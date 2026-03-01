# Xcode Cloud Troubleshooting (iOS)

This repo builds a Flutter iOS app (`Runner`) with Xcode Cloud.

## 1) Export fails (exit code 70) for **Development** / **Ad Hoc**

**Symptom (from `.xcdistributionlogs`):**
- `Xcode couldn't find any iOS App Development provisioning profiles matching 'com.flywithmiki.flightdeck'.`
- `Xcode couldn't find any iOS Ad Hoc provisioning profiles matching 'com.flywithmiki.flightdeck'.`
- Apple Portal error `resultCode 8220`:
  - `Your team has no devices from which to generate a provisioning profile.`

**Meaning:**
- Development and Ad Hoc provisioning profiles require at least one *real* registered iOS device UDID in the Apple Developer team.
- Simulator IDs do not count.

**Fix options (pick one):**
1. **Force Distribution Signing (Recommended for NO devices)**
   - Since you have no devices registered, you must prevent Xcode from trying to sign with a Development profile.
   - We have modified `ios/Flutter/Release.xcconfig` to force `CODE_SIGN_IDENTITY = Apple Distribution` and `CODE_SIGN_STYLE = Manual`.
   - This bypasses the need for registered devices during the Archive step.
   - Simply commit and push the changes to trigger a new build.

2. **Stop running Development/Ad Hoc exports in Xcode Cloud**
   - In App Store Connect → Xcode Cloud → your Workflow:
     - Ensure only **TestFlight / App Store** distribution is enabled.
     - Disable any “Development” or “Ad Hoc” distribution outputs (if shown).
   - If the UI doesn’t allow changing the existing workflow, create a *new* workflow that only distributes to TestFlight.

2. **Register any iPhone/iPad UDID (you don’t have to own it)**
   - Borrow a device from someone who is willing to have it registered.
   - Apple Developer → Certificates, Identifiers & Profiles → Devices → add the UDID.
   - Re-run the Xcode Cloud build.

> Note: Generating fake/invalid UDIDs is not a workable approach.

## 2) TestFlight/App Store export fails: App Store Connect authentication

**Symptoms (from `IDEDistribution.standard.log` / `IDEDistribution.critical.log`):**
- `Failed to find an account with App Store Connect access for team ... teamID='QNH8RGX236'`
- `Unable to authenticate with App Store Connect`

**Meaning:**
- Xcode Cloud can create the App Store provisioning profile, but it can’t authenticate to App Store Connect to fetch/upload as required.

**Fix checklist:**
- Log into https://appstoreconnect.apple.com with the Apple ID that owns the team.
- Accept any pending agreements (App Store Connect → Agreements, Tax, and Banking).
- Ensure the Apple ID has an appropriate App Store Connect role (e.g., Account Holder/Admin/App Manager).
- Ensure the App Store Connect app record exists and matches the bundle ID `com.flywithmiki.flightdeck`.
- Re-run the workflow.

## Reality check: “Can I develop without an iPhone?”

Yes:
- You can develop and run on the **iOS Simulator** without owning a phone.
- You can ship via **TestFlight** without devices.

No:
- You cannot produce **Development** / **Ad Hoc** signed IPA exports with *zero* registered devices.
