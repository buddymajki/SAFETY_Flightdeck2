# FlightDeck Auto-Update - Quick Start Checklist ✅

## Phase 1: Development Setup (10 minutes)

- [ ] **Run `flutter pub get`** - Get new dependencies
  ```bash
  flutter pub get
  ```

- [ ] **Verify compilation** - Check for errors
  ```bash
  flutter analyze
  ```

- [ ] **Test build** - Ensure APK builds
  ```bash
  flutter build apk --release
  ```

---

## Phase 2: Firestore Configuration (5 minutes)

- [ ] **Open Firebase Console**
  - Go to https://console.firebase.google.com
  - Select your project
  - Go to "Firestore Database"

- [ ] **Create `app_updates` collection**
  - Click "Create Collection"
  - Name: `app_updates`
  - Click "Next"

- [ ] **Create `latest` document**
  - Document ID: `latest`
  - Add fields:

| Field | Type | Value |
|-------|------|-------|
| `version` | String | `1.0.0` |
| `downloadUrl` | String | `https://...` (see Phase 3) |
| `changelog` | String | `"Initial version"` |
| `isForceUpdate` | Boolean | `false` |
| `updatedAt` | Timestamp | Now |

---

## Phase 3: Google Drive Setup (5 minutes)

- [ ] **Build release APK**
  ```bash
  cd android
  ./gradlew assembleRelease
  cd ..
  ```

- [ ] **Upload APK to Google Drive**
  - Go to https://drive.google.com
  - Create folder: `FlightDeck_Updates`
  - Upload: `android/app/build/outputs/apk/release/app-release.apk`
  - Right-click → "Share"
  - Change to "Viewer" → "Copy link"

- [ ] **Extract File ID from link**
  - Link format: `https://drive.google.com/file/d/FILE_ID_HERE/view?usp=sharing`
  - Copy the `FILE_ID_HERE` part

- [ ] **Create download URL**
  - Format: `https://drive.google.com/uc?id=FILE_ID&export=download`
  - Example: `https://drive.google.com/uc?id=1abc123XYZ456/view?export=download`

- [ ] **Update Firestore document**
  - Open Firestore Console
  - Go to `app_updates` → `latest`
  - Update `downloadUrl` field with your download URL

---

## Phase 4: Testing (5 minutes)

### Route 1: Automatic Testing
- [ ] **Update pubspec.yaml version** (optional)
  ```yaml
  version: 1.0.1+2  # Bump from 1.0.0+1
  ```

- [ ] **Run app in release mode**
  ```bash
  flutter run --release
  ```

- [ ] **Wait for update dialog**
  - App loads
  - Splash screen shows
  - After ~3 seconds, update dialog appears

- [ ] **Click "Telepítés"**
  - APK downloads
  - Progress bar shows download %
  - System installer opens
  - Click "Install"
  - ✅ App updated!

### Route 2: Using Debug Screen (Advanced)
- [ ] **Add debug route to main_navigation.dart**
  ```dart
  routes: {
    '/update-debug': (context) => const UpdateSystemDebugScreen(),
  }
  ```

- [ ] **Navigate to debug screen**
  ```dart
  Navigator.pushNamed(context, '/update-debug');
  ```

- [ ] **Test each function:**
  - [ ] "Check for Updates" button
  - [ ] "Show Update Dialog" button
  - [ ] "Download Only" button
  - [ ] "Install APK" button

---

## Phase 5: Production Deployment (Ongoing)

### For each new version:

1. **Update version in pubspec.yaml**
   ```yaml
   version: X.Y.Z+N  # Increment
   ```

2. **Build release APK**
   ```bash
   flutter build apk --release
   ```

3. **Upload to Google Drive**
   - New folder or replace existing
   - Get download URL
   - Share with "Anyone with link"

4. **Update Firestore document**
   ```json
   {
     "version": "X.Y.Z",
     "downloadUrl": "https://drive.google.com/uc?id=NEW_FILE_ID&export=download",
     "changelog": "- New features\n- Bug fixes",
     "isForceUpdate": false
   }
   ```

5. **Inform testers**
   - Send WhatsApp/Telegram message
   - Users open app → Update dialog appears
   - One click to install → Done! ✅

---

## Troubleshooting Quick Reference

| Issue | Solution |
|-------|----------|
| Dialog not showing | Check Firestore document exists, versions match |
| Download fails | Test Google Drive URL in browser |
| Install fails | Check APK is signed, Android version 5+ |
| Permission error | Check `REQUEST_INSTALL_PACKAGES` in AndroidManifest |
| Firestore error | Check Firebase Console connection, permissions |

---

## Commands Quick Reference

```bash
# Check code issues
flutter analyze

# Build & test
flutter build apk --release

# Run app (test build)  
flutter run --release

# View logs
flutter logs | grep Update

# Clean & rebuild (if issues)
flutter clean && flutter pub get
cd android && ./gradlew clean && cd ..
```

---

## File Locations Reference

| What | Where |
|------|-------|
| Update Service | `lib/services/update_service.dart` |
| Update Dialog | `lib/widgets/update_dialog.dart` |
| Debug Screen | `lib/screens/update_debug_screen.dart` |
| Android Main | `android/app/src/main/kotlin/.../MainActivity.kt` |
| Manifest | `android/app/src/main/AndroidManifest.xml` |
| APK Output | `android/app/build/outputs/apk/release/` |

---

## Success Indicators ✅

- [ ] App compiles without errors
- [ ] Firestore document created
- [ ] Google Drive link works
- [ ] Update dialog appears on app start
- [ ] APK downloads successfully
- [ ] APK installs on device
- [ ] New version runs after install

---

## Next Steps

1. ☑️ Complete Phase 1-5 above
2. ☑️ Distribute to testers
3. ☑️ Testers report feedback
4. ☑️ Fix issues and increment version
5. ☑️ Upload new APK & update Firestore
6. ☑️ Testers auto-update via app dialog
7. ☑️ Repeat for each version

---

**Estimated Time to Production:** 30 minutes total  
**Difficulty Level:** Easy-Medium  
**Production Ready:** Yes ✅

