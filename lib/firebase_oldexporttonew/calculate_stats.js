/**
 * ============================================================================
 *  FlightDeck Dashboard Stats Calculation Script
 *  Calculates and writes users/{uid}/stats/dashboard for migrated users
 * ============================================================================
 *
 *  NEW project:  flightdeck-v2  (serviceAccountKey.json)
 *
 *  USAGE:
 *    1. npm install          (firebase-admin already in package.json)
 *    2. node calculate_stats.js
 *
 *  PREREQUISITES:
 *    - migrate_users.js   has been run (users + checklists exist)
 *    - migrate_flights.js has been run (flightlog entries exist)
 *
 *  WHAT IT DOES (for each user in MIGRATION_USERS):
 *    1. Queries the new Firestore to find the user's newUid by email.
 *    2. Loads all flights from  users/{newUid}/flightlog/*
 *    3. Loads checklist progress from  users/{newUid}/checklistprogress/progress
 *    4. Loads the global checklist items from  globalChecklists  collection
 *    5. Calculates dashboard stats EXACTLY matching the Dart StatsService logic:
 *       - flightsCount, takeoffsCount (unique places), landingsCount (unique places)
 *       - flyingDays (unique calendar dates), airtimeMinutes, cummAltDiff
 *       - maneuverUsage (map of maneuver id → count)
 *       - startTypeUsage (map of startType id → count)
 *       - topTakeoffPlaces (top 10, sorted by count desc, each with name/id/count)
 *       - progress (total/checked/percentage + per-category breakdown)
 *    6. Writes the stats to  users/{newUid}/stats/dashboard  using set(merge)
 *
 *  IDEMPOTENCY:
 *    Safe to re-run. Overwrites stats with freshly calculated values.
 *
 * ============================================================================
 */

const admin = require('firebase-admin');

// ---------------------------------------------------------------------------
//  1. Initialize NEW Firebase app
// ---------------------------------------------------------------------------
const newServiceAccount = require('./serviceAccountKey.json');

const newApp = admin.initializeApp(
  {
    credential: admin.credential.cert(newServiceAccount),
  },
  'stats-calculator'
);

const db = admin.firestore(newApp);

// ---------------------------------------------------------------------------
//  2. Pre-defined list of users (same as migration scripts)
// ---------------------------------------------------------------------------
const MIGRATION_USERS = [
  { email: 'dr.renata.farkas@gmail.com' },
  { email: 'pedro.m.otao.pereira@gmail.com' },
  { email: 'platt.randall@gmail.com' },
  { email: 'daniel@schneider.dev' },
  { email: 'bukor000@gmail.com' },
  { email: 'nicolas.kamm@bluemail.ch' },
  { email: 'zsigmond.87@gmail.com' },
];

// ---------------------------------------------------------------------------
//  3. Helper – find newUid by email
// ---------------------------------------------------------------------------
async function getNewUidByEmail(email) {
  const snapshot = await db
    .collection('users')
    .where('email', '==', email)
    .limit(1)
    .get();
  if (snapshot.empty) {
    throw new Error(`User not found in Firestore with email: ${email}`);
  }
  return snapshot.docs[0].id;
}

// ---------------------------------------------------------------------------
//  4. Data loaders
// ---------------------------------------------------------------------------

/**
 * Load all flights from users/{uid}/flightlog.
 * Returns an array of flight objects parsed the same way as Flight.fromFirestore.
 */
async function loadFlights(uid) {
  const snapshot = await db
    .collection('users')
    .doc(uid)
    .collection('flightlog')
    .get();

  return snapshot.docs.map((doc) => {
    const data = doc.data();
    return {
      id: doc.id,
      // Parse date: Firestore Timestamp → ISO string, or keep string as-is
      date: parseDate(data.date),
      takeoffName: data.takeoffName || '',
      takeoffId: data.takeoffId || null,
      takeoffAltitude: parseDouble(data.takeoffAltitude),
      landingName: data.landingName || '',
      landingId: data.landingId || null,
      landingAltitude: parseDouble(data.landingAltitude),
      altitudeDifference: parseDouble(data.altitudeDifference),
      flightTimeMinutes: parseInt(data.flightTimeMinutes) || 0,
      comment: data.comment || null,
      startTypeId: data.startTypeId || null,
      flightTypeId: data.flightTypeId || null,
      // Arrays of maneuver IDs
      advancedManeuvers: Array.isArray(data.advancedManeuvers) ? data.advancedManeuvers : [],
      schoolManeuvers: Array.isArray(data.schoolManeuvers) ? data.schoolManeuvers : [],
      licenseType: data.license_type || 'student',
      status: data.status || 'pending',
      gpsTracked: data.gps_tracked || false,
    };
  });
}

