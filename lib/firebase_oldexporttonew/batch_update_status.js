const admin = require('firebase-admin');
// Change the path below to the actual location of your service account key file
const serviceAccount = require('./serviceAccountKey.json'); // Example: if the file is in the same folder

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

async function batchUpdateFlightLogStatus() {
  const userId = 'TxSQCliQNlh1HcNdDMC72qP1u9W2';
  const baseCollection = db.collection('users').doc(userId).collection('flightlog');
  let lastDocId = null;
  let totalUpdated = 0;
  const pageSize = 200;

  try {
    while (true) {
      let query = baseCollection
        .where('status', '==', 'accepted')
        .orderBy(admin.firestore.FieldPath.documentId())
        .limit(pageSize);

      if (lastDocId) {
        query = query.startAfter(lastDocId);
      }

      const snapshot = await query.get();
      if (snapshot.empty) break;

      const batch = db.batch();
      snapshot.docs.forEach((doc) => {
        batch.update(doc.ref, { status: 'pending' });
      });
      await batch.commit();

      totalUpdated += snapshot.docs.length;
      console.log(`Updated ${snapshot.docs.length} documents in this batch, total updated: ${totalUpdated}`);

      if (snapshot.docs.length < pageSize) break;
      lastDocId = snapshot.docs[snapshot.docs.length - 1].id;
    }
    console.log(`Successfully updated ${totalUpdated} documents`);
    process.exit(0);
  } catch (error) {
    console.error('Error:', error);
    process.exit(1);
  }
}

batchUpdateFlightLogStatus();
