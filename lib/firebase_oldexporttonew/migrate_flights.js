/**
 * ============================================================================
 *  FlightDeck Firebase Flight Migration Script
 *  Migrates flight records (flightlog) from OLD Firestore → NEW Firestore
 * ============================================================================
 *
 *  OLD project:  flight-deck-3bb7b   (serviceAccountKey_old.json)
 *  NEW project:  flightdeck-v2       (serviceAccountKey.json)
 *
 *  IMPORTANT: Run migrate_users.js FIRST to ensure users exist in new Auth
 *             and are mapped in the database.
 *
 *  USAGE:
 *    1. npm install            (firebase-admin already in package.json)
 *    2. node migrate_flights.js
 *
 *  WHAT IT DOES (for each user in MIGRATION_USERS):
 *    - Reads all flight records from OLD Firestore: users/{oldUid}/flights
 *    - Transforms each flight according to field mapping rules (see below)
 *    - Writes to NEW Firestore: users/{newUid}/flightlog/{newGeneratedId}
 *    - Stores the old flight's ID as "legacyFlightId" for traceability
 *    - Idempotent: checks for existing legacyFlightId to prevent duplicates
 *
 *  FIELD TRANSFORMATION RULES (OLD → NEW):
 *    ─────────────────────────────────────────────────────────────────────
 *    Field Name Changes:
 *      comments          →  comment          (rename)
 *      createdAt         →  created_at       (rename)
 *      takeoff           →  takeoffName      (rename)
 *      landing           →  landingName      (rename)
 *      flightTime        →  flightTypeMinutes (rename + type conversion)
 *
 *    Field Value Transformations:
 *      altitudeDifference: "554m"  →  "554"   (remove "m" suffix, keep as string)
 *      flightTime: "42" (string)   →  42      (convert to number)
 *      stampedBy: <old_value>      →  "nZcTCdp6Y3Mwvr6rtHFe1xEf0NS2"
 *                                     (override with fixed school admin ID)
 *
 *    Fields Preserved As-Is:
 *      stamped, stampedAt, date (timestamp), all other fields
 *
 *    Fields Added to Every Flight:
 *      license_type          : "Student"              (license category)
 *      thisflight_school_id  : "7fOhpfnUZFYgBT7r9vYl" (school for this flight)
 *      status                : "accepted"             (flight approval status)
 *      mainschool_id         : "7fOhpfnUZFYgBT7r9vYl" (primary school ID)
 *      legacyFlightId        : <original_doc_id>      (for traceability)
 *      migratedAt            : <current_timestamp>    (migration timestamp)
 *
 *  IDEMPOTENCY:
 *    - Queries existing flights by legacyFlightId before writing.
 *    - If already migrated, updates with new values (merge: true).
 *    - Safe to re-run without creating duplicates.
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
  'old-flightdeck-flights'
);

// NEW Firebase app (target for writes)
const newApp = admin.initializeApp(
  {
    credential: admin.credential.cert(newServiceAccount),
  },
  'new-flightdeck-flights'
);

const oldDb = admin.firestore(oldApp);
const newDb = admin.firestore(newApp);

// ---------------------------------------------------------------------------
//  2. Pre-defined list of users to migrate  (same as main migration script)
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

// School/Admin identifiers (reuse from main migration)
const SCHOOL_ID = '7fOhpfnUZFYgBT7r9vYl';
const SCHOOL_ADMIN_UID = 'nZcTCdp6Y3Mwvr6rtHFe1xEf0NS2';
const LICENSE_TYPE = 'Student';
const DEFAULT_STATUS = 'accepted';

// ---------------------------------------------------------------------------
//  3. Field transformation logic
// ---------------------------------------------------------------------------

/**
 * Parses altitude difference string and returns numeric value.
 * OLD:  "554m"  →  NEW: "554"  (remove unit, keep as string for now)
 */
function transformAltitudeDifference(oldValue) {
  if (!oldValue) return oldValue;
  // Remove "m" or other units if present, return the number part as string
  return String(oldValue).replace(/[^\d.-]/g, '');
}

