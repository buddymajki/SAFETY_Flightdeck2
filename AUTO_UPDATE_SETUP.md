# FlightDeck Auto-Update System - Setup Guide

## Áttekintés

Ez az auto-update rendszer lehetővé teszi, hogy az alkalmazás automatikusan észleljen és telepítsen új verziókat az alkalmazás indításakor Firestore-ban tárolt verzióinformáció alapján.

## Komponensek

### 1. **Update Service** (`lib/services/update_service.dart`)
- Verzióellenőrzés Firestore-ban
- APK letöltés Dio HTTP kliense
- Platform channel-es kommunikáció az Android telepítéshez

### 2. **Update Dialog** (`lib/widgets/update_dialog.dart`)
- Frissítés dialóg megjeleníté az felhasználónak
- Letöltési progress kijelzése
- Telepítési folyamat kezelése

### 3. **Android Implementation**
- `MainActivity.kt` - MethodChannel implementáció APK telepítéshez
- `AndroidManifest.xml` - szükséges permissziók és FileProvider konfigurálása
- `file_paths.xml` - FileProvider útvonalaira

### 4. **Firestore Configuration**
- `app_updates` kollekcióban egy `latest` dokumentum

---

## Setup Lépések

### 1. Flutter Dependencies Frissítés

A `pubspec.yaml` már frissítésre került:
```yaml
dio: ^5.3.0              # HTTP client for APK download
path_provider: ^2.1.1    # Access app cache directory
```

```bash
flutter pub get
```

### 2. Firestore Configuration

Hozz létre egy dokumentumot Firestore-ban az alábbi strukúrával:

**Collection:** `app_updates`  
**Document ID:** `latest`

**Document tartalma:**
```json
{
  "version": "1.1.0",
  "downloadUrl": "https://drive.google.com/uc?id=YOUR_FILE_ID&export=download",
  "changelog": "- Új funkciók\n- Hibajavítások\n- Performance fejlesztések",
  "isForceUpdate": false,
  "updatedAt": "2025-02-11T10:30:00Z"
}
```

