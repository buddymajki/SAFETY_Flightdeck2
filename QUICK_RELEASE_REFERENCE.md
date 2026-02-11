# 🚀 QUICK REFERENCE: NEW AUTOMATIC WORKFLOW

## ⚡ EVERY RELEASE: 4 COMMANDS

```bash
# 1. Edit pubspec.yaml
#    🔴 CRITICAL RULE: ALWAYS INCREASE BOTH NUMBERS!
#    Version: 1.0.X → 1.0.(X+1)  [must change for git tag]
#    Build:   +(Y) → +(Y+1)       [MUST increase or Android install fails!]
#    
#    SIMPLE RULE: Use matching numbers!
#    Example: 1.0.10+10 → 1.0.11+11 → 1.0.12+12
#    
#    Change to: version: 1.0.11+11

# 2. Sync + Build
dart bin/update_version.dart
flutter build apk --release

# 3. Push to GitHub
git add .
git commit -m "Release v1.0.11"
git push origin master

# 4. Create Tag (triggers GitHub Actions)
git tag v1.0.11
git push origin --tags

# 🤖 GitHub Actions takes over automatically!
```

---

## 🔴 CRITICAL: BOTH VERSION AND BUILD NUMBER MUST INCREASE!

**Android ONLY checks the build number (+X)!** If it's the same or lower, you get "APP NOT INSTALLED" error.

**FOOL-PROOF RULE:** 
**Make both numbers the same and increase by 1 each time:**
```
1.0.9+9   → 1.0.10+10 → 1.0.11+11 → 1.0.12+12
```

**WHY THIS WORKS:**
- Version number increases → new git tag can be created ✅
- Build number increases → Android accepts the update ✅
- Both matching → easy to remember ✅

**COMMON MISTAKES:**
- ❌ `1.0.9+9` → `1.0.10+9` (build stayed same → "APP NOT INSTALLED" error!)
- ❌ `1.0.9+9` → `1.0.9+10` (version same → "tag already exists" error!)
- ❌ `1.0.9+10` → `1.0.10+10` (build same → "APP NOT INSTALLED" error!)
- ✅ `1.0.9+9` → `1.0.10+10` (both increased → works perfectly!)

**REMEMBER:**
- Android ONLY checks **build number (+X)**, not version string!
- If build number doesn't increase, Android refuses to install!
- Keep it simple: match the numbers (1.0.X+X)

---

## ✨ WHAT HAPPENS AUTOMATICALLY

| Step | What | Who Does |
|------|------|----------|
| 1 | Update pubspec.yaml | You manually |
| 2 | Update metadata.json | `dart bin/update_version.dart` ✅ |
| 3 | Update app_version_service.dart | `dart bin/update_version.dart` ✅ |
| 4 | Build APK | `flutter build apk --release` ✅ |
| 5 | Commit to GitHub | `git push` ✅ |
| 6 | Create Release | GitHub Actions 🤖 |
| 7 | Upload APK | GitHub Actions 🤖 |
| 8 | Users see update | App checks metadata.json ✅ |

---

## 📋 BEFORE vs NOW

### BEFORE (Complex, Manual):
```
pubspec
  ↓ (manual) Google Drive upload APK
  ↓ (manual) Edit metadata.json in Drive
  ↓ (manual) Git push
  → Users eventually see it
```

### NOW (Simple, Automatic):
```
pubspec
  ↓ (automatic) dart bin/update_version.dart
  ↓ (automatic) flutter build apk --release
  ↓ (automatic) git push
  → GitHub Actions
  → Release created
  → APK uploaded
  → Users see it IMMEDIATELY
```

---

## 🔑 KEY POINTS

✅ **metadata.json** - Now in GitHub repo, auto-generated  
✅ **App download URL** - Hardcoded to GitHub raw file  
✅ **APK hosting** - GitHub Releases  
✅ **Version sync** - One script does EVERYTHING  
✅ **No Firestore** - Gone!  
✅ **No manual uploads** - Gone!  

---

## 🎯 TYPICAL RELEASE (Real Example)

```bash
# You're at pubspec.yaml with version: 1.0.4+1
# You want to release 1.0.5

# Step 1: Edit
# vim pubspec.yaml
# Change: version: 1.0.4+1 → version: 1.0.5+2

# Step 2-3: Sync + Build (45 seconds)
$ dart bin/update_version.dart
🔄 Syncing version from pubspec.yaml...
📦 Found version: 1.0.5 (build 2)
✅ AppVersionService updated!
✅ metadata.json updated!

$ flutter build apk --release
Building FlightDeck for APK...
Built: build/app/outputs/flutter-apk/app-release.apk

# Step 4: Push (5 seconds)
$ git add .
$ git commit -m "Release v1.0.5"
$ git push origin master
✅ Pushed 3 files

# 🤖 AUTOMATIC FROM HERE:
# GitHub Actions detected push
# → Building...
# → Creating release...
# → Uploading APK...
# ✅ Release v1.0.5 is live!

# 👥 USERS:
# Open app → Sees update available → Installs → Done!
```

---

## �️ TROUBLESHOOTING

### ❌ "APP NOT INSTALLED" Error on Device
**Cause:** Build number (+X) didn't increase from previous install
**Example:** Device has 1.0.9+10, trying to install 1.0.10+10 (same +10!)
**Fix:** 
```bash
# Increase BOTH numbers in pubspec.yaml
version: 1.0.11+11  # Both must be higher!

# Then rebuild and release:
dart bin/update_version.dart
flutter build apk --release
git add . && git commit -m "Release v1.0.11"
git push origin master
git tag v1.0.11
git push origin --tags
```

### ❌ "Tag already exists" Error
**Cause:** Tried to use same version number twice (e.g., v1.0.9)
**Fix:** Increase version number and create new tag
```bash
# In pubspec.yaml: 1.0.9+X → 1.0.10+Y
git tag v1.0.10
git push origin --tags
```

### ⏳ Update doesn't appear in app
**Cause:** GitHub Actions still building (takes ~2-5 minutes after tag push)
**Fix:** Wait 3-5 minutes, then use "Check for Updates" in hamburger menu

---

## �🔐 SAFETY CHECKS

If something goes wrong:
- ✅ Metadata.json wrong format? → Script validates
- ✅ APK build failed? → You see error locally first
- ✅ GitHub Actions failed? → Check Actions tab for logs
- ✅ Users can't download? → Check GitHub Releases page

---

## 💡 REMEMBER

- **Edit pubspec.yaml** - This is your ONLY manual input
- **Run script** - `dart bin/update_version.dart` handles sync
- **Build APK** - `flutter build apk --release`
- **Git push** - Rest is automatic!

---

**That's it! Egyszerű, gyors, automatikus!** 🚀

See `AUTOMATIC_RELEASE_WORKFLOW.md` for detailed explanation.
