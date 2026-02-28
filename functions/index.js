const admin = require("firebase-admin");
const {
  onDocumentCreated,
  onDocumentUpdated,
  onDocumentDeleted,
} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {setGlobalOptions} = require("firebase-functions/v2");

// Set default region for all functions
setGlobalOptions({region: "us-central1"});

admin.initializeApp();

// ============================================
// FLIGHT LOG TRIGGERS → PENDING FLIGHTS
// ============================================

// When a student creates a flight, copy it to the school's
// pendingFlights collection for instructor review.
exports.createPendingFlight = onDocumentCreated(
    "users/{uid}/flightlog/{logId}",
    async (event) => {
      const snap = event.data;
      if (!snap) return;
      const data = snap.data();
      const {uid, logId} = event.params;

      console.log("Flight log created:", {uid, logId});

      // Only create pending entry for students
      if (data.license_type !== "student") return;

      const schoolId = data.thisflight_school_id ||
        data.mainschool_id || data.school_id;
      if (!schoolId) {
        console.warn("No school_id on flight", logId);
        return;
      }

      const db = admin.firestore();
      const pendingRef = db.collection("schools")
          .doc(schoolId)
          .collection("pendingFlights")
          .doc(logId);

      await pendingRef.set({
        flightId: logId,
        student_uid: uid,
        school_id: schoolId,
        date: data.date || null,
        takeoffName: data.takeoffName || "",
        landingName: data.landingName || "",
        flightTimeMinutes: data.flightTimeMinutes || 0,
        altitudeDifference: data.altitudeDifference || 0,
        status: "pending",
        created_at: data.created_at ||
          admin.firestore.FieldValue.serverTimestamp(),
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      });

      console.log(`Pending flight created: ${schoolId}/${logId}`);
    },
);

// When a flight is updated, sync changes to pendingFlights
exports.onFlightLogUpdated = onDocumentUpdated(
    "users/{uid}/flightlog/{logId}",
    async (event) => {
      const after = event.data?.after.data();
      if (!after) return;
      const {logId} = event.params;

      const schoolId = after.thisflight_school_id ||
        after.mainschool_id || after.school_id;
      if (!schoolId) return;

      const db = admin.firestore();
      const pendingRef = db.collection("schools")
          .doc(schoolId)
          .collection("pendingFlights")
          .doc(logId);

      const pendingDoc = await pendingRef.get();
      if (!pendingDoc.exists) return;

      // Only update if still pending
      if (pendingDoc.data().status !== "pending") return;

      await pendingRef.update({
        date: after.date || null,
        takeoffName: after.takeoffName || "",
        landingName: after.landingName || "",
        flightTimeMinutes: after.flightTimeMinutes || 0,
        altitudeDifference: after.altitudeDifference || 0,
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      });

      console.log(`Pending flight updated: ${schoolId}/${logId}`);
    },
);

// When a flight is deleted, remove from pendingFlights too
exports.onFlightLogDeleted = onDocumentDeleted(
    "users/{uid}/flightlog/{logId}",
    async (event) => {
      const {uid, logId} = event.params;
      console.log("Flight log deleted:", {uid, logId});

      // Try to find and delete from all schools' pendingFlights
      const db = admin.firestore();
      const schoolsSnap = await db.collection("schools").get();

      for (const schoolDoc of schoolsSnap.docs) {
        const pendingRef = schoolDoc.ref
            .collection("pendingFlights").doc(logId);
        const pendingDoc = await pendingRef.get();
        if (pendingDoc.exists) {
          await pendingRef.delete();
          console.log(
              `Pending flight deleted: ${schoolDoc.id}/${logId}`,
          );
          break;
        }
      }
    },
);

exports.onUserProfileUpdated = onDocumentUpdated(
    "users/{uid}",
    (event) => {
      const before = event.data?.before.data();
      const after = event.data?.after.data();
      console.log("User profile updated:", {
        uid: event.params.uid,
        before,
        after,
      });
    },
);

// ============================================
// PENDING FLIGHTS CACHE (admin dashboard)
// ============================================

// Update the admin dashboard cache when pendingFlights change
exports.updatePendingFlightsCache = onDocumentCreated(
    "schools/{schoolId}/pendingFlights/{flightId}",
    async (event) => {
      const {schoolId} = event.params;
      await updateDashboardCache(schoolId);
    },
);

// Also update cache when a pending flight is modified
const onPendingUpdated = onDocumentUpdated(
    "schools/{schoolId}/pendingFlights/{flightId}",
    async (event) => {
      const {schoolId} = event.params;
      await updateDashboardCache(schoolId);
    },
);
exports.updatePendingFlightsCacheOnUpdate = onPendingUpdated;

// Also update cache when a pending flight is deleted
const onPendingDeleted = onDocumentDeleted(
    "schools/{schoolId}/pendingFlights/{flightId}",
    async (event) => {
      const {schoolId} = event.params;
      await updateDashboardCache(schoolId);
    },
);
exports.updatePendingFlightsCacheOnDelete = onPendingDeleted;

