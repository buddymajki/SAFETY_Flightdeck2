# IMPORTANT TODO: Android Release Signing Key

To ensure seamless updates across all machines and future releases, set up a custom release signing key (key.jks) for FlightDeck.

## Why?
- Android requires the same signing key for all updates.
- Debug keys are machine-specific; release key is portable.
- With a custom key, you can build and release from any computer, and users can always update without uninstalling.

## Steps (to do later)
1. Generate key.jks (Android Studio or keytool)
2. Store key.jks securely (cloud, USB, etc.)
3. Add signing config to build.gradle:
   ```gradle
   signingConfigs {
       release {
           storeFile file("../key.jks")
           storePassword "..."
           keyAlias "..."
           keyPassword "..."
       }
   }
   buildTypes {
       release {
           signingConfig signingConfigs.release
       }
   }
   ```
4. Use release build for production APKs
5. Never lose the key! (Android cannot update without it)

## Status
- [ ] key.jks generated
- [ ] build.gradle updated
- [ ] Release builds use custom key

> **TODO:** Set up key.jks before production or machine change!
