import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/test_model.dart';
import '../services/test_service.dart';
import '../services/app_config_service.dart';
import '../auth/auth_service.dart';
import 'test_review_screen.dart';

/// Main tests listing screen
class TestsScreen extends StatefulWidget {
  const TestsScreen({super.key});

  @override
  State<TestsScreen> createState() => _TestsScreenState();
}

class _TestsScreenState extends State<TestsScreen> {
  @override
  void initState() {
    super.initState();
    // Load tests when screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<TestService>(context, listen: false).loadAvailableTests();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(

      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final testService = Provider.of<TestService>(context);

    if (testService.isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading available tests...'),
          ],
        ),
      );
    }

    if (testService.error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Error loading tests',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                testService.error!,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => Provider.of<TestService>(context, listen: false)
                  .loadAvailableTests(),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (testService.availableTests.isEmpty) {
      return const Center(
        child: Text('No tests available yet'),
      );
    }

    final auth = Provider.of<AuthService>(context, listen: false);
    final user = auth.currentUser;

    if (user == null) {
      return const Center(
        child: Text('Not authenticated'),
      );
    }

    return RefreshIndicator(
      onRefresh: () => testService.loadAvailableTests(),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: testService.availableTests.length,
        itemBuilder: (context, index) {
          final test = testService.availableTests[index];
          return _TestCard(
            test: test,
            userId: user.uid,
            onTap: () => _openTest(context, test, user.uid),
          );
        },
      ),
    );
  }

  void _openTest(BuildContext context, TestMetadata test, String userId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TestTakingScreen(
          test: test,
          userId: userId,
        ),
      ),
    );
  }
}

/// Card widget displaying a single test in the list
class _TestCard extends StatelessWidget {
  final TestMetadata test;
  final String userId;
  final VoidCallback onTap;

