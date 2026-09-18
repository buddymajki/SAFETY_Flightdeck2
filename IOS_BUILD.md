# iOS build → TestFlight, lépésről lépésre (v1.0.44, build 10044)

**A lényeg előre:** ez a folyamat **majdnem teljesen terminálból** megy. Az Xcode-ra
pontosan **két dologra** van szükség:

1. **egyszer** be kell jelentkezni benne az Apple ID-ddal (ettől tud a gép aláírni),
2. ha a terminálos build elakad az aláíráson, akkor tartalékként onnan is lehet
   archiválni.

A feltöltést a **Transporter** nevű ingyenes Apple app csinálja: bedobod az
`.ipa` fájlt és kész. Xcode-dal nem kell szenvedni.

Jelölések: **[TERM]** = terminál (a VS Code beépített terminálja is jó, semmi
különbség), **[XCODE]** = az Xcode ablaka, **[WEB]** = böngésző.

---

## 0. Egyszeri előkészítés — csak legelső alkalommal kell

### 0.1 [TERM] Mi van már fent?

```bash
flutter --version
xcodebuild -version
pod --version
```

Amit látnod kell:
- `flutter` → `Flutter 3.38.x` (ha régebbi: `flutter upgrade`)
- `xcodebuild` → `Xcode 16.x` vagy újabb
- `pod` → `1.15` vagy újabb

### 0.2 [TERM] Ha az `xcodebuild` hibát ad

Tipikus hiba: *„xcode-select: error: tool 'xcodebuild' requires Xcode"*.
Ilyenkor az Xcode fent van, de a rendszer a Command Line Toolsra mutat:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
sudo xcodebuild -license accept
```

Ha az Xcode egyáltalán nincs fent: Mac App Store → Xcode → telepítés (nagy, tervezz rá időt).

### 0.3 [TERM] Ha a `pod` nincs meg

```bash
brew install cocoapods
```

Ha nincs Homebrew, vagy a fenti nem megy:

```bash
sudo gem install cocoapods
```

> Hackintoshon a `sudo gem install` gyakran elhasal a rendszer-Ruby miatt.
> Ilyenkor a `brew install cocoapods` a járható út.

### 0.4 [XCODE] Apple ID bejelentkezés — **ez az egyetlen kötelező Xcode-lépés**

1. Nyisd meg az **Xcode**-ot (elég maga az app, projektet nem kell megnyitni).
2. Menü: **Xcode → Settings…** (vagy `⌘ + ,`)
3. **Accounts** fül → bal alul **`+`** → **Apple ID** → jelentkezz be.
4. Ha kész, a listában látnod kell a csapatodat. A projekt ehhez a Team ID-hoz
   van kötve: **`QNH8RGX236`**.

Ettől tudja az Xcode automatikusan legyártani a *Distribution* tanúsítványt és az
*App Store* provisioning profile-t. Regisztrált iPhone **nem kell** hozzá —
TestFlight-hoz nincs szükség eszköz-UDID-ra.

Innentől az Xcode-ot **be is zárhatod**.

---

## 1. [TERM] A kód lehúzása

Ha még nincs a gépen a repo:

```bash
cd ~
git clone https://github.com/buddymajki/SAFETY_Flightdeck2.git
cd SAFETY_Flightdeck2
```

Ha már megvan:

```bash
cd ~/SAFETY_Flightdeck2
git checkout master
git pull
```

**Ellenőrzés — ezt írja ki:**

```bash
grep '^version:' pubspec.yaml
```
```
version: 1.0.44+10044
```

Ha mást ír, nem húztad le a friss kódot. Menj vissza a `git pull`-ra.

---

## 2. [TERM] Függőségek + CocoaPods

**Ezt most kötelező megcsinálni.** Az előző iOS build óta **5 csomag kikerült** a
projektből (`flutter_background_service`, `flutter_local_notifications`, `dio`,
`path_provider`, `reorderables`), de az `ios/Podfile.lock` még a régieket
sorolja fel. Ha nem generálod újra, a build elhasal egy nemlétező
`.symlinks/plugins/...` útvonalon.

```bash
flutter clean
flutter pub get