#### Firestore Manuális Beállítása:
1. Nyiss meg [Firebase Console](https://console.firebase.google.com)
2. Válaszd ki a projekted
3. Menj a **Firestore Database**-re
4. Klikk **Create Collection** → `"app_updates"`
5. Klikk **Add Document** → Document ID: `"latest"`
6. Add meg az adatokat az alábbi mezőkkel:
   - `version` (string): `"1.1.0"`
   - `downloadUrl` (string): Google Drive download URL
   - `changelog` (string): Verzió megjegyzések
   - `isForceUpdate` (boolean): `false` (jövőbeli kiterjesztés)
   - `updatedAt` (timestamp): mostani idő

### 3. Google Drive Integration

#### APK feltöltés a Google Drive-ba:

1. **Bejelentkezés:** Menj a [Google Drive](https://drive.google.com)-ra
2. **Mappa létrehozása:** `FlightDeck_Updates` (opcionális, de ajánlott)
3. **APK feltöltés:** Töltsd fel az APK fájlt
4. **Megosztás beállítása:**
   - Jobb klikk az APK-ra → "Share"
   - Módosítsd az engedélyeket: "Anyone with the link can view"
   - Másold ki a link-et
5. **File ID kivonása:**
   - Link formátum: `https://drive.google.com/file/d/FILE_ID_HERE/view?usp=sharing`
   - Szűrj ki a **FILE_ID_HERE** részt
6. **Download URL létrehozása:**
   - Formátum: `https://drive.google.com/uc?id=FILE_ID&export=download`

#### Firestore-ban frissítsd a `downloadUrl` értéket ezzel az URL-el.

---

## APK Verzió Kezelés

### Jelenlegi Verzió Beállítása

A Flutter app verzió a `pubspec.yaml`-ben van:
```yaml
version: 1.0.0+1
```

`updateService.appVersion` értéke: `1.0.0`

### Update Service Verzió Összehasonlítás

Az UpdateService a `1.0.0` formátumot támogat (MAJOR.MINOR.PATCH).

---

## Testing

### 1. **Lokális Tesztelés**

```dart
// lib/main.dart közelében egy test route hozzáadása
// (jól hasznos a development során)

// Android device-en:
flutter run --release
```

### 2. **Firestore Dokumentum Módosítása**

1. Frissítsd a Firestore `app_updates/latest` dokumentumot:
   - `version`: `"1.0.1"`
   - `downloadUrl`: új APK URL
   - `changelog`: új megjegyzések

2. Indítsd újra az alkalmazást

3. A frissítés dialógot a splash screen után 3 másodperc múlva meg kell jelennie

### 3. **Automata Tesztekhez Script Létrehozása**

Opcionális: Cloud Function az APK-kat szervezni automatikusan Google Drive-ban.

---

## Hibaelhárítás

### 1. **Update dialóg nem jelenik meg**

- Ellenőrizd, hogy a Firestore `app_updates/latest` dokumentum létezik
- Ellenőrizd az `appVersion` értékét az UpdateService-ben
- Kontrollálj a debug logban, hogy `[Update] checkForUpdates` üzenetek jelennek-e meg

### 2. **Letöltés sikertelen**

- Ellenőrizd az internet kapcsolatot
- Teszteld a Google Drive URL-t a böngészőben
- Ellenőrizd a Firestore `downloadUrl` értékét
- Kontrollálj a logban a `[Update] Error downloading update` üzeneteket

### 3. **Telepítés sikertelen**

- Android 12+ (API level 31+): Ellenőrizd, hogy az `android.permission.REQUEST_INSTALL_PACKAGES` engedélyt igényli az app
- Android 5-11: Az engedély implicit automatikusan az `ACTION_VIEW` intenthez `application/vnd.android.package-archive` MIME típussal
- Ellenőrizz a logban: `[MainActivity]` hibaüzeneteket

### 4. **FileProvider hibák**

- Ellenőrizd, hogy az `android/app/src/main/res/xml/file_paths.xml` fájl létezik
- Ellenőrizd az AndroidManifest.xml-ben a FileProvider deklarációját

---

## Versio Stratégia Javaslat

### Beta Testing Workflow:

1. **Beta verzió:** `1.0.1` (Testeri testing)
   - `isForceUpdate: false` - Opcionális frissítés
   
2. **Stable verzió:** `1.0.1` (Teljes release)
   - Frissítsd a Firestore dokumentumot
   - A testeri jelenleg telepítve van `1.0.1`-en

3. **Critical Update:** `1.1.0`
   - `isForceUpdate: true` - Kötelező frissítés (jövőbeli)
   - A "Később" gomb eltűnik a dialógból

---

## Jövőbeli Kiterjesztések

### 1. **isForceUpdate Támogatás**
```dart
// update_dialog.dart-ban
if (updateInfo.isForceUpdate) {
  // Nézze ki a skip gombat
}
```

### 2. **Cloud Function API**
Google Cloud Function az APK-t automatikusan Google Drive-ba feltölteni:
- Az APK metadata olvasása
- A Firestore automatikus frissítése

### 3. **Staged Rollout**
- Csak az X% felhasználónak mutasd az frimware frissítést

### 4. **In-App Update API** (oficális)
- Google Play in-app update API beintegrálása (ha Play Store release)

---

## Biztonsági Megjegyzések

1. **APK Aláírás:** Biztosítsd, hogy az APK megfelelően aláírva van az ugyanezzel a kulccsal, mint az előző verzió
2. **HTTPS:** Biztosítsd, hogy a Google Drive link HTTPS-t használ
3. **Filestore Security:** Ellenőrizd a Firestore security rules-okat:
   ```
   rules_version = '2';
   service cloud.firestore {
     match /databases/{database}/documents {
       match /app_updates/{document=**} {
         allow read: if true;
         allow write: if request.auth != null && request.auth.uid == "ADMIN_UID";
       }
     }
   }
   ```

---

## Támogatás & Kontakt

Ha problémáid vannak:
1. Nézd meg a debug logod: `flutter logs | grep Update`
2. Ellenőrizz a Firestore dokumentumodat
3. Teszteld a Google Drive linket böngészőben

