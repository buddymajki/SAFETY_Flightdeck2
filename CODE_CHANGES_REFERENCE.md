# Code Changes Reference

## File: `lib/models/test_model.dart`

### Change 1: TestContent Model - Add Disclaimer Field
**Location:** Lines 48-100

**What Changed:**
- Added `final String? disclaimer;` field to TestContent class
- Updated constructor to include disclaimer parameter
- Modified `TestContent.fromJson()` to extract disclaimer from JSON
- Supports both object format (with `text` field) and string format

**Code:**
```dart
class TestContent {
  final Map<String, List<Question>> questions;
  final Map<String, dynamic>? metadata;
  final String? disclaimer;  // ← NEW FIELD

  TestContent({
    required this.questions,
    this.metadata,
    this.disclaimer,  // ← NEW PARAMETER
  });

  factory TestContent.fromJson(Map<String, dynamic> json) {
    // ... existing code ...
    
    // Extract disclaimer if present
    String? disclaimer;
    if (json['disclaimer'] is Map) {
      disclaimer = (json['disclaimer'] as Map)['text'] as String?;
    } else if (json['disclaimer'] is String) {
      disclaimer = json['disclaimer'] as String?;
    }

    return TestContent(
      questions: questions,
      metadata: json['metadata'] as Map<String, dynamic>?,
      disclaimer: disclaimer,  // ← PASS TO CONSTRUCTOR
    );
  }
}
```

### Change 2: Question Model - Support img_url Field
**Location:** Line 246

**What Changed:**
- Updated `Question.fromJson()` to accept both `img_url` and `image_url` field names
- Uses fallback: tries `image_url` first, then `img_url`

**Code:**
```dart
return Question(
  // ... other fields ...
  imageUrl: json['image_url'] as String? ?? json['img_url'] as String?,  // ← UPDATED
  // ... other fields ...
);
```

---

## File: `lib/screens/tests_screen.dart`

### Change 1: _QuestionWidget - Display Images
**Location:** Lines 632-677

**What Changed:**
- Added image display section after question text
- Images displayed only if `imageUrl` is not null and not empty
- Added error handling for failed image loads
- Uses ClipRRect for rounded corners

**Code:**
```dart
@override
Widget build(BuildContext context) {
  return Card(
    // ... existing header code ...
    
    // Display image if available  ← NEW SECTION
    if (widget.question.imageUrl != null && widget.question.imageUrl!.isNotEmpty)
      Padding(
        padding: const EdgeInsets.only(top: 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            widget.question.imageUrl!,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Failed to load image'),
              );
            },
          ),
        ),
      ),
    
    const SizedBox(height: 16),
    // ... rest of widget ...
  );
}
```

### Change 2: TestTakingScreen - Show Disclaimer on Submit
**Location:** Lines 482-536

**What Changed:**
- Modified `_submitTest()` method to show disclaimer dialog before submission
- Check if disclaimer exists and show non-dismissible dialog
- Only proceed with submission if user accepts disclaimer
- If user declines, return early without submitting

**Code:**
```dart
Future<void> _submitTest() async {
  // Show disclaimer if available  ← NEW CODE
  if (_testContent?.disclaimer != null && _testContent!.disclaimer!.isNotEmpty) {
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _DisclaimerDialog(
        disclaimer: _testContent!.disclaimer!,
      ),
    );

    if (accepted != true) {
      return;  // ← EXIT WITHOUT SUBMITTING
    }
  }

  setState(() {
    _isSubmitting = true;
  });

  // ... existing submission code ...
}
```

### Change 3: New _DisclaimerDialog Widget
**Location:** Lines 906-1010

**What Changed:**
- Completely new widget class to display disclaimer with acceptance checkbox
- Non-dismissible dialog (cannot dismiss by tapping outside)
- Checkbox required before Accept button enables
- Professional appearance with warning icon and colored header

**Code:**
```dart
/// Dialog widget for displaying and accepting disclaimers
class _DisclaimerDialog extends StatefulWidget {
  final String disclaimer;

  const _DisclaimerDialog({
    required this.disclaimer,
  });

  @override
  State<_DisclaimerDialog> createState() => _DisclaimerDialogState();
}

class _DisclaimerDialogState extends State<_DisclaimerDialog> {
  bool _accepted = false;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with warning icon
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Please read and accept the following',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                  ),
                ),
              ],
            ),
          ),
          // Scrollable content
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Text(
                widget.disclaimer,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
          // Footer with checkbox and buttons
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Acceptance checkbox
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'I understand and accept the above terms',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  value: _accepted,
                  onChanged: (value) {
                    setState(() {
                      _accepted = value ?? false;
                    });
                  },
                ),
                const SizedBox(height: 16),
                // Action buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Decline'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _accepted
                          ? () => Navigator.of(context).pop(true)
                          : null,
                      child: const Text('Accept & Continue'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

---

## Summary of Changes

| File | Change | Lines | Type |
|------|--------|-------|------|
| `test_model.dart` | Add disclaimer field to TestContent | 48-100 | Model Update |
| `test_model.dart` | Support img_url field in Question | 246 | Model Update |
| `tests_screen.dart` | Display images in questions | 632-677 | UI Update |
| `tests_screen.dart` | Show disclaimer on submit | 482-536 | Logic Update |
| `tests_screen.dart` | Add _DisclaimerDialog widget | 906-1010 | New Widget |

**Total Lines Changed:** ~150 lines of new/modified code
**Files Modified:** 2 files
**New Features:** 2 features (image display, disclaimer handling)
**Backward Compatibility:** ✓ Yes (optional fields)
