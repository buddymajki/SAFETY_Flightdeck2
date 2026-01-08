const fs = require('fs');
const { v4: uuidv4 } = require('uuid');

// Bemeneti/kimeneti fájlok
const inputFile = 'upload.json';
const outputFile = 'upload_with_ids.json';

// Bemeneti adat beolvasása
const data = JSON.parse(fs.readFileSync(inputFile, 'utf8'));

// Flights tömb javítása: minden flight kap egy id-t, ha nincs neki
const newFlights = (data.flights || []).map(flight => ({
  ...flight,
  id: flight.id || uuidv4()
}));

// Új szerkezet
const newData = {
  ...data,
  flights: newFlights
};

// Kimeneti adat kiírása
fs.writeFileSync(outputFile, JSON.stringify(newData, null, 2));
console.log('Minden flight kapott id-t! Eredmény:', outputFile);