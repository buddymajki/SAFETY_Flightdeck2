import * as admin from 'firebase-admin';
import { onDocumentCreated, onDocumentUpdated, onDocumentDeleted } from 'firebase-functions/v2/firestore';
import { setGlobalOptions } from 'firebase-functions/v2';

// Optional: tune region/concurrency defaults for all functions
setGlobalOptions({ region: 'us-central1' });

admin.initializeApp();

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
