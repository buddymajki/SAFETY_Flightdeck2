# GOOGLE_DRIVE_AUTO_UPDATE

...existing content...
# Google Drive Auto-Update Tutorial (NO FIRESTORE NEEDED!) 🚀

## 📋 Overview

**Old Way:** Firestore database → manual updates  
**New Way:** Google Drive metadata.json → automatic version detection

---

## ✨ Setup (One-Time Only)

### Step 1️⃣: Create a Google Drive Folder

1. Go to https://drive.google.com
2. Create folder: `FlightDeck_Updates`
3. Right-click → Share → "Anyone with link" (or specific people)
4. Copy the **Folder ID** from URL:
   ```
   https://drive.google.com/drive/folders/[FOLDER_ID_HERE]/
   ```

---

### Step 2️⃣: Create metadata.json

Create a text file locally with this content:

```json
{
  "version": "1.0.4",
  "downloadUrl": "https://drive.google.com/uc?id=APK_FILE_ID&export=download",
  "changelog": "- Bug fixes\n- Performance improvements\n- UI updates",
  "isForce": false
}
```

**Fields:**
- `version`: Current version (must be > app version to trigger update)
- `downloadUrl`: Direct download link to APK on Google Drive
- `changelog`: What's new (displayed in update dialog)
- `isForce`: Force update even if user hasn't updated in a while

---

### Step 3️⃣: Upload Files to Google Drive

1. **Upload APK:**
   - Go to `FlightDeck_Updates` folder
   - Upload: `app-release.apk` (from `build/app/outputs/flutter-apk/`)
   - Right-click → Share → Copy link
   - Extract FILE_ID from: `https://drive.google.com/file/d/[FILE_ID_HERE]/view?usp=sharing`

2. **Create metadata.json in Google Drive:**
   - Right-click in folder → More → Upload file
   - Create new file via Google Drive web → Google Docs → Convert to plain text
   - OR: Upload metadata.json from your computer
   - Copy the metadata.json FILE_ID (same as APK above, but for metadata.json)

3. **Get Direct Links:**
   - APK: `https://drive.google.com/uc?id=APK_ID&export=download`
   - Metadata: `https://drive.google.com/uc?id=METADATA_ID&export=download`

   **Update metadata.json with APK download URL:**
   ```json
   {
     "version": "1.0.4",
     "downloadUrl": "https://drive.google.com/uc?id=[APK_ID_HERE]&export=download",
     "changelog": "Your changes here",
     "isForce": false
   }
   ```

---

## 🔧 Using in Your App

### Option A: Use Google Drive (RECOMMENDED!)
```dart
// In main_navigation.dart or wherever you check for updates
final metadataUrl = 'https://drive.google.com/uc?id=METADATA_FILE_ID&export=download';
final hasUpdate = await updateService.checkForUpdatesFromGoogleDrive(metadataUrl);

if (hasUpdate && mounted) {
  showDialog(context: context, builder: (_) => UpdateDialog(...));
}
```

### Option B: Use Firestore (Old Way, Still Works)
```dart
final hasUpdate = await updateService.checkForUpdates();
```

### Option C: Hybrid (Firestore + Google Drive Fallback)
```dart
bool hasUpdate = await updateService.checkForUpdates();
if (!hasUpdate) {
  // Firestore failed or no update, try Google Drive
  hasUpdate = await updateService.checkForUpdatesFromGoogleDrive(metadataUrl);
}
```

---

## 📱 Integration in main_navigation.dart

```dart
Future<void> _checkForUpdates() async {
  try {
    final updateService = context.read<UpdateService>();
    
    // Google Drive metadata URL (replace with your actual URL)
    const metadataUrl = 'https://drive.google.com/uc?id=YOUR_METADATA_FILE_ID&export=download';
    
    // Check for updates from Google Drive (NO FIRESTORE!)
    final hasUpdate = await updateService.checkForUpdatesFromGoogleDrive(metadataUrl);
    
    if (hasUpdate && mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) => UpdateDialog(
          onSkip: () => debugPrint('[Update] User skipped'),
          onUpdate: () => debugPrint('[Update] Success'),
        ),
      );
    }
  } catch (e) {
    debugPrint('[Update] Error: $e');
  }
}
```

---

## 🔄 For Future Updates

### When you have a new version:

1. **Update pubspec.yaml:**
   ```yaml
   version: 1.0.4+5
   ```

2. **Sync version:**
   ```bash
   dart bin/update_version.dart
   flutter build apk --release
   ```

3. **Upload to Google Drive:**
   - Upload new APK to `FlightDeck_Updates` folder
   - Get new FILE_ID

4. **Update metadata.json in Google Drive:**
   ```json
   {
     "version": "1.0.4",
     "downloadUrl": "https://drive.google.com/uc?id=NEW_APK_ID&export=download",
     "changelog": "- New feature X\n- Fixed bug Y",
     "isForce": false
   }
   ```

**That's it!** No Firestore changes needed!

---

## ✅ Advantages of Google Drive Method

✅ No Firestore database needed  
✅ No manual database updates  
✅ Simple metadata file  
✅ Works offline (once version is known)  
✅ Easy to rollback (just update metadata.json)  
✅ Free (Google Drive is free)  

---

## 🐛 Troubleshooting

**Q: "Device not updating after new metadata.json"**
- Make sure the `version` in metadata.json is higher than current app version
- Check that downloadUrl is correct (test in browser)
- Make sure metadata.json is shared with "Anyone with link"

**Q: "Error parsing metadata.json"**
- Check JSON syntax: https://jsonlint.com
- Make sure there are no special characters
- Use valid UTF-8 encoding

**Q: "Download URL not working"**
- Test the URL in browser
- Make sure APK file is shared with "Anyone with link"
- Confirm the FILE_ID in URL matches the file

**Q: "How do I get the FILE_ID easily?"**
- Share the file in Google Drive
- Copy the share link: `https://drive.google.com/file/d/FILE_ID_HERE/view?usp=sharing`
- The FILE_ID is the long string between `/d/` and `/view`

---

## 📄 metadata.json Full Example

```json
{
  "version": "1.0.4",
  "buildNumber": "5",
  "downloadUrl": "https://drive.google.com/uc?id=1abc123XYZ456def789ghi012jkl345&export=download",
  "changelog": "Version 1.0.4 - Build 5\n\n✨ New Features:\n- Real-time flight radar\n- Enhanced GPS accuracy\n\n🐛 Bug Fixes:\n- Fixed crashes on Android 12+\n- Improved battery usage\n\n📱 Other:\n- Updated UI\n- Better performance",
  "isForce": false
}
```

---

**No more Firestore version management! Just update metadata.json!** 🎉