  const _TestCard({
    required this.test,
    required this.userId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final testService = Provider.of<TestService>(context, listen: false);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.assignment,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      test.testEn,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 4),
                    FutureBuilder<TestSubmission?>(
                      future: testService.getSubmission(userId, test.id),
                      builder: (context, snapshot) {
                        final sub = snapshot.data;
                        String label = 'Tap to start test';
                        Color? color =
                            Theme.of(context).colorScheme.onSurfaceVariant;
                        if (sub != null) {
                          if (sub.status == 'acknowledged') {
                            label = '✓ DONE - PASSED';
                            color = Colors.green;
                          } else if (sub.status == 'final') {
                            label = 'Final results available';
                            color = Colors.greenAccent.shade200;
                          } else {
                            label = 'Submitted (waiting for review)';
                            color = Theme.of(context).colorScheme.primary;
                          }
                        }
                        return Text(
                          label,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: color),
                        );
                      },
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Screen for taking a test - loads questions and allows user to answer
class TestTakingScreen extends StatefulWidget {
  final TestMetadata test;
  final String userId;

  const TestTakingScreen({
    super.key,
    required this.test,
    required this.userId,
  });

  @override
  State<TestTakingScreen> createState() => _TestTakingScreenState();
}

class _TestTakingScreenState extends State<TestTakingScreen> {
  TestContent? _testContent;
  bool _isLoading = true;
  String? _error;
  final Map<String, dynamic> _answers = {};
  bool _isSubmitting = false;
  bool _readOnly = false;
  Map<String, dynamic>? _perQuestionResults;
  int _currentQuestionIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadTestContent();
  }

  Future<void> _loadTestContent() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final testService = Provider.of<TestService>(context, listen: false);
      final content = await testService.loadTestContent(widget.test.testUrl);

      // Check prior submission
      final existing =
          await testService.getSubmission(widget.userId, widget.test.id);
      bool ro = false;
      Map<String, dynamic>? per;
      if (existing != null) {
        _answers.clear();
        _answers.addAll(existing.answers);

        // If status is 'final', redirect to review/sign-off screen
        if (existing.status == 'final' && !mounted) return;
        if (existing.status == 'final') {
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => TestReviewScreen(
                  test: widget.test,
                  userId: widget.userId,
                  submission: existing,
                  testContent: content,
                ),
              ),
            );
          }
          return;
        }

        ro = true;
        final rd = existing.reviewData;
        if (rd != null && rd['perQuestion'] is Map) {
          per = Map<String, dynamic>.from(rd['perQuestion'] as Map);
        } else {
          per = _evaluateLocally(content, _answers);
        }
      }

      setState(() {
        _testContent = content;
        _isLoading = false;
        _readOnly = ro;
        _perQuestionResults = per;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.test.testEn),
        elevation: 0,
      ),
      body: _readOnly ? _buildReadOnlyBody() : _buildBody(),
    );
  }

  Widget _buildReadOnlyBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading test...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Error loading test',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadTestContent,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_testContent == null) {
      return const Center(
        child: Text('No test content available'),
      );
    }

    // Get questions in the current language (default to English, with fallback)
    final lang = context.read<AppConfigService>().currentLanguageCode;
    List<Question> questions = _testContent!.questions[lang] ?? [];
    if (questions.isEmpty) {
      questions = _testContent!.questions['en'] ?? [];
    }
    if (questions.isEmpty && _testContent!.questions.isNotEmpty) {
      // final fallback to the first available language
      questions = _testContent!.questions.values.first;
    }

    // Filter out disclaimer question (id="disclaimer") - it's only shown in final review
    questions = questions.where((q) => q.id != 'disclaimer').toList();

    if (questions.isEmpty) {
      return const Center(
        child: Text('No questions available in this test'),
      );
    }

    // Ensure current index is valid
    if (_currentQuestionIndex >= questions.length) {
      _currentQuestionIndex = questions.length - 1;
    }

    final currentQuestion = questions[_currentQuestionIndex];
    final isFirstQuestion = _currentQuestionIndex == 0;
    final isLastQuestion = _currentQuestionIndex == questions.length - 1;

    return Column(
      children: [
        // Progress header
        Container(
          color: Theme.of(context).colorScheme.surface,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Question ${_currentQuestionIndex + 1} of ${questions.length}',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: LinearProgressIndicator(
                        value: (_currentQuestionIndex + 1) / questions.length,
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Current question
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _QuestionWidget(
                question: currentQuestion,
                questionNumber: _currentQuestionIndex + 1,
                answer: _answers[currentQuestion.id],
                onAnswerChanged: (answer) {
                  setState(() {
                    _answers[currentQuestion.id] = answer;
                  });
                },
                readOnly: _readOnly,
                isCorrect: _perQuestionResults?[currentQuestion.id] as bool?,
              ),
            ],
          ),
        ),
        // Navigation buttons
        Container(
          color: Theme.of(context).colorScheme.surface,
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Previous button
              if (!isFirstQuestion)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _currentQuestionIndex--;
                      });
                    },
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Previous'),
                  ),
                )
              else
                Expanded(
                  child: SizedBox.shrink(),
                ),
              if (!isFirstQuestion) const SizedBox(width: 12),
              // Next button
              if (!isLastQuestion)
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      setState(() {
                        _currentQuestionIndex++;
                      });
                    },
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('Next'),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading test...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Error loading test',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadTestContent,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_testContent == null) {
      return const Center(
        child: Text('No test content available'),
      );
    }

    // Get questions in the current language (default to English, with fallback)
    final lang = context.read<AppConfigService>().currentLanguageCode;
    List<Question> questions = _testContent!.questions[lang] ?? [];
    if (questions.isEmpty) {
      questions = _testContent!.questions['en'] ?? [];
    }
    if (questions.isEmpty && _testContent!.questions.isNotEmpty) {
      // final fallback to the first available language
      questions = _testContent!.questions.values.first;
    }

    // Filter out disclaimer question (id="disclaimer") - it's only shown in final review
    questions = questions.where((q) => q.id != 'disclaimer').toList();

    if (questions.isEmpty) {
      return const Center(
        child: Text('No questions available in this test'),
      );
    }

    // Ensure current index is valid
    if (_currentQuestionIndex >= questions.length) {
      _currentQuestionIndex = questions.length - 1;
    }

    final currentQuestion = questions[_currentQuestionIndex];
    final isFirstQuestion = _currentQuestionIndex == 0;
    final isLastQuestion = _currentQuestionIndex == questions.length - 1;

    return Column(
      children: [
        // Progress header
        Container(
          color: Theme.of(context).colorScheme.surface,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Question ${_currentQuestionIndex + 1} of ${questions.length}',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: LinearProgressIndicator(
                        value: (_currentQuestionIndex + 1) / questions.length,
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Image section (fixed at top if available) - max 30% of screen height
        if (currentQuestion.imageUrl != null && currentQuestion.imageUrl!.isNotEmpty)
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.3,
            ),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  currentQuestion.imageUrl!,
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
          ),
        // Current question (scrollable, without image)
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: [
              _QuestionWidget(
                question: currentQuestion,
                questionNumber: _currentQuestionIndex + 1,
                answer: _answers[currentQuestion.id],
                onAnswerChanged: (answer) {
                  setState(() {
                    _answers[currentQuestion.id] = answer;
                  });
                },
                readOnly: _readOnly,
                isCorrect: _perQuestionResults?[currentQuestion.id] as bool?,
              ),
            ],
          ),
        ),
        // Navigation and submit buttons
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            bottom: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    // Previous button
                    if (!isFirstQuestion)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              _currentQuestionIndex--;
                            });
                          },
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('Previous'),
                        ),
                      )
                    else
                      Expanded(
                        child: SizedBox.shrink(),
                      ),
                    if (!isFirstQuestion) const SizedBox(width: 12),
                    // Next or Submit button
                    if (!isLastQuestion)
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () {
                            setState(() {
                              _currentQuestionIndex++;
                            });
                          },
                          icon: const Icon(Icons.arrow_forward),
                          label: const Text('Next'),
                        ),
                      )
                    else
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _isSubmitting ? null : _submitTest,
                          icon: _isSubmitting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Icon(Icons.check),
                          label: const Text('Submit Test'),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _submitTest() async {
    // Show disclaimer if available
    if (_testContent?.disclaimer != null && _testContent!.disclaimer!.isNotEmpty) {
      final accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _DisclaimerDialog(
          disclaimer: _testContent!.disclaimer!,
        ),
      );

      if (accepted != true) {
        return;
      }
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final testService = Provider.of<TestService>(context, listen: false);
      await testService.submitTest(
        userId: widget.userId,
        testId: widget.test.id,
        answers: _answers,
      );

      if (!mounted) return;

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 12),
              Text('Test submitted successfully!'),
            ],
          ),
          backgroundColor: Colors.green,
        ),
      );

      // Go back to tests list
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error submitting test: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Map<String, dynamic> _evaluateLocally(
      TestContent content, Map<String, dynamic> answers) {
    List<Question> questions = content.questions.values.first;
    int bestMatches = -1;
    for (final list in content.questions.values) {
      final match = list.where((q) => answers.containsKey(q.id)).length;
      if (match > bestMatches) {
        bestMatches = match;
        questions = list;
      }
    }
    final Map<String, dynamic> per = {};
    for (final q in questions) {
      if (q.type == QuestionType.text) {
        per[q.id] = null;
      } else {
        per[q.id] = q.isAnswerCorrect(answers[q.id]);
      }
    }
    return per;
  }
}

