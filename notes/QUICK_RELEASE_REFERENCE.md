# QUICK_RELEASE_REFERENCE
## Overview
This document serves as a quick reference for the release process of the FlightDeck application.
...existing content...
# QUICK REFERENCE: RELEASE WORKFLOW

## EVERY RELEASE: JUST CHANGE THE VERSION AND RUN 5 COMMANDS

```bash
# 1. Edit pubspec.yaml - change ONLY the version number
#    Example: version: 1.0.13 -> version: 1.0.14
#    (No build number needed! Script handles it automatically)

# 2. Sync + Build
dart bin/update_version.dart
flutter build apk --release

# 3. Push to GitHub
git add .
git commit -m "Release v1.0.14"
git push origin master

# 4. Create tag + upload APK
git tag v1.0.14
git push origin --tags
gh release upload v1.0.14 build\app\outputs\flutter-apk\app-release.apk --clobber
```

That's it! The APK built on YOUR machine goes directly to GitHub.
Users will see the update in the app.

---

## WHY THIS WORKS

- You build the APK locally = same signing key every time
- GitHub Actions only creates the release page (no build)
- gh CLI uploads YOUR APK to the release
- Build number is auto-calculated from version (1.0.13 = build 10013)
- Build number always increases as version increases

---

## VERSION RULES

**Simple:** Just increase the last number each time.

```
1.0.12 -> 1.0.13 -> 1.0.14 -> 1.0.15 -> ...
```

**NO build number (+X) needed in pubspec.yaml!**
The script auto-generates it from the version number.

---

## TROUBLESHOOTING

### "APP NOT INSTALLED" Error
**Cause:** Signing key mismatch (APK built on different machine)
**Fix:** Always use YOUR local build, never the GitHub Actions build.
That's why we upload the local APK with `gh release upload`.

### "Tag already exists" Error
**Cause:** Same version number used twice
**Fix:** Increase version number in pubspec.yaml

### Update doesn't appear in app
**Cause:** APK not yet uploaded to release
**Fix:** Run `gh release upload v1.0.X build\app\outputs\flutter-apk\app-release.apk --clobber`

---

## COPY-PASTE TEMPLATE

Replace X.X.X with your new version number:

```powershell
$ver="1.0.20"; dart bin/update_version.dart; flutter build apk --release; git add .; git commit -m "Release v$ver"; git push origin master; git tag v$ver; git push origin --tags; Start-Sleep -Seconds 30; gh release upload v$ver build\app\outputs\flutter-apk\app-release.apk --clobber
```
