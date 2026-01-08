const admin = require('firebase-admin');
const fs = require('fs');

// Service account kulcs betöltése
const serviceAccount = require('./serviceAccountKey.json');

// Firebase inicializálása
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  databaseURL: "https://flight-deck-3bb7b.firebaseio.com"
});

const db = admin.firestore();

const userId = 'DFoUf5Is4gYp3FzajuOxxV481rG2';

async function exportUserWithSubcollections() {
  const docRef = db.collection('users').doc(userId);
  const doc = await docRef.get();
  if (!doc.exists) {
    console.log('Nincs ilyen user!');
    return;
  }
  const userData = doc.data();

  // Alkollekciók lekérdezése
  const subcollections = await docRef.listCollections();
  for (const subcol of subcollections) {
    const subcolSnapshot = await subcol.get();
    userData[subcol.id] = [];
    subcolSnapshot.forEach(subdoc => {
      userData[subcol.id].push({ id: subdoc.id, ...subdoc.data() });
    });
  }

  fs.writeFileSync(`user_${userId}_full.json`, JSON.stringify(userData, null, 2));
  console.log('User + subcollections exportálva:', `user_${userId}_full.json`);
}

exportUserWithSubcollections();