/// Widget for displaying a single question with its input field
class _QuestionWidget extends StatefulWidget {
  final Question question;
  final int questionNumber;
  final dynamic answer;
  final ValueChanged<dynamic> onAnswerChanged;
  final bool readOnly;
  final bool? isCorrect;

  const _QuestionWidget({
    required this.question,
    required this.questionNumber,
    required this.answer,
    required this.onAnswerChanged,
    this.readOnly = false,
    this.isCorrect,
  });

  @override
  State<_QuestionWidget> createState() => _QuestionWidgetState();
}

class _QuestionWidgetState extends State<_QuestionWidget> {
  TextEditingController? _textController;

  @override
  void initState() {
    super.initState();
    if (widget.question.type == QuestionType.text) {
      _textController =
          TextEditingController(text: widget.answer as String? ?? '');
      _textController!.addListener(() {
        widget.onAnswerChanged(_textController!.text);
      });
    }
  }

  @override
  void didUpdateWidget(covariant _QuestionWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.question.type == QuestionType.text) {
      final newText = widget.answer as String? ?? '';
      if (_textController != null && _textController!.text != newText) {
        final selection = TextSelection.collapsed(offset: newText.length);
        _textController!.value =
            TextEditingValue(text: newText, selection: selection);
      }
    }
  }

  @override
  void dispose() {
    _textController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      '${widget.questionNumber}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.question.text,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
            // Display image if available
            // NOTE: Image is now rendered in _buildBody() as a fixed element above the scrollable content
            const SizedBox.shrink(),
            const SizedBox(height: 16),
            _buildAnswerInput(context),
            if (widget.readOnly)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    Icon(
                      widget.isCorrect == true
                          ? Icons.check_circle
                          : widget.isCorrect == false
                              ? Icons.cancel
                              : Icons.hourglass_top,
                      color: widget.isCorrect == true
                          ? Colors.green
                          : widget.isCorrect == false
                              ? Colors.red
                              : Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.isCorrect == true
                          ? 'Correct'
                          : widget.isCorrect == false
                              ? 'Incorrect'
                              : 'Awaiting review',
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnswerInput(BuildContext context) {
    switch (widget.question.type) {
      case QuestionType.multipleChoice:
        return _buildMultipleChoiceInput(context);
      case QuestionType.singleChoice:
        return _buildSingleChoiceInput(context);
      case QuestionType.trueFalse:
        return _buildTrueFalseInput(context);
      case QuestionType.text:
        return _buildTextInput(context);
      case QuestionType.matching:
        return _buildMatchingInput(context);
      default:
        return Text('Unsupported question type: ${widget.question.type}');
    }
  }


//MULTIPLE CHOICE VÁLASZTÓ GOMBOK
  Widget _buildMultipleChoiceInput(BuildContext context) {
    // Handle both List<String> and List<dynamic> from Firestore
    final answer = widget.answer;
    List<String> selectedAnswers = [];
    if (answer is List) {
      selectedAnswers = answer.map((e) => e.toString()).toList();
    }

    return Column(
      children: widget.question.options.map((option) {
        final isSelected = selectedAnswers.contains(option);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: isSelected ? Colors.transparent : Colors.transparent,
            border: Border.all(
              color: isSelected ? const Color.fromARGB(255, 105, 167, 225) : Colors.grey.shade300,
              width: isSelected ? 2 : 1.5,
            ),
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: const Color.fromARGB(255, 12, 67, 99).withValues(alpha: 0.2),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: CheckboxListTile(
            title: Text(
              option,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected ? const Color.fromARGB(255, 255, 255, 255) : const Color.fromARGB(221, 255, 255, 255),
                  ),
            ),
            value: isSelected,
            activeColor: const Color.fromARGB(255, 105, 167, 225),
            checkColor: Colors.white,
            onChanged: widget.readOnly
                ? null
                : (selected) {
                    final newAnswers = List<String>.from(selectedAnswers);
                    if (selected == true) {
                      newAnswers.add(option);
                    } else {
                      newAnswers.remove(option);
                    }
                    widget.onAnswerChanged(newAnswers);
                  },
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          ),
        );
      }).toList(),
    );
  }


