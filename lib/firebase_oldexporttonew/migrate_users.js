/**
 * ============================================================================
 *  FlightDeck Firebase Migration Script
 *  Migrates specific users + checklist data from OLD Firestore → NEW Firestore
 * ============================================================================
 *
 *  OLD project:  flight-deck-3bb7b   (serviceAccountKey_old.json)
 *  NEW project:  flightdeck-v2       (serviceAccountKey.json)
 *
 *  USAGE:
 *    1. npm install            (firebase-admin + uuid already in package.json)
 *    2. node migrate_users.js
 *
 *  WHAT IT DOES (for each user in MIGRATION_USERS):
 *    - Looks up / creates the user in NEW Firebase Auth
 *    - Reads  OLD Firestore  users/{oldUid}         → writes NEW Firestore  users/{newUid}
 *    - Reads  OLD Firestore  checklists/{oldUid}     → writes NEW Firestore  users/{newUid}/checklistprogress/progress
 *    - Stores legacyUid in the new user document
 *
 *  CHECKLIST FIELD MAPPING:
 *    OLD flat boolean fields → NEW map fields with {completed, completedAt}
 *
 *    Prefix renames:
 *      ex-N   →  exam-N          (e.g. ex-0 → exam-0)
 *
 *    All other prefixes remain unchanged:
 *      gh-bas-N  →  gh-bas-N
 *      gh-adv-N  →  gh-adv-N
 *      hf-bas-N  →  hf-bas-N
 *      hf-adv-N  →  hf-adv-N
 *      ... etc.
 *
 *    Value transformation:
 *      true   →  { completed: true,  completedAt: <current Firestore Timestamp> }
 *      false  →  { completed: false, completedAt: null }
 *
 *  IDEMPOTENCY:
 *    - Auth: uses getUser-by-email first; only creates if not found.
 *    - Firestore writes use set() with { merge: true } so re-runs don't
 *      destroy data that was added after the first migration.
 *
 * ============================================================================
 */

const admin = require('firebase-admin');

// ---------------------------------------------------------------------------
//  1. Initialize BOTH Firebase apps (old + new)
// ---------------------------------------------------------------------------
const oldServiceAccount = require('./serviceAccountKey_old.json');
const newServiceAccount = require('./serviceAccountKey.json');

// OLD Firebase app (read-only source)
const oldApp = admin.initializeApp(
  {
    credential: admin.credential.cert(oldServiceAccount),
  },
  'old-flightdeck'                 // give it a name so it doesn't clash
);

// NEW Firebase app (target for Auth + Firestore writes)
const newApp = admin.initializeApp(
  {
    credential: admin.credential.cert(newServiceAccount),
  },
  'new-flightdeck'
);

const oldDb = admin.firestore(oldApp);   // Firestore of old project
const newDb = admin.firestore(newApp);   // Firestore of new project
const newAuth = admin.auth(newApp);      // Auth of new project

// ---------------------------------------------------------------------------
//  2. Pre-defined list of users to migrate  (email → oldUid)
// ---------------------------------------------------------------------------
const MIGRATION_USERS = [
  { email: 'dr.renata.farkas@gmail.com',       oldUid: '6CmEjZWb9QUfNKY76xjHWlkIc7o1' },
  { email: 'pedro.m.otao.pereira@gmail.com',   oldUid: '6vI06C4fQwW3z9LwxMlnIL7Rp3H2' },
  { email: 'platt.randall@gmail.com',           oldUid: 'Yhp0MtiXGsb0FthVOodUkJ1I6VO2' },
  { email: 'daniel@schneider.dev',              oldUid: 'gWfB2yc3MlT3NwGWQTaRqZEpmPs2' },
  { email: 'bukor000@gmail.com',                oldUid: 'nXsOaHjZxWcuaqxlrl7nuzXN2Le2' },
  { email: 'nicolas.kamm@bluemail.ch',          oldUid: 'oOKGMxivlwS219BCouIud9A4VCM2' },
  { email: 'zsigmond.87@gmail.com',             oldUid: 'zB55YFLLvCSPHfoNgMUt2lGN6Ff1' },
];

// ---------------------------------------------------------------------------
//  3. Checklist key-mapping logic
// ---------------------------------------------------------------------------

/**
 * Renames OLD checklist field keys to the NEW naming convention.
 *
 * Known rename rules (add more here if needed):
 *   ex-N  →  exam-N
 *
 * Everything else keeps its original key.
 */
function renameChecklistKey(oldKey) {
  // ex-0, ex-1, ... ex-9  →  exam-0, exam-1, ... exam-9
  if (/^ex-\d+$/.test(oldKey)) {
    return oldKey.replace(/^ex-/, 'exam-');
  }
  // All other keys pass through unchanged
  // (gh-bas-N, gh-adv-N, hf-bas-N, hf-adv-N, etc.)
  return oldKey;
}

/**
 * Transforms a flat boolean checklist map from the OLD format into the NEW
 * nested-map format.
 *
 * OLD:  { "ex-0": false, "gh-bas-0": true, ... }
 * NEW:  { "exam-0": { completed: false, completedAt: null },
 *         "gh-bas-0": { completed: true, completedAt: <Timestamp> }, ... }
 */
function transformChecklist(oldData) {
  const now = admin.firestore.Timestamp.now();
  const newData = {};

  for (const [oldKey, value] of Object.entries(oldData)) {
    const newKey = renameChecklistKey(oldKey);
    const completed = value === true;
    newData[newKey] = {
      completed,
      completedAt: completed ? now : null,
    };
  }

  return newData;
}

// ---------------------------------------------------------------------------
//  4. Helper – ensure user exists in NEW Auth, return newUid
// ---------------------------------------------------------------------------

