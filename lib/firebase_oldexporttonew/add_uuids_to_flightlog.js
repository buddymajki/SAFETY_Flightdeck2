// Node.js script to add a unique 'id' field to each flightlog entry in upload_with_ids.json
// and save the result as upload_with_ids_and_uuids.json

const fs = require('fs');
const { v4: uuidv4 } = require('uuid');

// Read the input JSON file
const inputPath = './lib/firebase_oldexporttonew/upload_with_ids.json';
const outputPath = './lib/firebase_oldexporttonew/upload_with_ids_and_uuids.json';

const data = JSON.parse(fs.readFileSync(inputPath, 'utf8'));

if (Array.isArray(data.flightlog)) {
  data.flightlog = data.flightlog.map(entry => ({
    ...entry,
    id: uuidv4()
  }));
}

fs.writeFileSync(outputPath, JSON.stringify(data, null, 2));

console.log(`Added unique IDs to ${data.flightlog.length} flightlog entries. Output written to ${outputPath}`);