import * as admin from 'firebase-admin';
import { onDocumentCreated, onDocumentUpdated, onDocumentDeleted } from 'firebase-functions/v2/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { setGlobalOptions } from 'firebase-functions/v2';

// Optional: tune region/concurrency defaults for all functions
setGlobalOptions({ region: 'us-central1' });

admin.initializeApp();

// ============================================
// FLIGHT LOG TRIGGERS
// ============================================

// Template: react to new flight log entries
export const onFlightLogCreated = onDocumentCreated('users/{uid}/flightlog/{logId}', (event) => {
  const snap = event.data;
  if (!snap) return;
  const data = snap.data();
  console.log('Flight log created:', { uid: event.params.uid, logId: event.params.logId, data });
});

// Template: react to profile updates
export const onUserProfileUpdated = onDocumentUpdated('users/{uid}', (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  console.log('User profile updated:', { uid: event.params.uid, before, after });
});

// Template: react to flight log deletion
export const onFlightLogDeleted = onDocumentDeleted('users/{uid}/flightlog/{logId}', (event) => {
  console.log('Flight log deleted:', { uid: event.params.uid, logId: event.params.logId });
});

// ============================================
// GOOGLE CALENDAR → FIRESTORE SYNC
// ============================================
//
// This scheduled function syncs Google Calendar events into Firestore.
// It reads the calendarId from each school document in Firestore,
// so each school can have its own Google Calendar.
//
// Firestore schema:
//   schools/{schoolId}.gcalCalendarId = "xxxxx@group.calendar.google.com"
//
// SETUP REQUIREMENTS:
// 1. Enable "Google Calendar API" in GCP Console for your Firebase project
// 2. Find your Service Account email:
//    Firebase Console → Project Settings (⚙️) → Service accounts tab
//    → "Firebase Admin SDK" → shows email like:
//    firebase-adminsdk-xxxxx@your-project.iam.gserviceaccount.com
// 3. Share the Google Calendar with that Service Account email
//    Google Calendar → Settings → "FLYwithMIKI" → Share with specific people → Add → paste SA email → "See all event details"
// 4. Set the gcalCalendarId field on the school doc in Firestore
// 5. npm install googleapis   (in /functions)
// 6. firebase deploy --only functions

export const syncGoogleCalendar = onSchedule(
  {
    schedule: 'every 10 minutes',
    region: 'us-central1',
    timeoutSeconds: 120,
  },
  async () => {
    // Dynamic import so the function still deploys even if googleapis isn't installed yet
    let google: any;
    try {
      google = (await import('googleapis')).google;
    } catch {
      console.warn('[syncGoogleCalendar] googleapis not installed – run: cd functions && npm install googleapis');
      return;
    }

    const db = admin.firestore();

    // Find all schools that have a Google Calendar configured
    const schoolsSnap = await db.collection('schools')
      .where('gcalCalendarId', '!=', '')
      .get();

    if (schoolsSnap.empty) {
      console.log('[syncGoogleCalendar] No schools with gcalCalendarId configured');
      return;
    }

    try {
      const auth = new google.auth.GoogleAuth({
        scopes: ['https://www.googleapis.com/auth/calendar.readonly'],
      });
      const authClient = await auth.getClient();
      const calendar = google.calendar({ version: 'v3', auth: authClient });

      // Process each school
      for (const schoolDoc of schoolsSnap.docs) {
        const schoolId = schoolDoc.id;
        const calendarId = schoolDoc.data().gcalCalendarId;

        if (!calendarId) continue;

        console.log(`[syncGoogleCalendar] Syncing school=${schoolId}, calendar=${calendarId}`);

        try {
          const now = new Date();
          const future = new Date();
          future.setDate(future.getDate() + 90); // Next 90 days

          const res = await calendar.events.list({
            calendarId: calendarId,
            timeMin: now.toISOString(),
            timeMax: future.toISOString(),
            singleEvents: true,
            orderBy: 'startTime',
          });

          const events = res.data.items || [];
          const batch = db.batch();
          const eventsRef = db.collection('schools').doc(schoolId).collection('events');

          for (const gcalEvent of events) {
            if (!gcalEvent.id) continue;

            const docRef = eventsRef.doc(gcalEvent.id);
            batch.set(
              docRef,
              {
                gcalId: gcalEvent.id,
                title: gcalEvent.summary || '',
                description: gcalEvent.description || '',
                location: gcalEvent.location || '',
                startTime: gcalEvent.start?.dateTime || gcalEvent.start?.date || '',
                endTime: gcalEvent.end?.dateTime || gcalEvent.end?.date || '',
                status: gcalEvent.status === 'cancelled' ? 'cancelled' : 'active',
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                source: 'google_calendar',
              },
              { merge: true } // Don't overwrite registrations sub-collection
            );
          }

          // Mark events that disappeared from GCal as cancelled
          const existingSnap = await eventsRef.where('source', '==', 'google_calendar').get();
          const gcalIds = new Set(events.map((e: any) => e.id));
          for (const doc of existingSnap.docs) {
            if (!gcalIds.has(doc.id) && doc.data().status !== 'cancelled') {
              batch.update(doc.ref, { status: 'cancelled' });
            }
          }

          await batch.commit();
          console.log(`[syncGoogleCalendar] School ${schoolId}: synced ${events.length} events`);
        } catch (schoolError) {
          console.error(`[syncGoogleCalendar] Error syncing school ${schoolId}:`, schoolError);
          // Continue with next school
        }
      }
    } catch (error) {
      console.error('[syncGoogleCalendar] Error:', error);
    }
  }
);
