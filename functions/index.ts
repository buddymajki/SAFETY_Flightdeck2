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
// This scheduled function syncs a public Google Calendar into
// Firestore at schools/{SCHOOL_ID}/events/{gcalEventId}.
//
// SETUP REQUIREMENTS:
// 1. Enable "Google Calendar API" in GCP Console
// 2. Create a Service Account (or use the default Firebase one)
// 3. Share the Google Calendar with the Service Account email (read-only)
//    e.g. firebase-adminsdk-xxxxx@your-project.iam.gserviceaccount.com
// 4. Set the CALENDAR_ID and SCHOOL_ID below
// 5. npm install googleapis   (in /functions)
// 6. firebase deploy --only functions
//
// The calendar "FLYwithMIKI - Schooling days" is public with full event details,
// so we can also use the public calendar ID directly.
//
// To get the calendar ID:
// Google Calendar → Settings → "FLYwithMIKI - Schooling days" → Integrate calendar → Calendar ID
// It looks like: xxxxxxxxxxxxxxxxxxxx@group.calendar.google.com

// ── CONFIG (UPDATE THESE) ────────────────────────────────
const CALENDAR_ID = 'REPLACE_WITH_YOUR_GOOGLE_CALENDAR_ID@group.calendar.google.com';
const SCHOOL_ID = 'REPLACE_WITH_YOUR_SCHOOL_ID';
// ──────────────────────────────────────────────────────────

export const syncGoogleCalendar = onSchedule(
  {
    schedule: 'every 10 minutes',
    region: 'us-central1',
    timeoutSeconds: 60,
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

    if (CALENDAR_ID.startsWith('REPLACE')) {
      console.warn('[syncGoogleCalendar] CALENDAR_ID not configured – update index.ts');
      return;
    }

    try {
      const auth = new google.auth.GoogleAuth({
        scopes: ['https://www.googleapis.com/auth/calendar.readonly'],
      });

      const calendar = google.calendar({ version: 'v3', auth: await auth.getClient() });

      const now = new Date();
      const future = new Date();
      future.setDate(future.getDate() + 90); // Next 90 days

      const res = await calendar.events.list({
        calendarId: CALENDAR_ID,
        timeMin: now.toISOString(),
        timeMax: future.toISOString(),
        singleEvents: true,
        orderBy: 'startTime',
      });

      const events = res.data.items || [];
      const db = admin.firestore();
      const batch = db.batch();
      const eventsRef = db.collection('schools').doc(SCHOOL_ID).collection('events');

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
      console.log(`[syncGoogleCalendar] Synced ${events.length} events from Google Calendar`);
    } catch (error) {
      console.error('[syncGoogleCalendar] Error:', error);
    }
  }
);
