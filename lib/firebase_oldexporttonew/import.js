const admin = require('firebase-admin');
const fs = require('fs');

// Service account kulcs betöltése
const serviceAccount = require('./serviceAccountKey.json');

// Firebase inicializálása (új projekt!)
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  databaseURL: "https://flightdeck-v2.firebaseio.com"
});

const db = admin.firestore();

// Bemeneti JSON
const userId = 'JkkkpEKM8ia53kEhsGIO7cvXOoG3'; // vagy amit frissíteni akarsz
const data = JSON.parse(fs.readFileSync('upload_firestore_ready.json', 'utf8'));

// 1. User fő adatainak feltöltése (flightlog nélkül)
const { collections, ...userData } = data;
db.collection('users').doc(userId).set(userData)
  .then(async () => {
    console.log('User fő adatai feltöltve!');
    // 2. Flightlog feltöltése külön dokumentumokként
    if (collections && collections.flightlog && typeof collections.flightlog === 'object') {
      const flightlog = collections.flightlog;
      for (const [id, flight] of Object.entries(flightlog)) {
        await db.collection('users').doc(userId).collection('flightlog').doc(id).set(flight);
        console.log('Flight feltöltve:', id);
      }
      console.log('Minden flightlog feltöltve!');
    } else {
      console.log('Nincs flightlog adat!');
    }
    process.exit(0);
  })
  .catch(err => {
    console.error('Hiba a feltöltéskor:', err);
    process.exit(1);
  });