/**
 * Converts flightTime from string to number (minutes).
 * OLD:  "42"  →  NEW:  42  (numeric)
 */
function transformFlightTime(oldValue) {
  if (!oldValue) return 0;
  const num = parseInt(oldValue, 10);
  return isNaN(num) ? 0 : num;
}

/**
 * Transforms an OLD flight document into the NEW flight format.
 * 
 * For fields not explicitly mapped, they are copied as-is.
 * Then we override/add the mapped/required fields.
 */
function transformFlight(oldFlightData, oldFlightDocId) {
  const now = admin.firestore.Timestamp.now();

  // Start with all old data
  const newFlight = { ...oldFlightData };

  // ─── Field Renames ───
  // comments → comment
  if ('comments' in newFlight) {
    newFlight.comment = newFlight.comments;
    delete newFlight.comments;
  }

  // createdAt → created_at
  if ('createdAt' in newFlight) {
    newFlight.created_at = newFlight.createdAt;
    delete newFlight.createdAt;
  }

  // takeoff → takeoffName
  if ('takeoff' in newFlight) {
    newFlight.takeoffName = newFlight.takeoff;
    delete newFlight.takeoff;
  }

  // landing → landingName
  if ('landing' in newFlight) {
    newFlight.landingName = newFlight.landing;
    delete newFlight.landing;
  }

  // flightTime → flightTypeMinutes (with type conversion)
  if ('flightTime' in newFlight) {
    newFlight.flightTypeMinutes = transformFlightTime(newFlight.flightTime);
    delete newFlight.flightTime;
  }

  // ─── Field Value Transformations ───
  // altitudeDifference: remove unit suffix
  if ('altitudeDifference' in newFlight) {
    newFlight.altitudeDifference = transformAltitudeDifference(newFlight.altitudeDifference);
  }

  // stampedBy: override with the fixed school admin UID
  if ('stampedBy' in newFlight) {
    newFlight.stampedBy = SCHOOL_ADMIN_UID;
  }

  // ─── Add Required Fields (applied to all flights) ───
  newFlight.license_type = LICENSE_TYPE;
  newFlight.thisflight_school_id = SCHOOL_ID;
  newFlight.status = DEFAULT_STATUS;
  newFlight.mainschool_id = SCHOOL_ID;

  // ─── Traceability & Audit ───
  newFlight.legacyFlightId = oldFlightDocId;
  newFlight.migratedAt = now;

  return newFlight;
}

// ---------------------------------------------------------------------------
//  4. Helper – lookup newUid for a given email
// ---------------------------------------------------------------------------

/**
 * Queries the NEW Firestore to find the user's newUid by email.
 * Returns the newUid (doc ID) from the migrated user record.
 */
async function getNewUidByEmail(email) {
  const snapshot = await newDb
    .collection('users')
    .where('email', '==', email)
    .limit(1)
    .get();

  if (snapshot.empty) {
    throw new Error(`User not found in NEW DB with email: ${email}`);
  }

  return snapshot.docs[0].id;  // Return the document ID (newUid)
}

// ---------------------------------------------------------------------------
//  5. Helper – read flights from OLD Firestore
// ---------------------------------------------------------------------------

/**
 * Retrieves all flight documents for a given user from OLD Firestore.
 * Returns an array of { id: docId, ...flightData }
 */
async function getOldFlights(oldUid) {
  const snapshot = await oldDb
    .collection('users')
    .doc(oldUid)
    .collection('flights')
    .get();

  if (snapshot.empty) {
    return [];
  }

  return snapshot.docs.map(doc => ({
    id: doc.id,
    ...doc.data(),
  }));
}

// ---------------------------------------------------------------------------
//  6. Helper – check if flight already migrated (by legacyFlightId)
// ---------------------------------------------------------------------------

/**
 * Queries NEW Firestore to check if a flight with the given legacyFlightId
 * already exists for this user.
 * Returns the existing doc ID if found, null otherwise.
 */
