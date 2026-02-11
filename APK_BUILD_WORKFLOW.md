# FlightDeck - APK Build & Update Workflow

## 1. APK Buildingolás

### Release APK Létrehozása

```bash
# Android belépési könyvtárba
cd android

# Build az APK-t
./gradlew assembleRelease

# Az APK az alábbi helyen található:
# android/app/build/outputs/apk/release/app-release.apk
```

### Build Opciók

```bash
# Debug build (gyorsabb, nagyobb)
flutter build apk --debug

# Release build (optimalizált)
flutter build apk --release

# Split APK-k (csökkentett méret per architecture)
flutter build apk --release --split-per-abi
```

---

## 2. Verzió Frissítése

A verzió a `pubspec.yaml`-ben van. Frissítsd megadott release előtt:

```yaml
version: 1.0.0+1
```

Format: `MAJOR.MINOR.PATCH+BUILD_NUMBER`

- `1.0.0` = az Update Service által megegyeztetett verzió
- `+1` = Android build szám (növelendő minden buildnél)

### Verzió Léptetési Workflow:

```bash
# 1.0.0 → 1.0.1 (patch fix/buggy)
version: 1.0.1+2

# 1.0.0 → 1.1.0 (új feature)
version: 1.1.0+3

# 1.0.0 → 2.0.0 (major release)
version: 2.0.0+4
```

---

## 3. Google Drive Upload

### Step by Step:

1. **APK Kész:** `android/app/build/outputs/apk/release/app-release.apk`

2. **Google Drive Feltöltés:**
   - Menj a https://drive.google.com
   - Klikk **New** → **File upload**
   - Válaszd ki `app-release.apk`
   - Nézd meg a feltöltés progresszióját

3. **Megosztás Engedélyezése:**
   - Jobb klikk az APK-ra
   - Klikk **Share**
   - Módosítsd a permissions-t: "Viewer" (vagy "Anyone with the link")
   - Másold ki a link-et

4. **File ID Kivonása:**
   ```
   Megosztási link:
   https://drive.google.com/file/d/1abc123XYZ456_def789/view?usp=sharing
                                ↑ Ez az FILE_ID
   
   Download URL:
   https://drive.google.com/uc?id=1abc123XYZ456_def789&export=download
   ```

---

## 4. Firestore Frissítés

### Firestore Console-ban:

1. Firebase Console → [Projektod](https://console.firebase.google.com)
2. **Firestore Database** → **Collections** → `app_updates`
3. Klikk a `latest` dokumentumra
4. Frissítsd a mezőket:

```json
{
  "version": "1.0.1",
  "downloadUrl": "https://drive.google.com/uc?id=1abc123XYZ456_def789&export=download",
  "changelog": "- Hibajavítások\n- Performance javítások",
  "isForceUpdate": false,
  "updatedAt": "2025-02-11T10:30:00Z"
}
```

---

## 5. Teszt az Update Rendszerre

### Automatikus Teszt (App Indítás):

1. Eddé az APK-t Google Drive-ba feltöltésre
2. Frissítsd a Firestore dokumentumot az új verzióval
3. Indítsd el az alkalmazást
4. A frissítés dialóg a splash screen után hamarosan megjelenik (3 mp)

### Manual Teszt (Debug Mode):

```dart
// lib/services/update_service.dart közelében
// Megnyíthatod az update dialog manuálisan:

Future<void> _checkForUpdates() async {
  try {
    final updateService = context.read<UpdateService>();
    
    // Debug: Force show dialog
    final updateInfo = UpdateInfo(
      version: "1.0.1",
      downloadUrl: "...",
      changelog: "Test",
      isForceUpdate: false,
    );
    updateService._updateInfo = updateInfo;
    updateService.notifyListeners();
    
    // Dialog megjelenik azonnal
    showDialog(...);
  } catch (e) {
    debugPrint('Error: $e');
  }
}
```

---

## 6. Termékes Deploy Workflow

### Tipikus Release workflow:

```
┌─────────────────┐
│  Dev verzió     │ ← Helyi testing
│  (1.0.0+1)      │
└────────┬────────┘
         ↓
┌─────────────────────────────────────┐
│  Verziót lépteted (1.0.1+2)         │
│  Buildeled az APK-t                 │
│  --release flaggel                  │
└────────┬────────────────────────────┘
         ↓
┌─────────────────────────────────────┐
│  APK feltöltés Google Drive-ba      │
│  Share link lekérése                │
│  File ID kinyerése                  │
└────────┬────────────────────────────┘
         ↓
┌─────────────────────────────────────┐
│  Firestore frissítés:               │
│  - version: 1.0.1                   │
│  - downloadUrl: <GD link>           │
│  - changelog: ...                   │
└────────┬────────────────────────────┘
         ↓
┌─────────────────────────────────────┐
│  Teszt eszközön:                    │
│  1. Eddé az appot                   │
│  2. Indítsd el az appot             │
│  3. Update dialóg jelenik meg       │
│  4. Klikk "Telepítés"               │
│  5. APK letöltésre kerül            │
│  6. Automata telepítés              │
└────────┬────────────────────────────┘
         ↓
┌─────────────────────────────────────┐
│  Teszteri distribúció:              │
│  - WhatsApp / Telegram üzenet       │
│  - "Nyílt az app, update             │
│    dialóg jelenleg meg"             │
│  - Teszteri klikkel "Telepítés"     │
│  - Az app automata updatelődik!     │
└─────────────────────────────────────┘
```

---

## 7. Hibaelhárítás

| Probléma | Ok | Megoldás |
|----------|-----|----------|
| Update dialóg nem jelenik meg | Firestore doc hiányzik/verziók egyeznek | Ellenőrizd app verziót & Firestore |
| APK letöltés sikertelen | Google Drive link hibás | Teszteld a linket böngészőben |
| Telepítés sikertelen | APK sérült/Android verzió | Buildeld újra az APK-t |
| Permission denied | Hiányzik `REQUEST_INSTALL_PACKAGES` | Ellenőrizd AndroidManifest.xml |

---

## 8. Parancsok Gyors Referencia

```bash
# Verzió léptetése & build
flutter pub get
flutter build apk --release

# Mappa megnyitása az output-hoz (Windows)
explorer android\app\build\outputs\apk\release

# Teszt eszközre telepítés
flutter install

# Logok megtekintése
flutter logs | grep Update

# Gradle tisztítás (ha build problémák vannak)
cd android && ./gradlew clean && cd ..
flutter clean && flutter pub get
```

---

## 9. Biztonsági Checklist

- [ ] APK aláírva van az `key.jks` kulccsal (release build)
- [ ] Google Drive link megosztva az "Anyone" számára
- [ ] Firestore security rules korrektek
- [ ] Verzió szám megfelelően lépteted
- [ ] HTTPS-t használ minden URL (érdemes HTTPS-t használni)
- [ ] Teszt eszközön tesztelted a letöltést és telepítést

---

## Megjegyzések

- **[Hasznos]** A Google Drive linket sokszor kell frissíteni, mint új verzió létezik
- **[Performance]** Az APK letöltés a háttérben történik, az app továbbra is használható
- **[Optional]** Cloud Function-öt lehet beállítani az automata APK feltöltéshez