/**
 * Rebuild the admin dashboard cache for a school.
 * @param {string} schoolId - The school document ID.
 */
async function updateDashboardCache(schoolId) {
  const db = admin.firestore();
  const pendingSnap = await db.collection("schools")
      .doc(schoolId)
      .collection("pendingFlights")
      .where("status", "==", "pending")
      .get();

  const pendingCount = pendingSnap.size;
  const pendingFlights = pendingSnap.docs.map((doc) => ({
    id: doc.id,
    ...doc.data(),
  }));

  await db.collection("schools")
      .doc(schoolId)
      .collection("cache")
      .doc("adminDashboard")
      .set({
        pendingFlightsCount: pendingCount,
        pendingFlights: pendingFlights,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});

  console.log(
      `Dashboard cache updated: ${schoolId}, ` +
      `${pendingCount} pending`,
  );
}

// ============================================
// ADMIN CALLABLE FUNCTIONS
// ============================================

/**
 * Verify caller is admin of the school.
 * @param {object} auth - The auth context from the request.
 * @param {string} schoolId - The school document ID.
 * @return {object} The user data if authorized.
 */
async function verifySchoolAdmin(auth, schoolId) {
  if (!auth) {
    throw new HttpsError(
        "unauthenticated",
        "Must be authenticated",
    );
  }
  const db = admin.firestore();
  const userDoc = await db.collection("users")
      .doc(auth.uid).get();

  if (!userDoc.exists) {
    throw new HttpsError("not-found", "User not found");
  }

  const userData = userDoc.data();
  const role = userData.role || userData.license || "";
  const userSchool = userData.mainSchoolId ||
    userData.school_id || "";

  // Allow superadmin or school admin/instructor
  const isAdmin = role === "admin" || role === "superadmin" ||
    role === "instructor";
  const belongsToSchool = userSchool === schoolId;

  if (!isAdmin || (!belongsToSchool && role !== "superadmin")) {
    throw new HttpsError(
        "permission-denied",
        "Not authorized for this school",
    );
  }
  return userData;
}

/**
 * Accept a single pending flight
 * data: { schoolId, flightId }
 */
exports.acceptPendingFlightCallable = onCall(
    async (request) => {
      const {schoolId, flightId} = request.data;
      if (!schoolId || !flightId) {
        throw new HttpsError(
            "invalid-argument",
            "schoolId and flightId required",
        );
      }

      await verifySchoolAdmin(request.auth, schoolId);

      const db = admin.firestore();
      const pendingRef = db.collection("schools")
          .doc(schoolId)
          .collection("pendingFlights")
          .doc(flightId);

      const pendingDoc = await pendingRef.get();
      if (!pendingDoc.exists) {
        throw new HttpsError("not-found", "Flight not found");
      }

      const pendingData = pendingDoc.data();
      const studentUid = pendingData.student_uid;

      // Update status in student's flightlog
      const flightRef = db.collection("users")
          .doc(studentUid)
          .collection("flightlog")
          .doc(flightId);

      const batch = db.batch();
      batch.update(flightRef, {
        status: "accepted",
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      });
      batch.update(pendingRef, {
        status: "accepted",
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      });
      await batch.commit();

      console.log(`Flight accepted: ${schoolId}/${flightId}`);
      return {success: true, flightId};
    },
);

/**
 * Accept all pending flights for a school
 * data: { schoolId }
 */
exports.acceptAllPendingFlights = onCall(
    async (request) => {
      const {schoolId} = request.data;
      if (!schoolId) {
        throw new HttpsError(
            "invalid-argument",
            "schoolId required",
        );
      }

      await verifySchoolAdmin(request.auth, schoolId);

      const db = admin.firestore();
      const pendingSnap = await db.collection("schools")
          .doc(schoolId)
          .collection("pendingFlights")
          .where("status", "==", "pending")
          .get();

      if (pendingSnap.empty) {
        return {success: true, count: 0};
      }

      const batch = db.batch();
      let count = 0;

      for (const doc of pendingSnap.docs) {
        const data = doc.data();
        const studentUid = data.student_uid;

        // Update student's flightlog
        const flightRef = db.collection("users")
            .doc(studentUid)
            .collection("flightlog")
            .doc(doc.id);

        batch.update(flightRef, {
          status: "accepted",
          updated_at:
            admin.firestore.FieldValue.serverTimestamp(),
        });
        batch.update(doc.ref, {
          status: "accepted",
          updated_at:
            admin.firestore.FieldValue.serverTimestamp(),
        });
        count++;
      }

      await batch.commit();
      console.log(
          `All flights accepted: ${schoolId}, count=${count}`,
      );
      return {success: true, count};
    },
);

/**
 * Decline a pending flight
 * data: { schoolId, flightId }
 */