async function findExistingFlight(newUid, legacyFlightId) {
  const snapshot = await newDb
    .collection('users')
    .doc(newUid)
    .collection('flightlog')
    .where('legacyFlightId', '==', legacyFlightId)
    .limit(1)
    .get();

  if (snapshot.empty) {
    return null;
  }

  return snapshot.docs[0].id;  // Return the doc ID
}

// ---------------------------------------------------------------------------
//  7. Helper – write flight to NEW Firestore
// ---------------------------------------------------------------------------

/**
 * Writes / updates a transformed flight to the NEW Firestore.
 * If newFlightDocId is provided, updates that doc.
 * Otherwise, lets Firestore auto-generate the document ID.
 */
async function writeNewFlight(newUid, transformedFlight, newFlightDocId = null) {
  const collectionRef = newDb
    .collection('users')
    .doc(newUid)
    .collection('flightlog');

  if (newFlightDocId) {
    // Update existing flight
    await collectionRef.doc(newFlightDocId).set(transformedFlight, { merge: true });
    return newFlightDocId;
  } else {
    // Create new flight with auto-generated ID
    const docRef = await collectionRef.add(transformedFlight);
    return docRef.id;
  }
}

// ---------------------------------------------------------------------------
//  8. Main migration loop
// ---------------------------------------------------------------------------

async function migrate() {
  console.log('='.repeat(70));
  console.log('  FlightDeck Flight Migration  –  OLD (flight-deck-3bb7b) → NEW (flightdeck-v2)');
  console.log('='.repeat(70));
  console.log(`  Users to process: ${MIGRATION_USERS.length}\n`);

  const results = {
    success: 0,
    updated: 0,
    skipped: 0,
    errors: [],
  };

  for (const { email, oldUid } of MIGRATION_USERS) {
    console.log(`\n─── Processing flights for: ${email}  (oldUid: ${oldUid}) ───`);

    try {
      // Step A – Get the newUid for this user in the NEW system
      const newUid = await getNewUidByEmail(email);
      console.log(`  ✔ Found user in new DB: ${email} → ${newUid}`);

      // Step B – Fetch all flights from OLD Firestore
      const oldFlights = await getOldFlights(oldUid);
      console.log(`  ℹ Found ${oldFlights.length} flight(s) in old DB`);

      if (oldFlights.length === 0) {
        console.log(`  ⓘ No flights to migrate for this user.`);
        continue;
      }

      // Step C – Process each flight
      for (const oldFlight of oldFlights) {
        const oldFlightDocId = oldFlight.id;

        try {
          // Check if this flight was already migrated
          const existingFlightDocId = await findExistingFlight(newUid, oldFlightDocId);

          // Transform the flight data
          const transformedFlight = transformFlight(oldFlight, oldFlightDocId);

          // Write to NEW Firestore
          const newFlightDocId = await writeNewFlight(
            newUid,
            transformedFlight,
            existingFlightDocId  // Pass existing ID if found (for update), null for new
          );

          if (existingFlightDocId) {
            console.log(`  ↻ Updated flight: ${oldFlightDocId} (newId: ${newFlightDocId})`);
            results.updated++;
          } else {
            console.log(`  ✔ Migrated flight: ${oldFlightDocId} (newId: ${newFlightDocId})`);
            results.success++;
          }
        } catch (err) {
          console.error(`    ✖ Error migrating flight ${oldFlightDocId}: ${err.message}`);
          results.errors.push({
            email,
            oldUid,
            flightId: oldFlightDocId,
            error: err.message,
          });
        }
      }
    } catch (err) {
      console.error(`  ✖ ERROR processing flights for ${email}: ${err.message}`);
      results.errors.push({
        email,
        oldUid,
        error: err.message,
      });
    }
  }

  // ── Summary ──
  console.log('\n' + '='.repeat(70));
  console.log('  Flight migration complete!');
  console.log(`    New flights    : ${results.success}`);
  console.log(`    Updated flights: ${results.updated}`);
  console.log(`    Errors         : ${results.errors.length}`);
  if (results.errors.length) {
    console.log('    Error details:');
    results.errors.forEach((e) => {
      console.log(`      - ${e.email} / ${e.flightId || 'user level'}: ${e.error}`);
    });
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
