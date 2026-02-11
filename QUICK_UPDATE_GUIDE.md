# 🚀 QuickStart: FlightDeck Updates (Choose Your Method)

## 2️⃣ OPTIONS FOR UPDATES

---

## ✅ OPTION 1: Google Drive (RECOMMENDED!)

**Best for:** Complete independence from databases, simplicity

### Every time you have a new version:

**Step 1: Bump version**
```bash
# Edit pubspec.yaml
version: 1.0.4+5
```

**Step 2: Sync version**
```bash
dart bin/update_version.dart
flutter build apk --release
```

**Step 3: Upload files to Google Drive**
- Upload `app-release.apk` to Drive folder `FlightDeck_Updates`
- Get its FILE_ID from share link

**Step 4: Update metadata.json**
```json
{
  "version": "1.0.4",
  "downloadUrl": "https://drive.google.com/uc?id=APK_ID&export=download",
  "changelog": "- New features\n- Bug fixes",
  "isForce": false
}
```

**Step 5: Upload metadata.json to Drive**
- Upload updated file
- Get its FILE_ID

**Step 6: Configure App (ONE TIME)**
```dart
// In main_navigation.dart
const metadataUrl = 'https://drive.google.com/uc?id=METADATA_ID&export=download';
await updateService.checkForUpdatesFromGoogleDrive(metadataUrl);
```

**Done!** Users get update on next app start ✅

---

## ✅ OPTION 2: Firestore (Database Method)

**Best for:** More control, complex deployment scenarios

### Every time you have a new version:

**Step 1-2: Same as above**
```bash
# Edit pubspec.yaml
version: 1.0.4+5

dart bin/update_version.dart
flutter build apk --release
```

**Step 3: Upload APK to Google Drive**
- Get download URL

**Step 4: Update Firestore**
```
Database: /app_updates/latest
Fields:
  - version: "1.0.4"
  - downloadUrl: "https://drive.google.com/uc?id=..."
  - build: "5"
  - changelog: "..."
```

**Done!** Users get update on next app start ✅

---

## 🔄 COMPARISON

| Feature | Google Drive | Firestore |
|---------|-------------|-----------|
| Database needed? | ❌ No | ✅ Yes |
| Metadata editing | Simple JSON file | Firestore console |
| Version field updates | None | Manual |
| Rollback | Edit JSON | Edit database |
| Offline support | ✅ | ✅ |
| Setup complexity | Simple | Medium |
| Cost | Free | Free (small scale) |

---

## 📋 Checklist for Each Release

### Google Drive Method:
- [ ] Update `pubspec.yaml` version
- [ ] Run `dart bin/update_version.dart`  
- [ ] Run `flutter build apk --release`
- [ ] Upload APK to Google Drive
- [ ] Create/Update `metadata.json`
- [ ] Upload `metadata.json` to Google Drive
- [ ] Test with real device

### Firestore Method:
- [ ] Update `pubspec.yaml` version
- [ ] Run `dart bin/update_version.dart`
- [ ] Run `flutter build apk --release`
- [ ] Upload APK to Google Drive (get URL)
- [ ] Update `/app_updates/latest` in Firestore
- [ ] Test with real device

---

## 🆘 Troubleshooting

### Update not showing?
1. Check that new version in metadata.json or Firestore is **higher** than app version
2. Test download URL in browser (should download APK)
3. Restart app completely (kill and reopen)

### Version not updating in app?
1. Run: `dart bin/update_version.dart`
2. Run: `flutter clean && flutter build apk --release`
3. Reinstall with: `adb install -r app-release.apk`

### APK won't install?
- Error "version downgrade"? → Increment version code in pubspec.yaml
- Example: `version: 1.0.4+5` → `version: 1.0.4+6`

---

## 📖 For More Details

- **Google Drive Setup:** See `GOOGLE_DRIVE_AUTO_UPDATE.md`
- **Version Automation:** See `VERSION_MANAGEMENT.md`
- **Auto-Update Code:** See `UPDATE_IMPLEMENTATION_SUMMARY.md`

---

**Which method will you use?** 🚀
