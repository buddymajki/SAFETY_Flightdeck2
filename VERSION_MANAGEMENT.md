# App Version Management Guide 📱

## ✨ How It Works Now - AUTOMATIC!

**You only edit pubspec.yaml!** A Dart script (`bin/update_version.dart`) automatically syncs everything.

```
1. Edit pubspec.yaml:        version: 1.0.4+5
        ↓
2. Run: dart bin/update_version.dart
        ↓
3. AppVersionService generated automatically
        ↓
4. All screens show: "FlightDeck 1.0.4 (build 5)" ✅
```

---

## Simple 2-Step Process for Each Update

### Step 1️⃣: Update pubspec.yaml
Edit the version line:
```yaml
version: 1.0.4+5
```
*(Just increment the version and build number)*

### Step 2️⃣: Run the sync script
```bash
dart bin/update_version.dart
```
*(This takes 1 second and generates AppVersionService automatically)*

### Step 3️⃣: Build & Deploy
```bash
flutter build apk --release
```

### Step 4️⃣: Upload & Update Firestore
- Upload new APK to Google Drive
- Update `/app_updates/latest` in Firestore with new `version` and `downloadUrl`
- Users will see the update dialog on next app start ✅

---

## Where Version Appears

✅ **Splash Screen** (while loading) - Automatic
✅ **Login Screen** - Automatic  
✅ **Hamburger Menu** (≡) → Bottom → "App Version" - Automatic
✅ **Update Service** (internal) - Automatic

---

## What the Script Does

The `bin/update_version.dart` script:
1. Reads `pubspec.yaml` version (e.g., `1.0.4+5`)
2. Parses version (`1.0.4`) and build number (`5`)
3. Generates `lib/services/app_version_service.dart` with the correct constants
4. Shows you the result ✨

**You never manually edit AppVersionService again!**

---

## Future Builds Checklist

- [ ] Update `pubspec.yaml` version (e.g., `1.0.4+5`)
- [ ] Run `dart bin/update_version.dart` (takes 1 second)
- [ ] Run `flutter build apk --release`
- [ ] Test locally: `adb install -r ...app-release.apk`
- [ ] Upload APK to Google Drive
- [ ] Update Firestore `/app_updates/latest` document
- [ ] Done! 🎉

---

## Example: Building v1.0.4

**Before:**
```yaml
version: 1.0.3+4
```

**Update Step 1:**
```yaml
version: 1.0.4+5
```

**Update Step 2:**
```bash
dart bin/update_version.dart
```

**Output:**
```
🔄 Syncing version from pubspec.yaml to AppVersionService...
📦 Found version: 1.0.4 (build 5)
✅ AppVersionService updated successfully!
✨ Ready to build!
```

**Result:** App shows everywhere "FlightDeck 1.0.4 (build 5)" 🎉

---

## If Something Goes Wrong

**Q: The script says "version not found"**
- Check pubspec.yaml format: `version: X.Y.Z+N`
- Make sure it's at the top of the file
- Example: `version: 1.0.4+5`

**Q: AppVersionService not updated?**
- Make sure you're in the correct directory (flightdeck_firebase)
- Re-run: `dart bin/update_version.dart`
- Check the output for errors

**Q: Old version still showing?**
- `flutter clean` then rebuild
- Make sure you ran the sync script before building

---

**That's it! Just one file to edit for all future updates!** ✨

---

## 🆕 NEW: Google Drive Auto-Update (NO FIRESTORE!)

**Problem:** Having to manually update Firestore `/app_updates/latest` every time

**Solution:** Use metadata.json file on Google Drive instead!

### How It Works

Instead of Firestore database, create a simple `metadata.json` file:

```json
{
  "version": "1.0.4",
  "downloadUrl": "https://drive.google.com/uc?id=APK_FILE_ID&export=download",
  "changelog": "Bug fixes and improvements",
  "isForce": false
}
```

Upload this file next to your APK on Google Drive → App checks it automatically!

### Complete Workflow (Google Drive Method)

```
1. Edit pubspec.yaml: version: 1.0.4+5
        ↓
2. Run: dart bin/update_version.dart
        ↓
3. Run: flutter build apk --release
        ↓
4. Upload APK to Google Drive folder
        ↓
5. Update metadata.json (new version + APK URL)
        ↓
6. Upload metadata.json to same Google Drive folder
        ↓
7. Done! Users get update on next app start ✅
```

**No Firestore changes needed at all!**

### Advantages Over Firestore

✅ No database to manage  
✅ Everything in one Google Drive folder  
✅ Easier to rollback (just edit metadata.json)  
✅ Free (Google Drive is free)  
✅ No dependency on Firestore  

### Implementation in App

In `main_navigation.dart`:

```dart
Future<void> _checkForUpdates() async {
  const metadataUrl = 
    'https://drive.google.com/uc?id=YOUR_METADATA_FILE_ID&export=download';
  
  final hasUpdate = await updateService
    .checkForUpdatesFromGoogleDrive(metadataUrl);
    
  if (hasUpdate && mounted) {
    showDialog(context: context, builder: (_) => UpdateDialog(...));
  }
}
```

### Still Using Firestore?

Both methods work! Use whichever you prefer:

```dart
// Option 1: Firestore (existing method)
await updateService.checkForUpdates();

// Option 2: Google Drive (new method)
await updateService.checkForUpdatesFromGoogleDrive(metadataUrl);

// Option 3: Try Firestore first, fallback to Google Drive
final hasUpdate = await updateService.checkForUpdates()
  ?? await updateService.checkForUpdatesFromGoogleDrive(metadataUrl);
```

---

## 📚 Full Setup Guide

See **GOOGLE_DRIVE_AUTO_UPDATE.md** for complete step-by-step instructions including:
- Creating Google Drive folder
- Getting FILE_IDs  
- Creating metadata.json
- Testing download links
- Troubleshooting

