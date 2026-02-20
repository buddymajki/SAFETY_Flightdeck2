/**
 * ============================================================================
 *  FlightDeck Flightlog Cleanup Script
 *  Removes obsolete 'takeoff' and 'landing' fields from all migrated flights
 *  in the new Firestore system for all users in MIGRATION_USERS.
 * ============================================================================
 *
 *  USAGE:
 *    node cleanup_flightlog_fields.js
 *
 *  This script is idempotent and safe to run multiple times.
 * ============================================================================
 */

const admin = require('firebase-admin');

// ---------------------------------------------------------------------------
//  1. Initialize NEW Firebase app (target for cleanup)
// ---------------------------------------------------------------------------
const newServiceAccount = require('./serviceAccountKey.json');
const newApp = admin.initializeApp(
  {
    credential: admin.credential.cert(newServiceAccount),
  },
  'cleanup-flightdeck-flights'
);
const newDb = admin.firestore(newApp);

// ---------------------------------------------------------------------------
//  2. Pre-defined list of users to clean up (same as migration)
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
//  3. Helper – lookup newUid for a given email
// ---------------------------------------------------------------------------
async function getNewUidByEmail(email) {
  const snapshot = await newDb
    .collection('users')
    .where('email', '==', email)
    .limit(1)
    .get();
  if (snapshot.empty) {
    throw new Error(`User not found in NEW DB with email: ${email}`);
  }
  return snapshot.docs[0].id;
}

// ---------------------------------------------------------------------------
//  4. Main cleanup loop
// ---------------------------------------------------------------------------
async function cleanup() {
  console.log('='.repeat(70));
  console.log('  FlightDeck Flightlog Cleanup – Removing obsolete fields');
  console.log('='.repeat(70));
  for (const { email } of MIGRATION_USERS) {
    try {
      const newUid = await getNewUidByEmail(email);
      const flightlogRef = newDb.collection('users').doc(newUid).collection('flightlog');
      const flightsSnap = await flightlogRef.get();
      if (flightsSnap.empty) {
        console.log(`  ⓘ No flights for user: ${email}`);
        continue;
      }
      let cleaned = 0;
      for (const doc of flightsSnap.docs) {
        const data = doc.data();
        if ('takeoff' in data || 'landing' in data) {
          await doc.ref.update({
            takeoff: admin.firestore.FieldValue.delete(),
            landing: admin.firestore.FieldValue.delete(),
          });
          cleaned++;
        }
      }
      console.log(`  ✔ Cleaned ${cleaned} flights for user: ${email}`);
    } catch (err) {
      console.error(`  ✖ ERROR cleaning flights for ${email}: ${err.message}`);
    }
  }
  console.log('='.repeat(70));
  console.log('  Cleanup complete!');
  console.log('='.repeat(70));
}

cleanup()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('Fatal error:', err);
    process.exit(1);
  });
