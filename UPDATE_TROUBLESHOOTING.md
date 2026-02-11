# Update System Troubleshooting 🔧

## Hiba: "Probléma van az alkalmazásfile-al és nem sikerült telepíteni az alkalmazást"

Ez az Android Install Manager hibaüzenete, amely általában az alábbiak egyikét jelenti:

### 1. **APK fájl sérült vagy hiányos** ❌

**Okok:**
- A Google Drive letöltés valamilyen okból nem teljes
- A fájl mérete nem elég (< 1MB)
- Szerver hiba a Download során

**Megoldás:**
- Ellenőrizze a Logcat-ban az error-t: `flutter logs`
- A logban keresse meg: `[Update] APK_FILE_TOO_SMALL_...`
- Ha ez jelenik meg, törölje az APK cache-t:
  ```bash
  adb shell rm -r /sdcard/Android/data/com.example.flightdeck_firebase/cache/
  ```
- Próbálja újra a letöltést

### 2. **APK aláírás probléma** 🔐

**Okok:**
- Az APK nincs helyesen aláírva a release build-ben
- Debug APK vs Release APK eltérés

**Megoldás:**
```bash
# Ellenőrizze, hogy az APK helyesen van-e aláírva:
keytool -printcert -jarfile android/app/build/outputs/apk/release/app-release.apk

# Ha az APK nem aláírt, újra kell építeni:
flutter clean
flutter build apk --release

# vagy ha signing nem mutatja meg a key-t:
cd android
./gradlew signingReport
cd ..
```

### 3. **Google Drive URL probléma** 🌐

**Okok:**
- Az URL formátuma hibás
- A fájl lejárt megosztási linkje
- A Google Drive 403 (Forbidden) hibát ad vissza

**Megoldás:**
```
❌ Hibás formátum:
https://drive.google.com/file/d/FILE_ID/view?usp=sharing

✅ Helyes formátum:
https://drive.google.com/uc?id=FILE_ID&export=download

⚠️ Ha továbbra sem működik, próbálja:
https://drive.google.com/uc?id=FILE_ID&export=download&confirm=t
```

### 4. **Android Permission probléma** 🔒

**Okok:**
- `REQUEST_INSTALL_PACKAGES` engedély hiányzik
- Android 11+ Storage Permission probléma

**Ellenőrzés:**
- Nyitvatartási AndroidManifest.xml
- Keresse meg: `<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />`
- Ha nincs, adja hozzá

### 5. **FileProvider beállítás probléma** 📁

**Okok:**
- A `file_paths.xml` nem létezik vagy hibás a konfiguráció
- A `fileprovider` path nem megfelelő

**Javítás:**
1. Ellenőrizze az `android/app/src/main/res/xml/file_paths.xml` létezését
2. Tartalmát:
   ```xml
   <paths xmlns:android="http://schemas.android.com/apk/res/android">
       <cache-path name="apk_cache" path="." />
   </paths>
   ```
3. Ellenőrizze az AndroidManifest.xml-ben a FileProvider beállítást:
   ```xml
   <provider
       android:name="androidx.core.content.FileProvider"
       android:authorities="com.example.flightdeck_firebase.fileprovider"
       android:exported="false">
       <meta-data
           android:name="android.support.FILE_PROVIDER_PATHS"
           android:resource="@xml/file_paths" />
   </provider>
   ```

---

## Debug folyamat 🐛

### 1. **Logok megtekintése**
```bash
flutter logs
```
Keresse meg ezeket a sorokakat:
- `[Update]` - Update service logok
- `MainActivity` - Android platform channel hibák

### 2. **APK letöltési Status**
A logban ezeket kell látnia:
```
[Update] Starting download from: https://...
[Update] Downloaded: X.XX MB / Y.YY MB
[Update] Download complete, APK size: Z.ZZ MB
```

### 3. **Ha Error jel jelenik meg a Dialog-ban**
```
Hiba: DIO_ERROR_RESPONSE_403
Hiba: APK_FILE_TOO_SMALL_123456_bytes
Hiba: ERROR_...
```

---

## Kézi tesztelés 🧪

A Debug Screen-en:
```dart
// Add to main_navigation.dart routes:
routes: {
  '/update-debug': (context) => const UpdateSystemDebugScreen(),
}
```

Lépések:
1. Navigáljon `/update-debug` routera
2. Kattintson a "Check for Updates" gombra
3. Ha frissítés érhető el, kattintson a "Download Only"-ra
4. Ellenőrizze a logban az error-t

---

## Gyors fix checklist ✅

- [ ] APK helyesen aláírt (`flutter build apk --release`)
- [ ] Google Drive URL helyes (`https://drive.google.com/uc?id=...`)
- [ ] Firestore document létezik: `/app_updates/latest`
- [ ] Verziók helyes formátumban: `1.0.0`
- [ ] `REQUEST_INSTALL_PACKAGES` engedély megvan
- [ ] FileProvider beállítás helyes
- [ ] Google Drive fájl megosztva: "Anyone with the link"

---

## Manual APK telepítés (ha az Automatic nem működik)

```bash
# Telepítés adb-vel:
adb install -r android/app/build/outputs/apk/release/app-release.apk

# vagy Google Drive-ről:
# 1. Nyissa meg https://drive.google.com
# 2. Keresse meg az APK fájlt
# 3. Töltse le a telefonba
# 4. Nyissa meg a Downloads-t
# 5. Telepítse manuálisan
```

---

## Support 📞

Ha továbbra is probléma van, gyűjtsön össze:
1. Teljes `flutter logs` output
2. Az error szövege a Dialog-ban
3. Az APK verzió, amely telepítésre kerül
4. Az Android eszköz verziája

**Debug Screen-ből:** Másolja ki az "Update Info" részleteit és az error-t.