//SINGLE CHOICE VÁLASZTÓ GOMBOK
  Widget _buildSingleChoiceInput(BuildContext context) {
    // Safely handle answer type conversion ITT vannak a színek a felelet választáshoz single choice kérdésnél REFERENCE
    final selectedValue = widget.answer is String ? widget.answer : null;
    return Column(
      children: widget.question.options.map((option) {
        final isSelected = selectedValue == option;
        
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: isSelected ? Colors.transparent: Colors.transparent,
            border: Border.all(
              color: isSelected ? const Color.fromARGB(255, 105, 167, 225) : const Color.fromARGB(255, 228, 226, 226),
              width: isSelected ? 2 : 1.5,
            ),
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: const Color.fromARGB(255, 12, 67, 99).withValues(alpha: 0.2),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: RadioListTile<String>(
            title: Text(
              option,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected ? const Color.fromARGB(255, 255, 255, 255) : const Color.fromARGB(221, 255, 255, 255),
                  ),
            ),
            value: option,
            groupValue: selectedValue as String?,
            activeColor: const Color.fromARGB(255, 255, 255, 255),
            onChanged: widget.readOnly ? null : widget.onAnswerChanged,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          ),
        );
      }).toList(),
    );
  }


//TRUE FALSE VÁLASZTÓ GOMBOK
  Widget _buildTrueFalseInput(BuildContext context) {
    // Safely handle boolean answer type conversion
    bool? selectedValue;
    if (widget.answer is bool) {
      selectedValue = widget.answer as bool?;
    }
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: selectedValue == true ? Colors.transparent : Colors.transparent,
            border: Border.all(
              color: selectedValue == true ? const Color.fromARGB(255, 105, 167, 225) : const Color.fromARGB(255, 228, 226, 226),
              width: selectedValue == true ? 2 : 1.5,
            ),
            borderRadius: BorderRadius.circular(10),
            boxShadow: selectedValue == true
                ? [
                    BoxShadow(
                      color: const Color.fromARGB(255, 12, 67, 99).withValues(alpha: 0.2),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: RadioListTile<bool>(
            title: Text(
              'True',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: selectedValue == true ? FontWeight.w600 : FontWeight.w400,
                    color: selectedValue == true ? const Color.fromARGB(255, 255, 255, 255) :  const Color.fromARGB(255, 255, 255, 255),
                  ),
            ),
            value: true,
            groupValue: selectedValue,
            activeColor: const Color.fromARGB(255, 255, 255, 255),
            onChanged: widget.readOnly ? null : widget.onAnswerChanged,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: selectedValue == false ? Colors.transparent : Colors.transparent,
            border: Border.all(
              color: selectedValue == false ? const Color.fromARGB(255, 105, 167, 225) : const Color.fromARGB(255, 228, 226, 226),
              width: selectedValue == false ? 2 : 1.5,
            ),
            borderRadius: BorderRadius.circular(10),
            boxShadow: selectedValue == false
                ? [
                    BoxShadow(
                      color: const Color.fromARGB(255, 12, 67, 99).withValues(alpha: 0.2),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: RadioListTile<bool>(
            title: Text(
              'False',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: selectedValue == false ? FontWeight.w600 : FontWeight.w400,
                    color: selectedValue == false ? const Color.fromARGB(255, 255, 255, 255) : const Color.fromARGB(221, 255, 255, 255),
                  ),
            ),
            value: false,
            groupValue: selectedValue,
            activeColor: const Color.fromARGB(255, 255, 255, 255),
            onChanged: widget.readOnly ? null : widget.onAnswerChanged,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          ),
        ),
      ],
    );
  }


