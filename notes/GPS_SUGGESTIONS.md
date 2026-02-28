# GPS_SUGGESTIONS

...existing content...
# GPS Suggestions

## Battery saver toggle (concept)
- A 10s upload interval reduces radio and CPU wakeups, but the GPS chip can still run at ~1 Hz if the location stream is active.
- Battery savings mostly come from fewer network writes and less CPU work, not from the GPS chip itself unless the GPS update rate is also reduced.
- Expected impact during active tracking is moderate (roughly 10-30% improvement), depending on radio use, screen on/off, and device model.

## User-friendly tracking modes
- Off: No GPS tracking at all.
- Auto: Low-power monitoring until takeoff is detected (then switch to full tracking).
- Live: Full tracking for authority-grade visibility.

## Notes
- If authorities require all-day tracking, consider a clear "Authority Mode" with explicit consent and a persistent notification.
- For privacy-focused users, default to Auto and allow manual opt-in to Live mode.
- A simple toggle can map to Live vs Auto, while a separate master switch controls Off vs On.
