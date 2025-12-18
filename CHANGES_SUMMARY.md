# Changes Summary: Image Support and Disclaimer Handling

## Overview
Updated the test system to support displaying images in questions and showing a disclaimer that students must accept before test submission.

## Changes Made

### 1. **Question Model Updates** ([test_model.dart](lib/models/test_model.dart))

#### Image URL Field Support
- Updated `Question.fromJson()` to support both `img_url` and `image_url` field names
- The model now accepts both naming conventions from the JSON:
  ```dart
  imageUrl: json['image_url'] as String? ?? json['img_url'] as String?
  ```

### 2. **Test Content Model Updates** ([test_model.dart](lib/models/test_model.dart))

#### Disclaimer Support
- Added `disclaimer` field to `TestContent` class:
  ```dart
  final String? disclaimer;
  ```
- Updated `TestContent.fromJson()` to extract disclaimer from JSON
- Supports both object format (with `text` field) and string format:
  ```dart
  // Object format (from your example)
  {
    "id": "disclaimer",
    "type": "text",
    "text": "Disclaimer text here..."
  }
  
  // String format
  "Disclaimer text here..."
  ```

### 3. **Tests Screen Updates** ([tests_screen.dart](lib/screens/tests_screen.dart))

#### Image Display in Questions
- Updated `_QuestionWidget.build()` to display images below question text
- Added image rendering with:
  - Network image loading from `img_url`
  - Error handling for failed image loads
  - Rounded corners for better appearance
  - Responsive sizing

#### Disclaimer Dialog Implementation
- Modified `_submitTest()` to show disclaimer before submission
- Student must accept disclaimer to proceed with submission
- Created new `_DisclaimerDialog` widget with:
  - Scrollable disclaimer content
  - Checkbox for acceptance ("I understand and accept the above terms")
  - Decline and Accept buttons
  - Accept button disabled until checkbox is checked
  - Non-dismissible dialog (user must choose Decline or Accept)

## User Flow

### For Tests with Images:
1. Student sees question text
2. **Image displays below question** (if `img_url` is present in JSON)
3. Student answers question
4. Proceeds to next question

### For Tests with Disclaimer:
1. Student answers all questions
2. **Clicks "Submit Test"**
3. **Disclaimer Dialog appears** showing the full disclaimer text
4. Student must:
   - **Read the disclaimer**
   - **Check the acceptance checkbox**
   - **Click "Accept & Continue"** to submit
   - **Or click "Decline"** to go back without submitting

### Example JSON Structure
```json
{
  "en": [
    {
      "id": "q1",
      "type": "matching",
      "text": "Name the parts of the illustrated paraglider.",
      "img_url": "https://firebasestorage.googleapis.com/.../Linksvolte.png",
      "matchingPairs": [
        {"left": "1", "right": "Lower sail"},
        ...
      ],
      "correctAnswer": [...]
    }
  ],
  "disclaimer": {
    "id": "disclaimer",
    "type": "text",
    "text": "By signing below, I certify that...\n• I have completed...\n• I discussed and understand..."
  }
}
```

## Testing

To test these changes:

1. **Image Display**: Ensure questions with `img_url` show images properly
2. **Disclaimer**: Submit a test and verify:
   - Disclaimer dialog appears
   - Checkbox is required
   - Accept button is disabled until checked
   - Clicking Accept submits the test
   - Clicking Decline returns to test without submitting

## Notes

- Images display after the question text but before the answer input
- Disclaimer is NOT shown as a question - it only appears during submission
- The disclaimer acceptance is required to proceed with submission
- Both `img_url` and `image_url` field names are supported for compatibility
