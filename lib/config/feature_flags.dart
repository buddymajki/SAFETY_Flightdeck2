/// Build-time switches for features that are temporarily out of service.
///
/// Keeping the feature code in the tree behind a flag (instead of deleting it)
/// means turning it back on is a one-line change, and the code keeps compiling
/// and getting refactored along with everything else in the meantime.
class FeatureFlags {
  const FeatureFlags._();

  /// In-app update checking (the `app_updates` Firestore documents plus the
  /// "Update available" dialog).
  ///
  /// Disabled since v1.0.44:
  /// - Android: the release script used to swallow a failed Firestore write, so
  ///   `app_updates/android` sat at 1.0.42 while 1.0.43 was already shipping and
  ///   nobody was ever prompted. The script now fails loudly (bin/release.ps1),
  ///   but the documents still have to be corrected before the check means
  ///   anything.
  /// - iOS: there is no working update path at all - TestFlight notifies its
  ///   testers itself, and the dialog only ever pointed at an `itms-beta://`
  ///   link.
  ///
  /// Re-enable by flipping this to true once `app_updates/{android,ios,latest}`
  /// carry the current version and build number.
  static const bool updateCheckEnabled = false;
}
