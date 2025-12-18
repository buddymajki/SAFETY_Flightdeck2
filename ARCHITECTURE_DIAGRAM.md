# Architecture & Implementation Diagram

## Data Flow Architecture

```
JSON Test File
     ↓
[img_url field]          [disclaimer field]
     ↓                         ↓
     |                         |
     v                         v
TestContent.fromJson()   →  TestContent object
     ↓                         ↓
  Question model          disclaimer field
  (imageUrl populated)    (String extracted)
     ↓                         ↓
     |                         |
     v                         v
_QuestionWidget       _submitTest()
  .build()                    ↓
     ↓            _DisclaimerDialog
 displays image       .build()
```

---

## Question Display Flow

```
┌─────────────────────────────────────────────────┐
│         Question Card (_QuestionWidget)         │
├─────────────────────────────────────────────────┤
│                                                  │
│  ┌─────┐ Question Text                          │
│  │ 1   │ Name the parts of the paraglider      │
│  └─────┘                                        │
│                                                  │
│  ┌──────────────────────────────────────────┐  │
│  │                                          │  │
│  │    [IMAGE FROM img_url - if present]     │  │
│  │                                          │  │
│  └──────────────────────────────────────────┘  │
│                                                  │
│  ┌──────────────────────────────────────────┐  │
│  │  Answer Input (matching pairs, etc)      │  │
│  └──────────────────────────────────────────┘  │
│                                                  │
└─────────────────────────────────────────────────┘
```

---

## Test Submission Flow

```
Student Complete
     ↓
Click "Submit Test"
     ↓
Does test have disclaimer?
     ├─ NO  → Submit immediately
     │
     └─ YES → Show Disclaimer Dialog
              ↓
         ┌────────────────────────────────┐
         │  DISCLAIMER DIALOG             │
         ├────────────────────────────────┤
         │ ⚠️  Please read and accept...  │
         │                                │
         │ [Scrollable disclaimer text]   │
         │                                │
         │ ☐ I understand and accept...  │
         │                                │
         │ [Decline]  [Accept & Continue] │
         └────────────────────────────────┘
              ↓                    ↓
         Decline             Accept (with checkbox)
              ↓                    ↓
         No submit            Submit test
              ↓                    ↓
         Return to test      Success message
```

---

## Code Structure: Classes & Methods

```
Models (test_model.dart)
├── TestContent
│   ├── questions: Map<String, List<Question>>
│   ├── metadata: Map<String, dynamic>?
│   └── disclaimer: String?  ← NEW FIELD
│
└── Question
    ├── id: String
    ├── type: QuestionType
    ├── text: String
    ├── imageUrl: String?  ← UPDATED (supports img_url)
    └── ... other fields ...

Screens (tests_screen.dart)
├── TestTakingScreen
│   └── _TestTakingScreenState
│       ├── _submitTest()  ← MODIFIED (show disclaimer)
│       ├── _testContent: TestContent?
│       └── _answers: Map<String, dynamic>
│
├── _QuestionWidget
│   └── _QuestionWidgetState
│       └── build()  ← MODIFIED (display image)
│
└── _DisclaimerDialog  ← NEW CLASS
    └── _DisclaimerDialogState
        ├── _accepted: bool
        └── build()
```

---

## State Management in Disclaimer Dialog

```
_DisclaimerDialog
    ↓
_DisclaimerDialogState
    ↓
[_accepted = false initially]
    ↓
User interacts:
    ├─ Checks checkbox → setState() → _accepted = true
    │                  → Accept button enables
    │
    ├─ Clicks "Decline" → Navigator.pop(false)
    │
    └─ Clicks "Accept" → Navigator.pop(true)
         [only if _accepted == true]
         ↓
    Returns to _submitTest()
         ↓
    If true → proceed with submission
    If false → return (no submission)
```

---

## JSON Parsing Flow

### Input JSON
```json
{
  "en": [
    {
      "id": "q1",
      "type": "matching",
      "text": "Question...",
      "img_url": "https://...",
      "matchingPairs": [...]
    }
  ],
  "disclaimer": {
    "id": "disclaimer",
    "type": "text",
    "text": "By signing below..."
  }
}
```

### Parsing Process
```
TestContent.fromJson(json)
    ↓
Parse "en" key → List of questions
    ├─ For each question:
    │  └─ Question.fromJson()
    │     ├─ Check json['image_url']
    │     ├─ Fallback to json['img_url']
    │     └─ Set imageUrl field
    ↓
Parse "disclaimer" key
    ├─ If Map: extract json['disclaimer']['text']
    └─ If String: use directly
    ↓
Return TestContent object
    ├─ questions: Map with parsed questions
    └─ disclaimer: String (if present)
```

---

## Error Handling

### Image Loading Errors
```
Image.network(url)
    ↓
Success? → Display image
    ↓
Failed?  → Show error container
         └─ "Failed to load image" message
         └─ Graceful fallback
```

### Disclaimer Processing
```
_submitTest()
    ↓
disclaimer != null && !isEmpty?
    ├─ NO  → Submit directly
    │
    └─ YES → Show dialog
         ↓
    User interaction?
         ├─ Decline → Exit (no submit)
         └─ Accept → Continue with submit
```

---

## Integration Points

```
┌────────────────────────────────────────┐
│       Firebase Storage (Images)         │
│     [stores paraglider images, etc.]    │
└────────┬─────────────────────────────────┘
         │
         ↓ [Image URLs in JSON]
         
┌────────────────────────────────────────┐
│         Test JSON File                  │
│    [questions + disclaimer]             │
└────────┬─────────────────────────────────┘
         │
         ↓ [Loaded by TestService]
         
┌────────────────────────────────────────┐
│      TestContent Object                 │
│  [TestContent.fromJson()]               │
└────────┬─────────────────────────────────┘
         │
         ↓ [Provided to screens]
         
┌─────────────────────────────────────────────────────────┐
│         Test UI Screens                                  │
│  - _QuestionWidget [displays questions + images]        │
│  - _DisclaimerDialog [shows disclaimer on submit]      │
│  - _submitTest() [handles submission with disclaimer]   │
└─────────────────────────────────────────────────────────┘
```

---

## Modification Summary by Layer

| Layer | Before | After | Change |
|-------|--------|-------|--------|
| **Data** | No disclaimer support | Disclaimer field added | ✓ |
| **Model** | Only image_url field | Both img_url & image_url | ✓ |
| **Display** | No question images | Images display with text | ✓ |
| **Logic** | Direct submission | Disclaimer check → submit | ✓ |
| **Dialog** | No disclaimer UI | Full dialog with checkbox | ✓ |

---

## Backward Compatibility

```
Existing Tests (no changes)
    ↓
img_url field? NO → Image display skipped
    ↓
disclaimer field? NO → Submit directly
    ↓
All functionality works as before ✓

New Tests (with features)
    ↓
img_url field? YES → Image displays ✓
    ↓
disclaimer field? YES → Dialog shown ✓
    ↓
Full new functionality works ✓
```