/**
 * Load checklist progress from users/{uid}/checklistprogress/progress.
 * Returns a map of { itemId: { completed: bool, completedAt: ... } }
 */
async function loadChecklistProgress(uid) {
  const doc = await db
    .collection('users')
    .doc(uid)
    .collection('checklistprogress')
    .doc('progress')
    .get();
  if (!doc.exists) {
    return {};
  }
  return doc.data() || {};
}

/**
 * Load global checklist items from the globalChecklists collection.
 * Returns an array of { id, category, title_en, title_de, ... }
 */
async function loadGlobalChecklistItems() {
  const snapshot = await db.collection('globalChecklists').get();
  return snapshot.docs.map((doc) => ({
    id: doc.id,
    ...doc.data(),
  }));
}

// ---------------------------------------------------------------------------
//  5. Parse helpers (match Dart Flight._parseDate, _parseDouble)
// ---------------------------------------------------------------------------

/**
 * Parse a Firestore date field into an ISO 8601 string.
 * Matches Dart Flight._parseDate:
 *   - Timestamp → toDate().toISOString()
 *   - String → kept as-is
 *   - null → now
 */
function parseDate(raw) {
  if (!raw) return new Date().toISOString();
  // Firestore Timestamp object
  if (raw._seconds !== undefined || (raw.toDate && typeof raw.toDate === 'function')) {
    return raw.toDate().toISOString();
  }
  if (raw instanceof Date) return raw.toISOString();
  if (typeof raw === 'string') return raw;
  return new Date().toISOString();
}

/**
 * Parse a value to a float, matching Dart Flight._parseDouble.
 */
function parseDouble(value) {
  if (typeof value === 'number') return value;
  if (typeof value === 'string') {
    // Remove non-numeric suffixes like "m" (from altitude strings)
    const cleaned = value.replace(/[^\d.\-]/g, '');
    const num = parseFloat(cleaned);
    return isNaN(num) ? 0.0 : num;
  }
  return 0.0;
}

// ---------------------------------------------------------------------------
//  6. Stats calculation – mirrors Dart _calculateFlightStats exactly
// ---------------------------------------------------------------------------

/**
 * Calculate flight-related statistics.
 * Mirrors StatsService._calculateFlightStats from Dart.
 *
 *  Output fields:
 *    flightsCount      – total number of flights
 *    takeoffsCount     – number of UNIQUE takeoff places
 *    landingsCount     – number of UNIQUE landing places
 *    flyingDays        – number of UNIQUE calendar days with flights
 *    airtimeMinutes    – sum of all flightTimeMinutes
 *    cummAltDiff       – sum of all altitudeDifference (as int)
 *    maneuverUsage     – { maneuverName: count }
 *    startTypeUsage    – { startTypeId: count }
 *    topTakeoffPlaces  – top 10 takeoff places [ { name, id, count } ]
 */
