import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/test_service.dart';
import '../models/test_model.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

/// Main screen that displays available tests and allows users to take them.
/// 
/// This screen loads test metadata from Firestore (globalTests/) and displays
/// them in a modern, Material 3 design. When a test is tapped, it loads the
/// full test content from the JSON URL and presents it to the user.
class TestsScreen extends StatefulWidget {
  const TestsScreen({super.key});

  @override
  State<TestsScreen> createState() => _TestsScreenState();
}

class _TestsScreenState extends State<TestsScreen> {
  @override
  void initState() {
    super.initState();
    // Load tests when screen initializes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final testService = Provider.of<TestService>(context, listen: false);
      testService.loadAvailableTests();
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    
    if (user == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Tests'),
        ),
        body: const Center(
          child: Text('Please sign in to view tests'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Available Tests'),
        centerTitle: true,
      ),
      body: Consumer<TestService>(
        builder: (context, testService, child) {
          if (testService.isLoading) {
            return const Center(
              child: CircularProgressIndicator(),
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
                  Text(
                    testService.error!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => testService.loadAvailableTests(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          if (testService.availableTests.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.assignment_outlined,
                    size: 80,
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'No tests available',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Check back later for new tests',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
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
                    Text(
                      'Tap to start test',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
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
      
      setState(() {
        _testContent = content;
        _isLoading = false;
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
        centerTitle: true,
      ),
      body: _buildBody(),
      bottomNavigationBar: _testContent != null && !_isLoading
          ? _buildSubmitButton()
          : null,
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

    // Get questions in the current language (default to English)
    final questions = _testContent!.questions['en'] ?? [];
    
    if (questions.isEmpty) {
      return const Center(
        child: Text('No questions available in this test'),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: questions.length,
      itemBuilder: (context, index) {
        final question = questions[index];
        return _QuestionWidget(
          question: question,
          questionNumber: index + 1,
          answer: _answers[question.id],
          onAnswerChanged: (answer) {
            setState(() {
              _answers[question.id] = answer;
            });
          },
        );
      },
    );
  }

  Widget _buildSubmitButton() {
    // Check if all questions are answered
    final questions = _testContent!.questions['en'] ?? [];
    final allAnswered = questions.every((q) => _answers.containsKey(q.id));

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
            if (!allAnswered)
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
                        'Please answer all questions before submitting',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            FilledButton(
              onPressed: allAnswered && !_isSubmitting ? _submitTest : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Submit Test'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitTest() async {
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
        SnackBar(
          content: const Row(
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
}

/// Widget for displaying a single question with its input field
class _QuestionWidget extends StatelessWidget {
  final Question question;
  final int questionNumber;
  final dynamic answer;
  final ValueChanged<dynamic> onAnswerChanged;

  const _QuestionWidget({
    required this.question,
    required this.questionNumber,
    required this.answer,
    required this.onAnswerChanged,
  });

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
                      '$questionNumber',
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
                    question.text,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildAnswerInput(context),
          ],
        ),
      ),
    );
  }

  Widget _buildAnswerInput(BuildContext context) {
    switch (question.type) {
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
        return Text('Unsupported question type: ${question.type}');
    }
  }

  Widget _buildMultipleChoiceInput(BuildContext context) {
    final selectedAnswers = (answer as List<String>?) ?? [];
    
    return Column(
      children: question.options.map((option) {
        final isSelected = selectedAnswers.contains(option);
        
        return CheckboxListTile(
          title: Text(option),
          value: isSelected,
          onChanged: (selected) {
            final newAnswers = List<String>.from(selectedAnswers);
            if (selected == true) {
              newAnswers.add(option);
            } else {
              newAnswers.remove(option);
            }
            onAnswerChanged(newAnswers);
          },
          contentPadding: EdgeInsets.zero,
        );
      }).toList(),
    );
  }

  Widget _buildSingleChoiceInput(BuildContext context) {
    return Column(
      children: question.options.map((option) {
        return RadioListTile<String>(
          title: Text(option),
          value: option,
          groupValue: answer as String?,
          onChanged: onAnswerChanged,
          contentPadding: EdgeInsets.zero,
        );
      }).toList(),
    );
  }

  Widget _buildTrueFalseInput(BuildContext context) {
    return Column(
      children: [
        RadioListTile<bool>(
          title: const Text('True'),
          value: true,
          groupValue: answer as bool?,
          onChanged: onAnswerChanged,
          contentPadding: EdgeInsets.zero,
        ),
        RadioListTile<bool>(
          title: const Text('False'),
          value: false,
          groupValue: answer as bool?,
          onChanged: onAnswerChanged,
          contentPadding: EdgeInsets.zero,
        ),
      ],
    );
  }

  Widget _buildTextInput(BuildContext context) {
    return TextField(
      decoration: const InputDecoration(
        hintText: 'Enter your answer here...',
        border: OutlineInputBorder(),
      ),
      maxLines: 3,
      onChanged: onAnswerChanged,
      controller: TextEditingController(text: answer as String? ?? ''),
    );
  }

  Widget _buildMatchingInput(BuildContext context) {
    // For matching questions, we need pairs
    // Simplified version - could be enhanced with drag & drop
    final matches = (answer as Map<String, String>?) ?? {};
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Match the following:',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        ...question.options.asMap().entries.map((entry) {
          final index = entry.key;
          final leftItem = entry.value;
          
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(leftItem),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    hint: const Text('Select'),
                    value: matches[leftItem],
                    items: question.matchingPairs.map((pair) {
                      return DropdownMenuItem(
                        value: pair,
                        child: Text(pair),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        final newMatches = Map<String, String>.from(matches);
                        newMatches[leftItem] = value;
                        onAnswerChanged(newMatches);
                      }
                    },
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }
}