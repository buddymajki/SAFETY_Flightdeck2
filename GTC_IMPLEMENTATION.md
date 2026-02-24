# GTC_IMPLEMENTATION
## Overview
This document describes the GT&C system implemented in the FlightDeck application. The system allows schools to define terms and conditions that students must accept before proceeding. Acceptances are tracked per user/school combination for audit and compliance purposes.
...existing content...
# General Terms & Conditions (GT&C) Implementation Guide

## Overview
This document describes the GT&C system implemented in the FlightDeck application. The system allows schools to define terms and conditions that students must accept before proceeding. Acceptances are tracked per user/school combination for audit and compliance purposes.

## Architecture

### 1. **GTCService** (`lib/services/gtc_service.dart`)
Manages GT&C data fetching, caching, and acceptance tracking.

#### Key Methods:
- **`loadGTC(String schoolId)`**: Fetches GT&C document from `schools/<school_id>`
- **`checkGTCAcceptance(String uid, String schoolId)`**: Checks if user has accepted current GT&C version
- **`acceptGTC(String uid, String schoolId)`**: Records GT&C acceptance with timestamp and version
- **`resetGTCAcceptance(String uid, String schoolId)`**: Forces re-acceptance (used when GT&C version changes)
- **`clearGTCCache()`**: Clears all cached GT&C data

#### Properties:
- `currentGTC`: The loaded GT&C document
- `currentAcceptance`: User's acceptance record for current school
- `isGTCAccepted`: Boolean flag indicating if current user has accepted current GT&C
- `currentGTCVersion`: Current GT&C version

### 2. **Profile Screen Integration** (`lib/screens/profile_screen.dart`)
The GT&C section is displayed in the profile screen for students who have selected a school.

#### Key Features:
- Automatically loads GT&C when user selects a school
- Displays expandable sections with checkboxes
- Enforces acceptance of all required sections
- Shows acceptance status (accepted/not accepted)
- Displays acceptance timestamp after successful acceptance

## Firestore Data Structure

### School GT&C Document
**Path**: `schools/<school_id>`

```json
{
  "school_name": "String",
  "gtc_version": "1.0",
  "gtc_sections": [
    {
      "id": "section_1",
      "title": "Privacy Policy",
      "content": "Long text describing privacy terms...",
      "required": true
    },
    {
      "id": "section_2",
      "title": "Code of Conduct",
      "content": "Long text describing conduct rules...",
      "required": true
    },
    {
      "id": "section_3",
      "title": "Optional Survey",
      "content": "Optional content...",
      "required": false
    }
  ]
}
```

### User GT&C Acceptance Record
**Path**: `users/<uid>/gtc_acceptances/<school_id>`

```json
{
  "gtc_accepted": true,
  "gtc_accepted_at": "2024-12-17T15:30:00Z",
  "gtc_version": "1.0"
}
```

## User Flow

### Initial School Selection
1. User creates profile as "Student"
2. User selects a school from searchable dropdown
3. GT&C section automatically loads for that school
4. User sees GT&C sections with checkboxes
5. User must check all required sections
6. User clicks "Accept & Sign" button
7. Acceptance is recorded in Firestore with timestamp

### School Change Scenario
1. User changes selected school
2. GT&C section updates to new school's GT&C
3. If no acceptance exists for new school, user must accept it
4. Previous acceptances for other schools remain in Firestore (for audit trail)
5. Only the acceptance for the current `school_id` matters for access control

### GT&C Version Update Scenario
1. School admin updates GT&C document and increments `gtc_version`
2. User has stale acceptance record with old version
3. System detects version mismatch and forces re-acceptance
4. User must re-accept new GT&C version
5. New acceptance record is created with updated version

## Implementation Details

### Checkbox State Management
```dart
Map<String, bool> _gtcCheckboxStates = {}; // Track per-section acceptance
```
- Checkboxes are tied to section IDs
- State is maintained in the widget
- Only required sections block acceptance

### Acceptance Validation
```dart
bool _allRequiredGTCAccepted(List<Map<String, dynamic>> gtcSections) {
  // Returns true only if ALL required sections are checked
}
```

### Version Mismatch Detection
```dart
if (acceptedVersion != currentVersion) {
  _currentAcceptance = null; // Force re-acceptance
}
```

## UI/UX Features