function calculateFlightStats(flights) {
  const uniqueTakeoffs = new Set();
  const uniqueLandings = new Set();
  const uniqueDays = new Set();
  let totalMinutes = 0;
  let totalAltDiff = 0;
  const maneuverUsage = {};
  const startTypeUsage = {};
  const takeoffPlaceCounts = {};

  for (const flight of flights) {
    // Takeoffs – use ID if available, otherwise name (matches Dart logic)
    const takeoffKey =
      flight.takeoffId && flight.takeoffId.length > 0
        ? flight.takeoffId
        : flight.takeoffName;
    if (takeoffKey && takeoffKey.length > 0) {
      uniqueTakeoffs.add(takeoffKey);
    }

    // Landings – use ID if available, otherwise name
    const landingKey =
      flight.landingId && flight.landingId.length > 0
        ? flight.landingId
        : flight.landingName;
    if (landingKey && landingKey.length > 0) {
      uniqueLandings.add(landingKey);
    }

    // Flying days – parse date and build YYYY-MM-DD key
    try {
      const date = new Date(flight.date);
      if (!isNaN(date.getTime())) {
        const year = date.getFullYear();
        const month = String(date.getMonth() + 1).padStart(2, '0');
        const day = String(date.getDate()).padStart(2, '0');
        uniqueDays.add(`${year}-${month}-${day}`);
      }
    } catch (_) {
      // Skip unparseable dates (matches Dart catch block)
    }

    // Airtime
    totalMinutes += flight.flightTimeMinutes || 0;

    // Altitude difference (as integer, matching Dart .toInt())
    totalAltDiff += Math.floor(flight.altitudeDifference || 0);

    // Maneuver usage – combine advancedManeuvers + schoolManeuvers
    const allManeuvers = [
      ...(flight.advancedManeuvers || []),
      ...(flight.schoolManeuvers || []),
    ];
    for (const maneuver of allManeuvers) {
      maneuverUsage[maneuver] = (maneuverUsage[maneuver] || 0) + 1;
    }

    // Start type usage
    if (flight.startTypeId && flight.startTypeId.length > 0) {
      startTypeUsage[flight.startTypeId] =
        (startTypeUsage[flight.startTypeId] || 0) + 1;
    }

    // Takeoff place counts (for top-N calculation)
    if (takeoffKey && takeoffKey.length > 0) {
      takeoffPlaceCounts[takeoffKey] =
        (takeoffPlaceCounts[takeoffKey] || 0) + 1;
    }
  }

  // Sort and get top 10 takeoff places (descending by count)
  // Matches Dart: sortedTakeoffPlaces.take(10).map(...)
  const sortedTakeoffPlaces = Object.entries(takeoffPlaceCounts)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 10);

  const topTakeoffPlaces = sortedTakeoffPlaces.map(([key, count]) => {
    // Find the first flight that matches this takeoff key to get the name
    // Mirrors Dart: flights.firstWhere((f) => f.takeoffId == entry.key || f.takeoffName == entry.key)
    const matchingFlight = flights.find(
      (f) => f.takeoffId === key || f.takeoffName === key
    ) || flights[0]; // fallback to first flight (matches Dart orElse)

    return {
      name: matchingFlight ? matchingFlight.takeoffName : key,
      id: matchingFlight ? matchingFlight.takeoffId || null : null,
      count: count,
    };
  });

  return {
    flightsCount: flights.length,
    takeoffsCount: uniqueTakeoffs.size,
    landingsCount: uniqueLandings.size,
    flyingDays: uniqueDays.size,
    airtimeMinutes: totalMinutes,
    cummAltDiff: totalAltDiff,
    maneuverUsage,
    startTypeUsage,
    topTakeoffPlaces,
  };
}

// ---------------------------------------------------------------------------
//  7. Progress stats calculation – mirrors Dart _calculateProgressStatsFromItems
// ---------------------------------------------------------------------------

/**
 * Calculate progress statistics from checklist progress data and global items.
 * Mirrors StatsService._calculateProgressStatsFromItems from Dart.
 *
 * @param {Object} progressData  – from  checklistprogress/progress  doc
 *        Each key is itemId, value is { completed: bool, completedAt: ... }
 * @param {Array}  checklistItems – from  globalChecklists  collection
 *        Each item has { id, category, ... }
 *
 * Output matches ProgressStats.toJson():
 *   { total, checked, percentage, categories: { catId: { label, checked, total, percent } } }
 */
function calculateProgressStats(progressData, checklistItems) {
  // Group items by category (matches Dart itemsByCategory logic)
  const itemsByCategory = {};
  const categoryLabels = {};

  for (const item of checklistItems) {
    const itemId = item.id || '';
    const category = item.category || 'uncategorized';

    if (!itemId) continue;

    if (!itemsByCategory[category]) {
      itemsByCategory[category] = [];
    }
    itemsByCategory[category].push(itemId);

    // Store label if not already set (fallback to category id, matches Dart)
    if (!categoryLabels[category]) {
      categoryLabels[category] = category;
    }
  }

  // Calculate category progress
  const categories = {};
  let totalChecked = 0;

  for (const [categoryId, items] of Object.entries(itemsByCategory)) {
    let checkedCount = 0;

    for (const itemId of items) {
      const itemProgress = progressData[itemId];
      let isCompleted = false;

      if (itemProgress) {
        // Match Dart: itemProgress['completed'] as bool? ?? false
        isCompleted = itemProgress.completed === true;
      }

      if (isCompleted) {
        checkedCount++;
      }
    }

    totalChecked += checkedCount;
    const total = items.length;
    // Match Dart: ((checkedCount / total) * 100).round()
    const percent = total > 0 ? Math.round((checkedCount / total) * 100) : 0;

    categories[categoryId] = {
      label: categoryLabels[categoryId] || categoryId,
      checked: checkedCount,
      total: total,
      percent: percent,
    };
  }

  const totalItems = checklistItems.length;
  // Match Dart: ((totalChecked / totalItems) * 100).round()
  const overallPercent =
    totalItems > 0 ? Math.round((totalChecked / totalItems) * 100) : 0;

  return {
    total: totalItems,
    checked: totalChecked,
    percentage: overallPercent,
    categories: categories,
  };
}

