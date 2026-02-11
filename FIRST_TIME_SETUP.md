# 🎯 STEP-BY-STEP: Your First Google Drive Setup (30 minutes)

Follow these exact steps to get your first release on Google Drive with auto-updating!

---

## ⏱️ TIME: ~30 minutes

---

## 📱 STEP 1: Create Google Drive Folder (2 minutes)

1. Go to https://drive.google.com
2. Click "New" button (left side) →  "Folder"
3. Name it: `FlightDeck_Updates`
4. Click "Create"
5. Right-click folder → "Share"
6. Change to: "Anyone with link" 
7. Copy the folder link (you'll need it: `https://drive.google.com/drive/folders/[FOLDER_ID]/`)
https://drive.google.com/drive/folders/1nDTiF2_QN5AwAl7Jou_72eLCARe53Fn6?usp=sharing
---

## 🔑 STEP 2: Upload Your Current APK (2 minutes)

1. Open `build/app/outputs/flutter-apk/` folder on your computer
2. Find: `app-release.apk`
3. Drag into Google Drive folder (FlightDeck_Updates)
4. Wait for upload (5-10 MB = ~10 seconds)
5. Right-click APK → Share
6. Copy the link: `https://drive.google.com/file/d/[FILE_ID_HERE]/view?usp=sharing`
7. **Extract FILE_ID** (the long string between `/d/` and `/view`)
8. **Create direct download URL:** `https://drive.google.com/uc?id=1jfsDm5BSsjiMrpAaYzZBpKIVZvAaLw83&export=download`


---

## 📝 STEP 3: Create metadata.json File (3 minutes)

1. Open Notepad (or any text editor)
2. Copy this and paste:

```json
{
  "version": "1.0.3",
  "buildNumber": "4",
  "downloadUrl": "https://drive.google.com/uc?id=REPLACE_WITH_YOUR_APK_FILE_ID&export=download",
  "changelog": "Initial release with FlightDeck features",
  "isForce": false
}
```

3. **Replace** `REPLACE_WITH_YOUR_APK_FILE_ID` with your APK FILE_ID from Step 2
4. Save as: `metadata.json` (exact name!)
5. **Important:** Make sure version matches your current app version

**Example (filled in):**
```json
{
  "version": "1.0.3",
  "buildNumber": "4",
  "downloadUrl": "https://drive.google.com/uc?id=1abc123XYZ456def789ghi012jkl345&export=download",
  "changelog": "Initial release with FlightDeck features",
  "isForce": false
}
```

---

## 📤 STEP 4: Upload metadata.json (2 minutes)

1. Go to your `FlightDeck_Updates` folder in Google Drive
2. Click "New" → "File upload"
3. Select `metadata.json` from your computer
4. Wait for upload
5. Right-click `metadata.json` → "Share"
6. Copy the link: `https://drive.google.com/file/d/1S8632U8D8nzQ35PYF9_ggBjUv6BdVqZU/view?usp=sharing`
7. **Extract the FILE_ID** (same as APK process)
8. **Create direct URL:** `https://drive.google.com/uc?id=1S8632U8D8nzQ35PYF9_ggBjUv6BdVqZU&export=download`


---

## ✅ STEP 5: Test metadata.json Download (2 minutes)

1. Open your metadata URL in browser (paste it in address bar)
2. Should **download** a file (not open in browser)
3. Open downloaded file with Notepad
4. Should see your JSON with version info
5. Click "Back" in browser

✅ **If this works, metadata is correct!**

---

## 🔧 STEP 6: Integrate into App (10 minutes)

### Part A: Add the URL

Open: `lib/screens/main_navigation.dart`

Find the `_checkForUpdates()` method (search for it):

```dart
Future<void> _checkForUpdates() async {
  try {
    final updateService = context.read<UpdateService>();
    final hasUpdate = await updateService.checkForUpdates();
    
    if (hasUpdate && mounted) {
      showDialog(...);
    }
  } catch (e) {
    debugPrint('[Update] Error: $e');
  }
}
```

Replace it with:

```dart
Future<void> _checkForUpdates() async {
  try {
    // Your metadata.json download URL (from Step 4)
    const metadataUrl = 
      'https://drive.google.com/uc?id=1S8632U8D8nzQ35PYF9_ggBjUv6BdVqZU&export=download';
    
    final updateService = context.read<UpdateService>();
    final hasUpdate = await updateService
      .checkForUpdatesFromGoogleDrive(metadataUrl);
    
    if (hasUpdate && mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) => UpdateDialog(
          onSkip: () => Navigator.of(dialogContext).pop(),
          onUpdate: () => Navigator.of(dialogContext).pop(),
        ),
      );
    }
  } catch (e) {
    debugPrint('[Update] Error checking updates: $e');
  }
}
```

**✅ Your metadata FILE_ID:** `1S8632U8D8nzQ35PYF9_ggBjUv6BdVqZU` (already in code above!)

### Part B: Enable Auto-Checking

Find `initState()` method in same file:

Make sure it calls `_checkForUpdates()`:

```dart
@override
void initState() {
  super.initState();
  // ... other code ...
  
  // Check for updates after screen loads
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _checkForUpdates();
  });
}
```

---

## 🏗️ STEP 7: Build and Test (5 minutes)

1. **Run script** (syncs version):
   ```bash
   cd d:\_Appdev\FlightDeck_new1\FlightDeck_firebase\flightdeck_firebase
   dart bin/update_version.dart
   ```

2. **Build APK:**
   ```bash
   flutter build apk --release
   ```

3. **Install on device:**
   ```bash
   adb install -r build\app\outputs\flutter-apk\app-release.apk
   ```

4. **Test in app:**
   - Open app
   - Go to hamburger menu (≡)
   - Check "App Version" (should show 1.0.3)
   - Wait 2-3 seconds
   - Update dialog should **NOT** appear (version in metadata = current version)

✅ **If app opens without crashing, integration works!**

---

## 🧪 STEP 8: Test with Fake Update (2 minutes)

1. Go back to Google Drive
2. Right-click `metadata.json` → Open with → Google Docs
3. Find: `"version": "1.0.3"`
4. Change to: `"version": "1.0.4"`
5. File → Save (Ctrl+S)
6. Close tab

Now your metadata.json says version `1.0.4` but app is `1.0.3`

**Test in app:**
1. Close and reopen app completely
2. Wait 3-5 seconds
3. **Update dialog should appear!** 📱
4. Click "Update"
5. Should download APK (you'll see progress dialog)
6. Should ask to install
7. Click "Install"
8. App should restart with new version ✅

---

## ⚡ TROUBLESHOOTING (5 minutes)

### Update dialog doesn't appear?
- [ ] Did you wait 3-5 seconds after opening app?
- [ ] Did you change version in metadata.json?
- [ ] Go to Google Drive → Check metadata.json is updated
- [ ] Open metadata download URL in browser → should show version: "1.0.4"

### Update downloads but won't install?
- [ ] Check APK file size (should be 30+ MB)
- [ ] Try: `adb uninstall com.example.flightdeck_firebase`
- [ ] Then: `adb install app-release.apk`

### Metadata file not accessible?
- [ ] Google Drive
 → `metadata.json` → right-click → Share
- [ ] Make sure "Anyone with link" is selected
- [ ] Test download URL in browser

### App crashes?
- [ ] Check Android logcat: `adb logcat | findstr flutter`
- [ ] Common: `UpdateService not found` → Check provider setup
- [ ] Common: JSON parse error → Check metadata.json format

---

## ✅ YOU'RE DONE!

Your app now:
✅ Automatically checks Google Drive for updates
✅ Shows update dialog when new version available
✅ Downloads APK from Google Drive
✅ Installs automatically
✅ No Firebase/Firestore needed!

---

## 🔄 FOR NEXT RELEASE (What You Do Every Time)

1. **Update pubspec.yaml:**
   ```yaml
   version: 1.0.4+5
   ```

2. **Build:**
   ```bash
   dart bin/update_version.dart
   flutter build apk --release
   ```

3. **Upload to Google Drive:**
   - Right-click old APK in folder → Delete
   - Upload new APK
   - Right-click → Share → Copy link
   - Extract FILE_ID

4. **Update metadata.json:**
   - Right-click → Open with Google Docs
   - Change version: `"version": "1.0.4"`
   - Change downloadUrl with new APK FILE_ID
   - Change changelog if needed
   - File → Save

5. **Done!** Users get update on next app start ✅

---

## 📚 HELP?

- Setup issues? → Read GOOGLE_DRIVE_AUTO_UPDATE.md
- Code questions? → Read INTEGRATION_GOOGLE_DRIVE.md  
- Comparisons? → Read QUICK_UPDATE_GUIDE.md
- Everything? → Read GOOGLE_DRIVE_DOCS_INDEX.md

---

## 🎉 THAT'S IT!

You have successfully:
✅ Created Google Drive folder
✅ Uploaded APK
✅ Created metadata.json
✅ Integrated into app
✅ Tested auto-update system

**No Firestore needed!** Just a JSON file! 🚀