exports.declinePendingFlight = onCall(
    async (request) => {
      const {schoolId, flightId} = request.data;
      if (!schoolId || !flightId) {
        throw new HttpsError(
            "invalid-argument",
            "schoolId and flightId required",
        );
      }

      await verifySchoolAdmin(request.auth, schoolId);

      const db = admin.firestore();
      const pendingRef = db.collection("schools")
          .doc(schoolId)
          .collection("pendingFlights")
          .doc(flightId);

      const pendingDoc = await pendingRef.get();
      if (!pendingDoc.exists) {
        throw new HttpsError("not-found", "Flight not found");
      }

      // Delete the pending entry (flight stays in
      // student's log with pending status)
      await pendingRef.delete();

      console.log(`Flight declined: ${schoolId}/${flightId}`);
      return {success: true, flightId};
    },
);

// ============================================
// CLEANUP STALE PENDING FLIGHTS
// ============================================

// Run daily to clean up pending flights older than 90 days
exports.cleanupStalePendingFlights = onSchedule(
    {
      schedule: "every day 03:00",
      region: "us-central1",
      timeoutSeconds: 120,
    },
    async () => {
      const db = admin.firestore();
      const cutoff = new Date();
      cutoff.setDate(cutoff.getDate() - 90);

      const schoolsSnap = await db.collection("schools").get();
      let totalCleaned = 0;

      for (const schoolDoc of schoolsSnap.docs) {
        const staleSnap = await schoolDoc.ref
            .collection("pendingFlights")
            .where("status", "==", "pending")
            .where("created_at", "<", cutoff)
            .get();

        if (staleSnap.empty) continue;

        const batch = db.batch();
        for (const doc of staleSnap.docs) {
          batch.delete(doc.ref);
        }
        await batch.commit();
        totalCleaned += staleSnap.size;
      }

      console.log(
          `Cleanup: removed ${totalCleaned} stale pending`,
      );
    },
);

// ============================================
// GOOGLE CALENDAR → FIRESTORE SYNC
// ============================================
//
// Reads gcalCalendarId from each school doc in Firestore.
//
// SETUP:
// 1. Enable "Google Calendar API" in GCP Console
// 2. Share Google Calendar with the Firebase SA email
// 3. Set gcalCalendarId on school doc in Firestore

exports.syncGoogleCalendar = onSchedule(
    {
      schedule: "every 10 minutes",
      region: "us-central1",
      timeoutSeconds: 120,
    },
    async () => {
      let google;
      try {
        google = require("googleapis").google;
      } catch (e) {
        console.warn("[syncGoogleCalendar] googleapis not installed");
        return;
      }

      const db = admin.firestore();

      const schoolsSnap = await db.collection("schools")
          .where("gcalCalendarId", "!=", "")
          .get();

      if (schoolsSnap.empty) {
        console.log("[syncGoogleCalendar] No schools with gcalCalendarId");
        return;
      }

      try {
        const auth = new google.auth.GoogleAuth({
          scopes: ["https://www.googleapis.com/auth/calendar.readonly"],
        });
        const authClient = await auth.getClient();
        const calendar = google.calendar({version: "v3", auth: authClient});

        for (const schoolDoc of schoolsSnap.docs) {
          const schoolId = schoolDoc.id;
          const calendarId = schoolDoc.data().gcalCalendarId;
          if (!calendarId) continue;

          console.log(`[syncGoogleCalendar] Syncing school=${schoolId}`);

          try {
            const now = new Date();
            const future = new Date();
            future.setDate(future.getDate() + 90);

            const res = await calendar.events.list({
              calendarId: calendarId,
              timeMin: now.toISOString(),
              timeMax: future.toISOString(),
              singleEvents: true,
              orderBy: "startTime",
            });

            const events = res.data.items || [];
            const batch = db.batch();
            const eventsRef = db.collection("schools")
                .doc(schoolId).collection("events");

            for (const gcalEvent of events) {
              if (!gcalEvent.id) continue;
              const docRef = eventsRef.doc(gcalEvent.id);
              batch.set(
                  docRef,
                  {
                    gcalId: gcalEvent.id,
                    title: gcalEvent.summary || "",
                    description: gcalEvent.description || "",
                    location: gcalEvent.location || "",
                    startTime: gcalEvent.start?.dateTime ||
                      gcalEvent.start?.date || "",
                    endTime: gcalEvent.end?.dateTime ||
                      gcalEvent.end?.date || "",
                    status: gcalEvent.status === "cancelled" ?
                      "cancelled" : "active",
                    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                    source: "google_calendar",
                  },
                  {merge: true},
              );
            }

            // Mark disappeared events as cancelled
            const existingSnap = await eventsRef
                .where("source", "==", "google_calendar").get();
            const gcalIds = new Set(events.map((e) => e.id));
            for (const doc of existingSnap.docs) {
              if (!gcalIds.has(doc.id) &&
                  doc.data().status !== "cancelled") {
                batch.update(doc.ref, {status: "cancelled"});
              }
            }

            await batch.commit();
            console.log(
                `[syncGoogleCalendar] School ${schoolId}: ` +
                `synced ${events.length} events`,
            );
          } catch (schoolError) {
            console.error(
                `[syncGoogleCalendar] Error school ${schoolId}:`,
                schoolError,
            );
          }
        }
      } catch (error) {
        console.error("[syncGoogleCalendar] Error:", error);
      }
    },
);