//text-es kérdések ITT MÉG A LILA színt eltűntetni majd
  Widget _buildTextInput(BuildContext context) {
    return TextField(
      decoration: const InputDecoration(
        hintText: 'Enter your answer here...',
        border: OutlineInputBorder(),
      ),
      maxLines: 3,
      controller: _textController,
      readOnly: widget.readOnly,
    );
  }


//MATCHING VÁLASZTÓ GOMBOK
  Widget _buildMatchingInput(BuildContext context) {
    // For matching questions, we need pairs
    // Handle both Map<String, String> and Map<dynamic, dynamic> from Firestore
    Map<String, String> matches = {};
    if (widget.answer is Map) {
      matches = (widget.answer as Map).cast<String, String>();
    }
    final leftItems = widget.question.options; // left side
    final rightItems = widget.question.matchingPairs; // right side options

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select the correct option:',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
        ),
        const SizedBox(height: 8),
        ...leftItems.map((leftItem) {
          // Build available options per row: remove already-used values
          final used = matches.entries
              .where((e) => e.key != leftItem)
              .map((e) => e.value)
              .toSet();
          final current = matches[leftItem];
          final availableOptions = rightItems
              .where((opt) => opt == current || !used.contains(opt))
              .toList();

          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.transparent,
                border: Border.all(
                  color: const Color.fromARGB(255, 255, 255, 255),
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left label with arrow
                  Row(
                    children: [
                      Expanded(
                        flex: 1,
                        child: Text(
                          leftItem,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: const Color.fromARGB(255, 255, 255, 255),
                              ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Icon(
                        Icons.arrow_forward,
                        size: 20,
                        color: Color.fromARGB(255, 255, 255, 255),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Dropdown - full width below
                  DropdownButtonFormField<String?>(
                    decoration: InputDecoration(
                      isDense: false,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: current != null
                              ? const Color.fromARGB(255, 105, 167, 225)
                              : Colors.white.withValues(alpha: 0.5),
                          width: 2,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: current != null
                              ? const Color.fromARGB(255, 105, 167, 225)
                              : Colors.white.withValues(alpha: 0.5),
                          width: 2,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: Color.fromARGB(255, 105, 167, 225),
                          width: 2,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      filled: true,
                      fillColor: current != null
                          ? const Color.fromARGB(255, 105, 167, 225).withValues(alpha: 0.15)
                          : Colors.transparent,
                    ),
                    isExpanded: true,
                    hint: Text(
                      'Select',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                    initialValue: current,
                    items: [
                      // Clear option at the top
                      if (current != null)
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Row(
                            children: [
                              Icon(
                                Icons.close,
                                size: 16,
                                color: Colors.red.shade300,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Clear selection',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.red.shade300,
                                  fontWeight: FontWeight.w500,
                                  fontStyle: FontStyle.italic,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      // Regular options
                      ...availableOptions.map((pair) {
                        return DropdownMenuItem<String?>(
                          value: pair,
                          child: Text(
                            pair,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: const Color.fromARGB(255, 255, 255, 255),
                              fontWeight: FontWeight.w500,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }),
                    ],
                    dropdownColor: const Color.fromARGB(255, 40, 60, 90),
                    isDense: true,
                    menuMaxHeight: 300,
                    onChanged: widget.readOnly
                        ? null
                        : (value) {
                            final newMatches =
                                Map<String, String>.from(matches);
                            if (value == null) {
                              // Clear the selection
                              newMatches.remove(leftItem);
                            } else {
                              newMatches[leftItem] = value;
                            }
                            widget.onAnswerChanged(newMatches);
                          },
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}

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
          // Header
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
          // Content
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


