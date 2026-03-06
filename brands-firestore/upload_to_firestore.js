// Feltöltő script csak a gliders.json-hoz
// Használat előtt: npm install firebase-admin

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

// Itt add meg a saját serviceAccount kulcsod elérési útját
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

const glidersPath = path.join(__dirname, 'gliders.json');
const gliders = JSON.parse(fs.readFileSync(glidersPath, 'utf8'));

async function uploadGliders() {
  for (const glider of gliders) {
    const { id, ...data } = glider;
    await db.collection('gliders').doc(id).set(data);
    console.log(`Feltöltve: ${id}`);
  }
  console.log('Összes ernyő feltöltve!');
}

uploadGliders().catch(console.error);