### Display States
1. **Loading**: Shows spinner while fetching GT&C
2. **Not Accepted**: Shows sections with checkboxes and "Accept & Sign" button
3. **Accepted**: Shows checkmark and acceptance timestamp
4. **No GT&C**: Hidden if school has no GT&C document

### Visual Feedback
- Required sections show "(Required)" tag
- Optional sections show "(Optional)" tag
- Error state shows warning message if not all required items are checked
- Disabled "Accept & Sign" button until all required sections are checked
- Green checkmark and timestamp displayed after acceptance

### Responsive Design
- Uses ResponsiveListView for consistent spacing
- Card-based layout matching other profile sections
- Proper padding and margins for readability

## Audit Trail
All acceptances are permanently stored in Firestore at:
```
users/{uid}/gtc_acceptances/{school_id}
```

This enables:
- Historical record of which GT&C version was accepted
- Timestamp of acceptance for compliance
- Multiple schools can have separate acceptances for same user
- Previous acceptances preserved when user switches schools

## Edge Cases Handled

### 1. Missing GT&C Document
- GT&C section is hidden if school has no document
- No errors or warnings shown

### 2. Empty GT&C Sections
- Section is not displayed if no sections are defined
- System gracefully handles missing data

### 3. Network Failure
- Error handling with fallback to null acceptance
- User can retry by changing school or refreshing

### 4. Timestamp Formatting
- Uses DateFormat('yyyy-MM-dd HH:mm') for display
- Handles Firestore Timestamp objects properly
- Graceful error handling if timestamp is invalid

## Testing Scenarios

### Test 1: Basic Acceptance
1. Create student profile
2. Select school with GT&C
3. Check all required sections
4. Click "Accept & Sign"
5. Verify record in Firestore
6. Refresh profile - should show accepted status

### Test 2: School Change
1. Accept GT&C for School A
2. Change school to School B
3. Verify School B's GT&C is displayed
4. Accept School B's GT&C
5. Verify both acceptances exist in Firestore

### Test 3: Version Update
1. Accept GT&C version 1.0
2. Admin updates school GT&C to version 1.1
3. Refresh profile
4. Verify system detects version mismatch
5. Verify user must re-accept

### Test 4: Optional Sections
1. See optional sections with checkboxes
2. Leave optional sections unchecked
3. Verify "Accept & Sign" is enabled if all required sections are checked
4. Verify system allows acceptance without optional sections

## Future Enhancements

1. **Email Notification**: Send confirmation email when GT&C is accepted
2. **Digital Signature**: Add signature capture widget
3. **Multi-language Support**: Translate GT&C sections
4. **Admin Dashboard**: View acceptance statistics per school
5. **Bulk Acceptance**: Admin can manually mark acceptance for bulk users
6. **Expiring GT&C**: Add expiration date to force re-acceptance
7. **Conditional Sections**: Show/hide sections based on user attributes
8. **Document Attachment**: Link PDF or document to GT&C sections

## Troubleshooting

### GT&C Not Showing
- Check that user has selected a school
- Verify school document exists in Firestore at `schools/<school_id>`
- Check that `gtc_sections` array is not empty

### Acceptance Not Saving
- Verify Firestore write permissions for `users/{uid}/gtc_acceptances/{school_id}`
- Check network connectivity
- Review Firebase console for error messages

### Version Mismatch Issues
- Ensure `gtc_version` field exists in school document
- Verify version number format (string, e.g., "1.0")
- Check that acceptance record has `gtc_version` field

## Security Considerations

1. **Firestore Rules**: Ensure rules prevent users from modifying others' acceptances
2. **Timestamp Server**: Use `FieldValue.serverTimestamp()` to prevent client clock manipulation
3. **User Verification**: System relies on authentication - verify user is logged in
4. **Version Integrity**: Validate GT&C version before marking as accepted

## Migration Guide

### Adding GT&C to Existing School
1. Add GTCService to provider in main.dart if not already added
2. Create school GT&C document with structure shown above
3. Increment school document version if needed
4. Users will see GT&C on next profile load

### Updating GT&C Content
1. Update `gtc_sections` array in school document
2. Increment `gtc_version` field
3. System will automatically force re-acceptance for all users

### Removing GT&C
1. Delete `gtc_sections` array or make it empty
2. GT&C section will be hidden from profile UI
3. Existing acceptance records remain in Firestore for audit trail
