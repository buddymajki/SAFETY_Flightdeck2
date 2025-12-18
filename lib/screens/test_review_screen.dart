import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/test_model.dart';
import '../services/test_service.dart';
import '../services/app_config_service.dart';

/// Screen for reviewing graded test and signing off
/// 
/// Student sees:
/// - All questions with their answers
/// - Correct answers if they got it wrong
/// - Instructor feedback for text questions
/// - Checkbox to confirm understanding
/// - Sign button to finalize
class TestReviewScreen extends StatefulWidget {
  final TestMetadata test;
  final String userId;
  final TestSubmission submission;
  final TestContent testContent;

  const TestReviewScreen({
    super.key,
    required this.test,
    required this.userId,
    required this.submission,
    required this.testContent,
  });

  @override
  State<TestReviewScreen> createState() => _TestReviewScreenState();
}

class _TestReviewScreenState extends State<TestReviewScreen> {
  bool _understood = false;
  bool _acceptedGTC = false;
  bool _isSigning = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review Results'),
        centerTitle: true,
      ),
      body: _buildBody(),
      bottomNavigationBar: _buildSignButton(),
    );
  }

  Widget _buildBody() {
    // Get questions in the current language
    final lang = context.read<AppConfigService>().currentLanguageCode;
    List<Question> questions = widget.testContent.questions[lang] ?? [];
    if (questions.isEmpty) {
      questions = widget.testContent.questions['en'] ?? [];
    }
    if (questions.isEmpty && widget.testContent.questions.isNotEmpty) {
      questions = widget.testContent.questions.values.first;
    }

    // Filter out disclaimer question (id="disclaimer") - display it separately
    questions = questions.where((q) => q.id != 'disclaimer').toList();

    // Calculate score percentage
    int correctCount = 0;
    for (final question in questions) {
      final feedbackData = widget.submission.questionFeedback?[question.id] as Map?;
      if (feedbackData != null) {
        final isCorrect = feedbackData['isCorrect'] as bool? ?? feedbackData['isCirrect'] as bool?;
        if (isCorrect == true) correctCount++;
      } else if (question.type != QuestionType.text) {
        // Auto-evaluate non-text questions
        if (question.isAnswerCorrect(widget.submission.answers[question.id]) == true) {
          correctCount++;
        }
      }
    }
    final scorePercentage = ((correctCount / questions.length) * 100).toStringAsFixed(1);

    return SingleChildScrollView(
      child: Column(
        children: [
          // Score Header
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade600, Colors.blue.shade800],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Text(
                  'Your Score',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Colors.white70,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      scorePercentage,
                      style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '%',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '$correctCount of ${questions.length} questions correct',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          // Questions List
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: questions.length,
            itemBuilder: (context, index) {
              final question = questions[index];
              final answer = widget.submission.answers[question.id];
              
              // Check for feedback first (instructor graded this question)
              final feedbackData = widget.submission.questionFeedback?[question.id] as Map?;
              bool? isCorrect;
              
              if (feedbackData != null) {
                // Handle both 'isCorrect' and the typo 'isCirrect'
                if (feedbackData.containsKey('isCorrect')) {
                  isCorrect = feedbackData['isCorrect'] as bool?;
                } else if (feedbackData.containsKey('isCirrect')) {
                  isCorrect = feedbackData['isCirrect'] as bool?;
                }
              }
              
              // If no instructor feedback, auto-evaluate non-text questions
              if (isCorrect == null && question.type != QuestionType.text) {
                isCorrect = question.isAnswerCorrect(answer);
              }

              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Question number and text
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Text(
                                '${index + 1}',
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onPrimaryContainer,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              question.text,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Student's answer - highlighted based on correctness
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isCorrect == true
                              ? Colors.green.shade50
                              : isCorrect == false
                                  ? Colors.red.shade50
                                  : Colors.grey.shade50,
                          border: Border.all(
                            color: isCorrect == true
                                ? Colors.green.shade400
                                : isCorrect == false
                                    ? Colors.red.shade400
                                    : Colors.grey.shade400,
                            width: 1.5,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Your answer:',
                              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                color: isCorrect == true
                                    ? Colors.green.shade700
                                    : isCorrect == false
                                        ? Colors.red.shade700
                                        : Colors.grey.shade700,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _buildAnswerDisplay(question, answer),
                          ],
                        ),
                      ),
                      // Correctness indicator
                      Row(
                        children: [
                          Icon(
                            isCorrect == true
                                ? Icons.check_circle
                                : isCorrect == false
                                    ? Icons.cancel
                                    : Icons.hourglass_top,
                            color: isCorrect == true
                                ? Colors.green.shade600
                                : isCorrect == false
                                    ? Colors.red.shade600
                                    : Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isCorrect == true
                                ? 'Correct'
                                : isCorrect == false
                                    ? 'Incorrect'
                                    : 'Awaiting review',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: isCorrect == true
                                  ? Colors.green.shade700
                                  : isCorrect == false
                                      ? Colors.red.shade700
                                      : Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      // Show correct answer if wrong
                      if (isCorrect == false) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            border: Border.all(color: Colors.blue.shade300, width: 1.5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Correct answer:',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Colors.blue.shade700,
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              _buildCorrectAnswerDisplay(question),
                            ],
                          ),
                        ),
                      ],
                      // Instructor feedback for text questions
                      if (feedbackData != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            border: Border.all(color: Colors.blue.shade400, width: 1.5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Instructor feedback:',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Colors.blue.shade700,
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                feedbackData['feedback'] as String? ??
                                    'No feedback provided',
                                style:
                                    Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: Colors.blue.shade900,
                                      fontWeight: FontWeight.w500,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
          // Disclaimer (if present in test)
          if (widget.testContent.disclaimer != null && widget.testContent.disclaimer!.isNotEmpty)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2.5,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.gavel,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'Certification & Sign-Off',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // First Checkbox: Understanding and Readiness
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(255, 29, 86, 34), // Dark green
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF0D3818),
                        width: 2,
                      ),
                    ),
                    child: CheckboxListTile(
                      value: _understood,
                      activeColor: Colors.white,
                      checkColor: const Color(0xFF1B5E20),
                      side: const BorderSide(
                        color: Colors.white,
                        width: 2.5,
                      ),
                      onChanged: (value) {
                        setState(() {
                          _understood = value ?? false;
                        });
                      },
                      title: Text(
                        'I understand all corrections and feedbacks, I fully understand the theory and I feel ready for the first high flight.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w400,
                          fontSize: 15,
                          height: 1.5,
                        ),
                      ),
                      contentPadding: EdgeInsets.zero,
                      dense: false,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // GT&C Section Header
                  Text(
                    'Terms & Conditions:',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // GT&C Text - Scrollable
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.grey.shade400,
                        width: 1.5,
                      ),
                    ),
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: SingleChildScrollView(
                      child: Text(
                        widget.testContent.disclaimer!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.black87,
                          fontWeight: FontWeight.w500,
                          height: 1.6,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Second Checkbox: GT&C Acceptance
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D47A1), // Deep blue
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF0A3D91),
                        width: 2,
                      ),
                    ),
                    child: CheckboxListTile(
                      value: _acceptedGTC,
                      activeColor: Colors.white,
                      checkColor: const Color(0xFF0D47A1),
                      side: const BorderSide(
                        color: Colors.white,
                        width: 2.5,
                      ),
                      onChanged: (value) {
                        setState(() {
                          _acceptedGTC = value ?? false;
                        });
                      },
                      title: Text(
                        'I read the Terms & Conditions and I accept all points.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w400,
                          fontSize: 15,
                          height: 1.5,
                        ),
                      ),
                      contentPadding: EdgeInsets.zero,
                      dense: false,
                    ),
                  ),
                ],
              ),
            )
          else
            // Fallback: Simple acknowledgment checkbox if no disclaimer
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Acknowledgment',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    value: _understood,
                    onChanged: (value) {
                      setState(() {
                        _understood = value ?? false;
                      });
                    },
                    title: const Text(
                      'I understand all corrections and feedbacks, I fully understand the theory and I feel ready for the first high flight.',
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSignButton() {
    // Check if both checkboxes are needed (when there's a disclaimer)
    final hasDisclaimer = widget.testContent.disclaimer != null && 
                          widget.testContent.disclaimer!.isNotEmpty;
    final allAccepted = hasDisclaimer 
        ? (_understood && _acceptedGTC) 
        : _understood;
    
    // Build list of missing confirmations
    final missingCheckboxes = <String>[];
    if (!_understood) {
      missingCheckboxes.add('confirmation of understanding');
    }
    if (hasDisclaimer && !_acceptedGTC) {
      missingCheckboxes.add('T&C acceptance');
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!allAccepted)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Please confirm: ${missingCheckboxes.join(', ')}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            FilledButton(
              onPressed: allAccepted && !_isSigning ? _signOff : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: _isSigning
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text('Sign & Complete'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _signOff() async {
    setState(() {
      _isSigning = true;
    });

    try {
      final testService = Provider.of<TestService>(context, listen: false);
      await testService.acknowledgeTestReview(
        userId: widget.userId,
        testId: widget.test.id,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 12),
              Text('Test completed and signed!'),
            ],
          ),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSigning = false;
        });
      }
    }
  }

  Widget _buildAnswerDisplay(Question question, dynamic answer) {
    switch (question.type) {
      case QuestionType.singleChoice:
        final answerText = answer != null ? answer.toString() : 'No answer';
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade400, width: 1.5),
          ),
          child: Text(
            answerText,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey.shade900,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      case QuestionType.multipleChoice:
        List<String> selected = [];
        if (answer is List) {
          selected = answer.map((e) => e.toString()).toList();
        }
        if (selected.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade400, width: 1.5),
            ),
            child: Text(
              'No answers selected',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey.shade700,
                fontStyle: FontStyle.italic,
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: selected.map((opt) {
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade400, width: 1.5),
              ),
              child: Text(
                opt,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey.shade900,
                  fontWeight: FontWeight.w500,
                ),
              ),
            );
          }).toList(),
        );
      case QuestionType.trueFalse:
        final answerText = answer == true ? 'True' : answer == false ? 'False' : 'No answer';
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade400, width: 1.5),
          ),
          child: Text(
            answerText,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey.shade900,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      case QuestionType.text:
        final answerText = answer != null ? answer.toString() : 'No answer';
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade400, width: 1.5),
          ),
          child: Text(
            answerText,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey.shade900,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      case QuestionType.matching:
        Map<String, String> matches = {};
        if (answer is Map) {
          answer.forEach((key, value) {
            matches[key.toString()] = value.toString();
          });
        }
        if (matches.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade400, width: 1.5),
            ),
            child: Text(
              'No matches provided',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey.shade700,
                fontStyle: FontStyle.italic,
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: matches.entries.map((e) {
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade400, width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.key,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '→ ${e.value}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade800,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      default:
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade400, width: 1.5),
          ),
          child: Text(
            answer?.toString() ?? 'No answer',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey.shade900,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
    }
  }

  Widget _buildCorrectAnswerDisplay(Question question) {
    final displayText = _getCorrectAnswerDisplay(question);
    
    // For matching questions, display as a formatted list
    if (question.type == QuestionType.matching && displayText.contains('\n')) {
      final lines = displayText.split('\n');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: lines.map((line) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              line,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.blue.shade900,
                fontWeight: FontWeight.w500,
              ),
            ),
          );
        }).toList(),
      );
    }
    
    // For other types, just display as text
    return Text(
      displayText,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Colors.blue.shade900,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  String _getCorrectAnswerDisplay(Question question) {
    switch (question.type) {
      case QuestionType.singleChoice:
        if (question.correctOptionIndex != null &&
            question.correctOptionIndex! < question.options.length) {
          return question.options[question.correctOptionIndex!];
        }
        return 'N/A';
      case QuestionType.multipleChoice:
        if (question.correctOptionIndices != null) {
          final answers = question.correctOptionIndices!
              .where((i) => i < question.options.length)
              .map((i) => question.options[i])
              .join(', ');
          return answers.isNotEmpty ? answers : 'N/A';
        }
        return 'N/A';
      case QuestionType.trueFalse:
        return question.correctBoolAnswer == true ? 'True' : 'False';
      case QuestionType.text:
        return question.correctTextAnswer ?? 'N/A';
      case QuestionType.matching:
        if (question.correctMatchingPairs != null) {
          return question.correctMatchingPairs!
              .map((p) => '${p['left']} → ${p['right']}')
              .join('\n');
        }
        return 'N/A';
      default:
        return 'N/A';
    }
  }
}
