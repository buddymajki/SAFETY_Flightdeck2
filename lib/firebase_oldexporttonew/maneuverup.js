const admin = require("firebase-admin");
const fs = require("fs");
const path = require("path");

// A serviceAccount kulcs path-ja
const serviceAccount = require("./serviceAccountKey.json"); // Saját kulcsod neve ide

// Inicializálás
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

// Ezt a fájlt akarjuk feltölteni
const maneuversPath = path.join(__dirname, "globalManeuvers.json");
const maneuversData = JSON.parse(fs.readFileSync(maneuversPath, "utf-8"));

const collectionName = "globalManeuvers";

async function upload() {
  const batch = db.batch();
  let count = 0;
  for (const [id, data] of Object.entries(maneuversData)) {
    const docRef = db.collection(collectionName).doc(id);
    batch.set(docRef, data);
    count++;
  }
  await batch.commit();
  console.log(`✅ ${count} manőver feltöltve a '${collectionName}' gyűjteménybe!`);
  process.exit(0);
}

upload().catch(err => {
  console.error(err);
  process.exit(1);
});