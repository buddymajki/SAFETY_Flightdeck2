// Node.js script to restructure upload_with_ids_and_uuids.json for Firestore import
// - Moves all fields under "user" to the root
// - Moves each flightlog entry to a new object under "collections.flightlog", keyed by its id
// - Output: upload_firestore_ready.json

const fs = require('fs');

const inputPath = './lib/firebase_oldexporttonew/upload_with_ids_and_uuids.json';
const outputPath = './lib/firebase_oldexporttonew/upload_firestore_ready.json';

const data = JSON.parse(fs.readFileSync(inputPath, 'utf8'));

const result = { ...data.user, collections: { flightlog: {} } };

if (Array.isArray(data.flightlog)) {
  data.flightlog.forEach(entry => {
    if (entry.id) {
      result.collections.flightlog[entry.id] = { ...entry };
    }
  });
}

fs.writeFileSync(outputPath, JSON.stringify(result, null, 2));

console.log(`Restructured JSON for Firestore import. Output written to ${outputPath}`);