// ---------------------------------------------------------------------------
//  8. Build the full DashboardStats JSON (matches DashboardStats.toJson())
// ---------------------------------------------------------------------------

/**
 * Assemble the full dashboard stats object, exactly matching DashboardStats.toJson().
 */
function buildDashboardStats(flightStats, progressStats) {
  return {
    flightsCount: flightStats.flightsCount,
    takeoffsCount: flightStats.takeoffsCount,
    landingsCount: flightStats.landingsCount,
    flyingDays: flightStats.flyingDays,
    airtimeMinutes: flightStats.airtimeMinutes,
    cummAltDiff: flightStats.cummAltDiff,
    progress: progressStats,
    maneuverUsage: flightStats.maneuverUsage,
    startTypeUsage: flightStats.startTypeUsage,
    topTakeoffPlaces: flightStats.topTakeoffPlaces, // already [{name,id,count},...]
    updatedAt: new Date().toISOString(), // Match Dart: DateTime.now().toIso8601String()
  };
}

// ---------------------------------------------------------------------------
//  9. Main
// ---------------------------------------------------------------------------

async function main() {
  console.log('='.repeat(70));
  console.log('  FlightDeck Stats Calculator  –  flightdeck-v2');
  console.log('='.repeat(70));

  // Load global checklist items once (shared across all users)
  console.log('\n  Loading globalChecklists collection...');
  const globalChecklistItems = await loadGlobalChecklistItems();
  console.log(`  ✔ Loaded ${globalChecklistItems.length} global checklist items\n`);

  const results = { success: 0, errors: [] };

  for (const { email } of MIGRATION_USERS) {
    console.log(`\n─── Calculating stats for: ${email} ───`);

    try {
      // Step 1: Find user UID
      const uid = await getNewUidByEmail(email);
      console.log(`  ✔ Found user: ${uid}`);

      // Step 2: Load flights
      const flights = await loadFlights(uid);
      console.log(`  ℹ Loaded ${flights.length} flights`);

      // Step 3: Load checklist progress
      const progressData = await loadChecklistProgress(uid);
      const progressKeys = Object.keys(progressData).length;
      console.log(`  ℹ Loaded ${progressKeys} checklist progress entries`);

      // Step 4: Calculate flight stats
      const flightStats = calculateFlightStats(flights);
      console.log(
        `  ℹ Flight stats: ${flightStats.flightsCount} flights, ` +
        `${flightStats.flyingDays} flying days, ` +
        `${flightStats.airtimeMinutes} min airtime, ` +
        `${flightStats.cummAltDiff}m altitude`
      );

      // Step 5: Calculate progress stats
      const progressStats = calculateProgressStats(
        progressData,
        globalChecklistItems
      );
      console.log(
        `  ℹ Progress: ${progressStats.checked}/${progressStats.total} ` +
        `(${progressStats.percentage}%) across ${Object.keys(progressStats.categories).length} categories`
      );

      // Step 6: Build and write dashboard stats
      const dashboardStats = buildDashboardStats(flightStats, progressStats);

      await db
        .collection('users')
        .doc(uid)
        .collection('stats')
        .doc('dashboard')
        .set(dashboardStats, { merge: true });

      console.log(`  ✔ Dashboard stats written to users/${uid}/stats/dashboard`);
      results.success++;
    } catch (err) {
      console.error(`  ✖ ERROR for ${email}: ${err.message}`);
      results.errors.push({ email, error: err.message });
    }
  }

  // Summary
  console.log('\n' + '='.repeat(70));
  console.log('  Stats calculation complete!');
  console.log(`    Successful : ${results.success}`);
  console.log(`    Errors     : ${results.errors.length}`);
  if (results.errors.length) {
    console.log('    Error details:');
    results.errors.forEach((e) =>
      console.log(`      - ${e.email}: ${e.error}`)
    );
  }
  console.log('='.repeat(70));
}

// ---------------------------------------------------------------------------
//  Run!
// ---------------------------------------------------------------------------
main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('Fatal error:', err);
    process.exit(1);
  });