/**
 * Looks up the user by email in the NEW Firebase Auth.
 * If found, returns the existing UID.
 * If not found, creates the user with a random temporary password and returns
 * the new UID.  The user should be sent a password-reset email afterwards.
 */
async function ensureUserInNewAuth(email) {
  try {
    const userRecord = await newAuth.getUserByEmail(email);
    console.log(`  ✔ User already exists in new Auth: ${email} → ${userRecord.uid}`);
    return userRecord.uid;
  } catch (err) {
    if (err.code === 'auth/user-not-found') {
      // Generate a random 24-char password (user should reset)
      const tempPassword = require('crypto').randomBytes(18).toString('base64');
      const newUser = await newAuth.createUser({
        email,
        password: tempPassword,
        emailVerified: false,
      });
      console.log(`  ✚ Created user in new Auth: ${email} → ${newUser.uid} (temp password – send reset!)`);
      return newUser.uid;
    }
    throw err;   // unexpected error – bubble up
  }
}

// ---------------------------------------------------------------------------
//  5. Helper – read data from OLD Firestore
// ---------------------------------------------------------------------------

async function getOldUserData(oldUid) {
  const snap = await oldDb.collection('users').doc(oldUid).get();
  if (!snap.exists) {
    console.log(`  ⚠ No user document found in OLD DB for uid: ${oldUid}`);
    return null;
  }
  return snap.data();
}

async function getOldChecklistData(oldUid) {
  const snap = await oldDb.collection('checklists').doc(oldUid).get();
  if (!snap.exists) {
    console.log(`  ⚠ No checklist document found in OLD DB for uid: ${oldUid}`);
    return null;
  }
  return snap.data();
}

// ---------------------------------------------------------------------------
//  6. Helper – write data to NEW Firestore
// ---------------------------------------------------------------------------

/**
 * Writes / merges the user document into  users/{newUid}  in the NEW Firestore.
 * Adds the legacyUid field so we can always trace back.
 */
async function writeNewUserData(newUid, oldUid, oldUserData) {
  const ref = newDb.collection('users').doc(newUid);

  // Build the payload – start from the old data, add/overwrite with legacyUid
  const payload = {
    ...oldUserData,
    legacyUid: oldUid,
    migratedAt: admin.firestore.Timestamp.now(),
    // Add school identifiers for all migrated users
    mainschool_id: '7fOhpfnUZFYgBT7r9vYl',
    school_id: '7fOhpfnUZFYgBT7r9vYl',
    license: 'Student',
  };

  // Remove fields that should not be blindly copied (add more exclusions as needed)
  // For example the old UID if it was stored as a field:
  // delete payload.uid;

  await ref.set(payload, { merge: true });
  console.log(`  ✔ User data written to users/${newUid}`);
}

/**
 * Writes the converted checklist data into
 *   users/{newUid}/checklistprogress/progress
 * using set({ merge: true }) for idempotency.
 */
async function writeNewChecklistData(newUid, convertedChecklist) {
  const ref = newDb
    .collection('users').doc(newUid)
    .collection('checklistprogress').doc('progress');

  await ref.set(convertedChecklist, { merge: true });
  console.log(`  ✔ Checklist data written to users/${newUid}/checklistprogress/progress`);
}

// ---------------------------------------------------------------------------
//  7. Main migration loop
// ---------------------------------------------------------------------------

async function migrate() {
  console.log('='.repeat(70));
  console.log('  FlightDeck Migration  –  OLD (flight-deck-3bb7b) → NEW (flightdeck-v2)');
  console.log('='.repeat(70));
  console.log(`  Users to process: ${MIGRATION_USERS.length}\n`);

  const results = { success: 0, skipped: 0, errors: [] };

  for (const { email, oldUid } of MIGRATION_USERS) {
    console.log(`\n─── Processing: ${email}  (oldUid: ${oldUid}) ───`);

    try {
      // Step A – ensure user exists in NEW Auth
      const newUid = await ensureUserInNewAuth(email);

      // Step B – read old user data
      const oldUserData = await getOldUserData(oldUid);
      if (oldUserData) {
        await writeNewUserData(newUid, oldUid, oldUserData);
      } else {
        // Even if there's no old user doc, still store the legacyUid + school fields
        await newDb.collection('users').doc(newUid).set(
          {
            legacyUid: oldUid,
            email,
            migratedAt: admin.firestore.Timestamp.now(),
            mainschool_id: '7fOhpfnUZFYgBT7r9vYl',
            school_id: '7fOhpfnUZFYgBT7r9vYl',
          },
          { merge: true }
        );
        console.log(`  ✔ Minimal user doc written (no old data found)`);
      }

      // Step C – read & transform old checklist data
      const oldChecklist = await getOldChecklistData(oldUid);
      if (oldChecklist) {
        const converted = transformChecklist(oldChecklist);
        await writeNewChecklistData(newUid, converted);
      } else {
        console.log(`  ⓘ No checklist to migrate for this user.`);
      }

      results.success++;
    } catch (err) {
      console.error(`  ✖ ERROR migrating ${email}: ${err.message}`);
      results.errors.push({ email, oldUid, error: err.message });
    }
  }

  // ── Summary ──
  console.log('\n' + '='.repeat(70));
  console.log('  Migration complete!');
  console.log(`    Successful : ${results.success}`);
  console.log(`    Errors     : ${results.errors.length}`);
  if (results.errors.length) {
    console.log('    Error details:');
    results.errors.forEach((e) => console.log(`      - ${e.email}: ${e.error}`));
  }
  console.log('='.repeat(70));
}

// ---------------------------------------------------------------------------
//  Run!
// ---------------------------------------------------------------------------
migrate()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('Fatal error:', err);
    process.exit(1);
  });