cd ios
rm -rf Pods Podfile.lock
pod install --repo-update
cd ..
```

**Mit csinál a `pod install`?** A Flutter-pluginok natív iOS részeit (Firebase,
GPS, hang stb.) tölti le és köti be az Xcode projektbe. Ez hozza létre a
`Runner.xcworkspace`-t — ezért kell később *azt* nyitni, nem a `.xcodeproj`-ot.

**Sikeres, ha ezt írja a végén:**
```
Pod installation complete! There are NN dependencies from the Podfile and NN total pods installed.
```

**Ha CDN/hálózati hibát ad:**
```bash
pod repo update
pod install
```

Ez első alkalommal lassú (több perc, akár 10+), mert letölti a teljes pod-indexet.

---

## 3. [TERM] A build

```bash
flutter build ipa --release
```

Ez lefordítja a Dart kódot, archivál és exportál — **egyben**. Lassú gépen
nyugodtan **20–40 perc**. Közben látszólag megáll a „Running Xcode build…"
sornál percekre — ez normális, **ne szakítsd meg**.

**Sikeres, ha a végén valami ilyet ír:**
```
✓ Built IPA to build/ios/ipa
```

**Ellenőrizd, hogy tényleg ott van:**
```bash
ls -lh build/ios/ipa/
```

Egy `.ipa` fájlt kell látnod, nagyjából 60–90 MB.

> Ha a build az **aláírásnál** hasal el (`No profiles for 'com.flywithmiki.ios'
> were found` vagy `Signing for "Runner" requires a development team`), ne
> bűvészkedj a terminálban — ugorj a **3B**-re.

### 3B. [XCODE] Tartalék út, ha a 3. lépés elhasalt az aláíráson

```bash
open ios/Runner.xcworkspace
```

> **`Runner.xcworkspace`**, NE `Runner.xcodeproj`! A `.xcodeproj` nem ismeri a
> pod-okat, és „Module 'firebase_core' not found" típusú hibákat fogsz kapni.

Az Xcode-ban:

1. Bal oldali fában kattints a legfelső kék **Runner** ikonra.
2. Középen, a TARGETS alatt válaszd a **Runner** targetet (ne a PROJECT-et).
3. **Signing & Capabilities** fül:
   - **Automatically manage signing** — pipa be
   - **Team** — válaszd ki a csapatodat (`QNH8RGX236`)
   - Várd meg, míg a „Provisioning Profile: Xcode Managed Profile" sor
     hibaüzenet nélkül megjelenik.
4. Felül, az ablak tetején a futtatási célnál (ahol egy szimulátor neve van)
   válaszd: **Any iOS Device (arm64)**.
   *Ha szimulátor van kiválasztva, az Archive menüpont szürke marad.*
5. Menü: **Product → Archive**. (Megint 20–40 perc.)
6. Amikor kész, magától felugrik az **Organizer** ablak az archívummal.
   → innen a **4B** lépés.

---

## 4. [TRANSPORTER] Feltöltés App Store Connectbe

Ez a legegyszerűbb út, és nem kell hozzá Xcode.

1. **Mac App Store → „Transporter"** (Apple ingyenes appja) → telepítsd.
2. Indítsd el, jelentkezz be ugyanazzal az Apple ID-val.
3. Húzd bele a `build/ios/ipa/` mappából a `.ipa` fájlt (vagy `+` → Add App).
4. **Deliver** gomb.

A feltöltés végén „Delivered successfully" üzenetet kell látnod.

### 4B. [XCODE] Ha a 3B úton mentél (Organizer)

Az Organizer ablakban:

1. Jelöld ki a most készült archívumot (dátum szerint a legfelső).
2. Jobb oldalt: **Distribute App**
3. **App Store Connect** → Next
4. **Upload** → Next
5. A következő képernyőkön hagyj mindent alapértelmezetten → **Next / Upload**
6. Várd meg a „Upload Successful" üzenetet.

---

## 5. [WEB] TestFlight

1. Nyisd meg: https://appstoreconnect.apple.com → **My Apps** → FlightDeck
2. **TestFlight** fül.
3. A build először **„Processing"** állapotban lesz — ez **5–30 perc**, türelem.
   (Kapsz e-mailt is, amikor kész.)
4. Ha kész, a build mellett kattints, és add hozzá a tesztelői csoportodhoz.
5. A tesztelők automatikusan kapnak értesítést.

**A 90 napos lejárat innen számolódik újra.**

> Export compliance kérdést **nem** fog feltenni — az `Info.plist`-ben már benne
> van az `ITSAppUsesNonExemptEncryption = false`.

---

## 6. [TERM] Egy commit vissza, hogy legközelebb gyorsabb legyen

A `pod install` újraírta az `ios/Podfile.lock`-ot. Tedd vissza a repóba, hogy a
következő buildnél már ne fusson bele senki a stale lock-ba:

```bash
git add ios/Podfile.lock
git commit -m "chore(ios): regenerate Podfile.lock after dependency cleanup"
git push
```

---

## Ha elakadsz — a tipikus hibák

| Hibaüzenet | Mi a baj | Megoldás |
|---|---|---|
| `Module 'firebase_core' not found` | a `.xcodeproj`-ot nyitottad meg, vagy nem futott a `pod install` | 2. lépés újra, majd `open ios/Runner.xcworkspace` |
| `No profiles for 'com.flywithmiki.ios' were found` | nincs bejelentkezve Apple ID az Xcode-ban | 0.4 lépés |
| `Signing for "Runner" requires a development team` | ugyanaz | 0.4 lépés |
| `The bundle version must be higher than the previously uploaded version` | a 10044-es build számot már feltöltötted egyszer | `pubspec.yaml`-ban `1.0.44+10045`, majd `dart bin/update_version.dart`, és 2–4. lépés újra |
| `error: unable to find utility "xcodebuild"` | rossz developer dir | 0.2 lépés |
| A `pod install` végtelenségig pörög | CocoaPods CDN | `pod repo update` külön, utána `pod install` |
| Az **Archive** menüpont szürke | szimulátor van kiválasztva | felül állítsd **Any iOS Device (arm64)**-re |
| A build „megáll" 10 percre | nem állt meg, csak lassú | hagyd futni |

---

## Amit erről a buildről tudni érdemes

- **Update-ellenőrzés kikapcsolva** (`lib/config/feature_flags.dart` →
  `updateCheckEnabled = false`). iOS-en a TestFlight amúgy is maga értesíti a
  tesztelőket. Nincs se automatikus, se kézi ellenőrzés, és a menüből eltűnt a
  „Check for Updates" sor.
- **Checklist fülek**: az 1.0.43-ban javított beágyazott görgetés-hiba **most jut
  el először iOS-re** (a TestFlight build közben lejárt), plusz a fülsáv fölé
  lógó nyilak eddig eltakarták az első és utolsó fület — most a sáv mellé
  kerültek.
- **Ernyőválasztó**: a kódbeli hibát javítottuk, **de a működéshez a Firestore
  security rules deploy is kell** (`firebase deploy --only firestore:rules`).
  A `/gliders` kollekció szabálya sosem lett élesítve, ezért a Firestore minden
  olvasást visszautasít — Androidon is, iOS-en is. Ha a deploy megvan, ez a
  build már működni fog, nem kell újrabuildelni.
- **Ismert, szándékosan nem javított** (`MASTER_TODO.md` R-6): a
  `lib/firebase_options.dart` iOS blokkjában `iosBundleId:
  'com.example.flightdeckFirebase'` áll, míg az Xcode projekt bundle ID-ja
  `com.flywithmiki.ios`. Eddig is így épült és működött; egy Firebase iOS app
  újraregisztrálása külön lépés, a TestFlight-határidő előtt nem érdemes
  kockáztatni.
- Nincs `ios/Runner/GoogleService-Info.plist` — az app a `firebase_options.dart`
  -ból inicializálja a Firebase-t. Ez így helyes, ne keresd a plistet.
- Apróság a jövőre: az iPhone kezdőképernyőjén az app neve **„Flightdeck
  Firebase"** (`CFBundleDisplayName`), Androidon „FlightDeck". Ha egységesíted,
  az `ios/Runner/Info.plist`-ben írd át.
