# APK Installation Fix - Engedélyek kezelése

## Probléma
Az APK letöltése működött, de a telepítés elakadt, mert:
- Android 8.0+ (API 26+) óta **kötelező engedély** szükséges: "Install unknown apps"
- Ez az engedély nem automatikus, a felhasználónak kézzel kell engedélyeznie

## Megoldás

### 1. MainActivity.kt (Android oldal)
**Hozzáadva**: Engedély ellenőrzés az installAPK() metódusban
```kotlin
if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
    if (!packageManager.canRequestPackageInstalls()) {
        // Nyisd meg a beállításokat
        val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
        startActivity(intent)
        return false
    }
}
```

**Mit csinál?**
- Ellenőrzi, hogy van-e engedély telepíteni
- Ha nincs, automatikusan **megnyitja az Android beállításokat**
- A felhasználó engedélyezi, majd visszatér az appba és újra próbálhatja

### 2. update_dialog.dart (Flutter oldal)
**Hozzáadva**: Új felugró dialógus, ha az engedély hiányzik
- Új szöveg: `permission_needed` (EN + DE)
- Ha az installUpdate() false-sal tér vissza ÉS nincs konkrét hiba, az = engedély hiányzik
- Megjelenít egy **figyelmeztetést**, hogy a felhasználó tudja, mit kell tennie

## Hogyan működik most

### Első használat esetén (nincs engedély):
1. User kattint "Install"
2. APK letöltődik ✓
3. installAPK() lefut → ellenőrzi az engedélyt
4. **Nincs engedély** → megnyitja a Settings oldalt
5. Felhasználó engedélyezi: "Allow from this source"
6. User visszatér az appba
7. **Dialógus megjelenik**: "Permission required! Please enable..."
8. User bezárja, újra kattint "Install"
9. Most már **működik a telepítés** ✓

### Következő frissítések esetén (engedély már megvan):
1. User kattint "Install"
2. APK letöltődik ✓
3. installAPK() lefut → **engedély OK**
4. Telepítő felugrik azonnal ✓
5. User kattint "Install" a telepítőben
6. **App frissül** ✓

## Megjegyzések
- **NINCS szükség arra, hogy bezárd az appot** frissítés előtt
- Az Android automatikusan kezeli a running app cseréjét
- A beállítások egyszer kell megadni, utána már automatikus
- A figyelmeztetés 2 nyelven működik (EN/DE)

## Tesztelés
1. Új build létrehozása
2. Tag push (GitHub release)
3. Régi verzióval tesztelni az update-et
4. Első próbálkozásnál engedély kérés
5. Második próbálkozásnál telepítés ✓
