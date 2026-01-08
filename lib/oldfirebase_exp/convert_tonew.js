const fs = require('fs');

// -- Segédfüggvények --
function extractNameAndAltitude(str) {
  // Pl. "Büelen (1089m)" → {name: "Büelen", alt: 1089}
  if (typeof str !== 'string') return { name: str, alt: null };
  const m = str.match(/^(.+?) \((\d+)m\)$/);
  if (m) return { name: m[1].trim(), alt: parseInt(m[2], 10) };
  return { name: str.trim(), alt: null };
}

function parseIntString(s) {
  if (!s) return null;
  const num = String(s).match(/\d+/);
  return num ? parseInt(num[0], 10) : null;
}

function toISOStringOrNull(obj) {
  if (obj && typeof obj._seconds === 'number') {
    // Firestore unix timestamp
    return new Date(obj._seconds * 1000).toISOString().replace('.000Z','Z');
  }
  return null;
}

function dateToMidnightISO(dateStr) {
  // "2025-09-28" ⇒ midnight UTC
  if (!dateStr) return null;
  return `${dateStr}T00:00:00Z`;
}

// -- Feldolgozás --
function convertUser(old) {
  return {
    glider: old.glider || "",
    name: old.name,
    email: old.email,
    nickname: old.nickname,
    shvnumber: old.shvNumber,
    license: old.status
  };
}

function convertFlights(flightArr) {
  return flightArr.map(flight => {
    const takeoff = extractNameAndAltitude(flight.takeoff || '');
    const landing = extractNameAndAltitude(flight.landing || '');
    return {
      altitudeDifference: parseIntString(flight.altitudeDifference),
      comment: flight.comments || "",
      created_at: toISOStringOrNull(flight.createdAt),
      date: dateToMidnightISO(flight.date),
      flightTimeMinutes: parseIntString(flight.flightTime),
      landingAltitude: landing.alt,
      landingName: landing.name,
      status: "accepted",
      takeoffAltitude: takeoff.alt,
      takeoffName: takeoff.name
      // Az összes többi új mezőt csak akkor tölthetnénk, ha lenne az inputban!
    };
  });
}

// -- Main --
function main() {
  // 1. Fájlok neve
  const inputFile = 'judith_flights_info.json';
  const outputFile = 'judith_flights_info_converted.json';

  // 2. Bemenet beolvasása
  const raw = fs.readFileSync(inputFile, 'utf8');
  const source = JSON.parse(raw);

  // 3. Átalakítás
  const result = {
    user: convertUser(source),
    flightlog: convertFlights(source.flights || [])
  };

  // 4. Output kiírása
  fs.writeFileSync(outputFile, JSON.stringify(result, null, 2), 'utf8');
  console.log(`✅ Kész! Új fájl: ${outputFile}`);
}

main();