import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/test_model.dart';
import '../services/test_service.dart';
import '../services/app_config_service.dart';
import '../services/gtc_service.dart';
import '../services/profile_service.dart';
import '../services/stats_service.dart';
import '../auth/auth_service.dart';
import 'test_review_screen.dart';

/// Main tests listing screen
class TestsScreen extends StatefulWidget {
  const TestsScreen({super.key});

  @override
  State<TestsScreen> createState() => _TestsScreenState();
}

class _TestsScreenState extends State<TestsScreen> {
  final Map<String, Map<String, bool>> _gtcCheckboxStatesBySchool = {};
  final Map<String, bool> _gtcExpandedBySchool = {};
  String? _lastActiveSchoolId;
  String? _lastAcceptanceUid;
  String? _lastSubmissionsUid;
  List<TestSubmission> _userSubmissions = [];
  Set<String> _loadedSignedGtcSchools = {};

  static const Map<String, Map<String, String>> _gtcTexts = {
    'GTC_Title': {'en': 'General Terms & Conditions', 'de': 'Allgemeine Geschaeftsbedingungen'},
    'GTC_Error_Message': {'en': 'Please accept every section and sign', 'de': 'Bitte akzeptieren Sie alle Abschnitte und unterschreiben'},
    'Accepted_On': {'en': 'Accepted on', 'de': 'Akzeptiert am'},
    'View_Terms': {'en': 'View Terms', 'de': 'Bedingungen anzeigen'},
    'Collapse': {'en': 'Collapse', 'de': 'Einklappen'},
    'Accept_And_Sign': {'en': 'Accept & Sign', 'de': 'Akzeptieren & unterschreiben'},
    'Signed_GTC': {'en': 'Signed Terms & Conditions', 'de': 'Unterzeichnete Bedingungen'},
    'School': {'en': 'School', 'de': 'Schule'},
    'I_Accept': {'en': 'I accept', 'de': 'Ich akzeptiere'},
    'GTC_Not_Available': {'en': 'Terms not available', 'de': 'Bedingungen nicht verfuegbar'},
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<TestService>(context, listen: false).loadAvailableTests();
    });
  }

  void _ensureSignedGtcsLoaded(List<String> schoolIds, GTCService gtcService) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final schoolId in schoolIds) {
        if (!_loadedSignedGtcSchools.contains(schoolId) && gtcService.getGTCForSchool(schoolId) == null) {
          _loadedSignedGtcSchools.add(schoolId);
          gtcService.loadGTC(schoolId);
        }
      }
    });
  }

  String _t(String key, String lang) => _gtcTexts[key]?[lang] ?? key;

  void _ensureUserAcceptancesLoaded(String uid) {
    if (_lastAcceptanceUid == uid) return;
    _lastAcceptanceUid = uid;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<GTCService>().loadUserAcceptances(uid);
    });
  }

  void _ensureCurrentSchoolGtcLoaded(String uid, String schoolId) {
    if (_lastActiveSchoolId == schoolId) return;
    _lastActiveSchoolId = schoolId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final gtcService = context.read<GTCService>();
      gtcService.loadGTC(schoolId);
      gtcService.checkGTCAcceptance(uid, schoolId);
    });
  }

  void _ensureUserSubmissionsLoaded(String uid) {
    if (_lastSubmissionsUid == uid) return;
    _lastSubmissionsUid = uid;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<TestService>().loadUserSubmissions(uid).then((submissions) {
        if (mounted) {
          setState(() => _userSubmissions = submissions);
        }
      }).catchError((e) {
        debugPrint('[TestsScreen] Error loading submissions: $e');
      });
    });
  }

  void _showSnack(String message, {Color? backgroundColor}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final testService = context.watch<TestService>();

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
            Icon(Icons.error_outline, size: 64, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 16),
            Text('Error loading tests', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(testService.error!, textAlign: TextAlign.center),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => Provider.of<TestService>(context, listen: false).loadAvailableTests(),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final auth = context.read<AuthService>();
    final user = auth.currentUser;
    if (user == null) {
      return const Center(child: Text('Not authenticated'));
    }

    final profileService = context.watch<ProfileService>();
    final profile = profileService.userProfile;
    final gtcService = context.watch<GTCService>();
    final lang = context.watch<AppConfigService>().currentLanguageCode;
    final statsService = context.watch<StatsService>();

    final currentSchoolId = profile?.mainSchoolId;
    final isStudent = (profile?.license ?? '').toLowerCase() == 'student';

    _ensureUserAcceptancesLoaded(user.uid);
    _ensureUserSubmissionsLoaded(user.uid);
    if (isStudent && currentSchoolId != null) {
      _ensureCurrentSchoolGtcLoaded(user.uid, currentSchoolId);
    }

    // Get dashboard stats as JSON for trigger evaluation
    final statsJson = statsService.stats.toJson();

    // Categorize tests by state
    final submissionsByTestId = <String, TestSubmission>{};
    for (final sub in _userSubmissions) {
      submissionsByTestId[sub.testId] = sub;
    }

    final unlockedTests = <TestMetadata>[];
    final lockedTests = <TestMetadata>[];
    final passedTests = <TestMetadata>[];
    final failedTests = <TestMetadata>[];

    for (final test in testService.availableTests) {
      final submission = submissionsByTestId[test.id];
      final triggersMet = test.areTriggersMet(statsJson);

      if (submission != null && submission.passed == true) {
        passedTests.add(test);
      } else if (submission != null && submission.passed == false) {
        failedTests.add(test);
      } else if (!triggersMet) {
        lockedTests.add(test);
      } else {
        unlockedTests.add(test);
      }
    }

    // Build GTC widget
    final currentGtcWidget = <Widget>[];
    final isCurrentSchoolGtcAccepted = isStudent && currentSchoolId != null && gtcService.isGTCAcceptedForSchool(currentSchoolId);

    if (isStudent && currentSchoolId != null && !isCurrentSchoolGtcAccepted) {
      currentGtcWidget.add(
        _buildGtcCardForSchool(
          lang: lang, uid: user.uid, schoolId: currentSchoolId,
          profileService: profileService, gtcService: gtcService, allowSigning: true,
        ),
      );
    }

    // Build signed GTC section
    final acceptedSchoolIds = gtcService.acceptedSchoolIds;
    final signedSchoolIds = acceptedSchoolIds.toList();
    _ensureSignedGtcsLoaded(signedSchoolIds, gtcService);

    final signedGtcWidgets = <Widget>[];
    if (signedSchoolIds.isNotEmpty) {
      signedGtcWidgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(_t('Signed_GTC', lang), style: Theme.of(context).textTheme.titleMedium),
        ),
      );
      for (final schoolId in signedSchoolIds) {
        signedGtcWidgets.add(
          _buildGtcCardForSchool(
            lang: lang, uid: user.uid, schoolId: schoolId,
            profileService: profileService, gtcService: gtcService, allowSigning: false,
          ),
        );
      }
    }

    return RefreshIndicator(
      onRefresh: () async {
        _lastSubmissionsUid = null; // Force reload submissions
        _ensureUserSubmissionsLoaded(user.uid);
        await testService.loadAvailableTests();
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Current GTC section
          ...currentGtcWidget,

          // Available Tests (triggers met, not yet attempted)
          if (unlockedTests.isNotEmpty) ...[
            if (currentGtcWidget.isNotEmpty) const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                lang == 'de' ? 'Verfügbare Tests' : 'Available Tests',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ...unlockedTests.map((test) => _TestCard(
              test: test,
              lang: lang,
              submission: submissionsByTestId[test.id],
              isLocked: false,
              onTap: () => _openTest(context, test, user.uid),
            )),
          ],

          // Failed Tests (with retry info)
          if (failedTests.isNotEmpty) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                lang == 'de' ? 'Nicht bestanden' : 'Failed Tests',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ...failedTests.map((test) {
              final sub = submissionsByTestId[test.id]!;
              return _TestCard(
                test: test,
                lang: lang,
                submission: sub,
                isLocked: false,
                onTap: sub.canRetryNow
                    ? () => _openTest(context, test, user.uid)
                    : null,
              );
            }),
          ],

          // Passed Tests
          if (passedTests.isNotEmpty) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                lang == 'de' ? 'Bestandene Tests' : 'Passed Tests',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ...passedTests.map((test) => _TestCard(
              test: test,
              lang: lang,
              submission: submissionsByTestId[test.id],
              isLocked: false,
              onTap: () => _openTest(context, test, user.uid),
            )),
          ],

          // Locked Tests (triggers not met)
          if (lockedTests.isNotEmpty) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                lang == 'de' ? 'Gesperrte Tests' : 'Locked Tests',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ...lockedTests.map((test) => _TestCard(
              test: test,
              lang: lang,
              submission: null,
              isLocked: true,
              statsJson: statsJson,
            )),
          ],

          // No tests at all
          if (unlockedTests.isEmpty && failedTests.isEmpty && passedTests.isEmpty && lockedTests.isEmpty)
            _buildEmptyTestsCard(),

          // Signed Terms & Conditions section
          ...signedGtcWidgets,
        ],
      ),
    );
  }

  void _openTest(BuildContext context, TestMetadata test, String userId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TestTakingScreen(test: test, userId: userId),
      ),
    ).then((_) {
      // Refresh submissions when returning from test
      _lastSubmissionsUid = null;
      _ensureUserSubmissionsLoaded(userId);
    });
  }

  Widget _buildEmptyTestsCard() {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'No tests available yet',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }

  String _schoolNameFor(String schoolId, ProfileService profileService, Map<String, dynamic>? gtcData) {
    String? fromProfile;
    for (final school in profileService.schools) {
      if (school['id'] == schoolId) {
        fromProfile = school['name'];
        break;
      }
    }
    if (fromProfile != null && fromProfile.isNotEmpty) return fromProfile;
    final fromGtc = gtcData?['school_name'] as String?;
    return fromGtc?.isNotEmpty == true ? fromGtc! : 'Unknown School';
  }

  Widget _buildGtcCardForSchool({
    required String lang,
    required String uid,
    required String schoolId,
    required ProfileService profileService,
    required GTCService gtcService,
    required bool allowSigning,
  }) {
    final gtcData = gtcService.getGTCForSchool(schoolId);
    final acceptanceRecord = gtcService.getAcceptanceForSchool(schoolId);
    final isAccepted = gtcService.isGTCAcceptedForSchool(schoolId);
    final isLoading = gtcService.isLoadingForSchool(schoolId);
    final isExpanded = _gtcExpandedBySchool[schoolId] ?? false;
    final schoolName = _schoolNameFor(schoolId, profileService, gtcData);

    if (gtcData == null && isLoading) {
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary, strokeWidth: 2)),
              const SizedBox(width: 12),
              Expanded(child: Text('${_t('GTC_Title', lang)} - $schoolName', style: Theme.of(context).textTheme.titleMedium)),
            ],
          ),
        ),
      );
    }

    if (gtcData == null) {
      if (acceptanceRecord != null) {
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_t('GTC_Title', lang), style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text('${_t('School', lang)}: $schoolName', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                Text(_t('GTC_Not_Available', lang), style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      gtcService.loadGTC(schoolId);
                      gtcService.checkGTCAcceptance(uid, schoolId);
                      setState(() => _gtcExpandedBySchool[schoolId] = true);
                    },
                    child: Text(_t('View_Terms', lang)),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      return const SizedBox.shrink();
    }

    final gtcJsonData = gtcData['gtc_data'] as Map<String, dynamic>?;
    if (gtcJsonData == null) return const SizedBox.shrink();

    Map<String, dynamic>? langSections = gtcJsonData[lang] as Map<String, dynamic>?;
    langSections ??= gtcJsonData['en'] as Map<String, dynamic>?;
    if (langSections == null) {
      for (final value in gtcJsonData.values) {
        if (value is Map<String, dynamic>) { langSections = value; break; }
      }
    }
    if (langSections == null) return const SizedBox.shrink();

    final gtcSections = (langSections['sections'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (gtcSections.isEmpty) return const SizedBox.shrink();

    final sectionStates = _gtcCheckboxStatesBySchool.putIfAbsent(schoolId, () => {});

    if (isAccepted && !isExpanded && acceptanceRecord?['gtc_accepted_at'] != null) {
      final acceptanceTime = _formatGTCAcceptanceTime(acceptanceRecord);
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_t('GTC_Title', lang), style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text('${_t('School', lang)}: $schoolName', style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 4),
                    Text('${_t('Accepted_On', lang)} $acceptanceTime',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.expand_more),
                onPressed: () {
                  setState(() => _gtcExpandedBySchool[schoolId] = true);
                  gtcService.loadGTC(schoolId);
                  gtcService.checkGTCAcceptance(uid, schoolId);
                },
                tooltip: _t('View_Terms', lang),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_t('GTC_Title', lang), style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 4),
                          Text('${_t('School', lang)}: $schoolName', style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                    if (isAccepted)
                      IconButton(
                        icon: const Icon(Icons.expand_less),
                        onPressed: () => setState(() => _gtcExpandedBySchool[schoolId] = false),
                        tooltip: _t('Collapse', lang),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (!isAccepted && allowSigning)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(_t('GTC_Error_Message', lang),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                if (!isAccepted && allowSigning) const SizedBox(height: 12),
                ...gtcSections.asMap().entries.map((entry) {
                  final index = entry.key;
                  final section = entry.value;
                  final sectionId = 'section_$index';
                  final title = section['title'] as String? ?? '';
                  final text = section['text'] as String? ?? '';
                  final list = (section['list'] as List?)?.cast<String>() ?? [];
                  final afterList = section['afterList'] as String? ?? '';

                  sectionStates.putIfAbsent(sectionId, () => false);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(text, style: Theme.of(context).textTheme.bodySmall),
                              if (list.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                ...list.map((item) => Padding(
                                  padding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('• ', style: Theme.of(context).textTheme.bodySmall),
                                      Expanded(child: Text(item, style: Theme.of(context).textTheme.bodySmall)),
                                    ],
                                  ),
                                )),
                              ],
                              if (afterList.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(afterList, style: Theme.of(context).textTheme.bodySmall),
                              ],
                            ],
                          ),
                        ),
                        if (allowSigning) ...[
                          const SizedBox(height: 8),
                          CheckboxListTile(
                            value: isAccepted ? true : (sectionStates[sectionId] ?? false),
                            onChanged: isAccepted ? null : (value) { setState(() { sectionStates[sectionId] = value ?? false; }); },
                            title: Text(_t('I_Accept', lang),
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: isAccepted ? Theme.of(context).colorScheme.onSurfaceVariant : null)),
                            contentPadding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          if (!isAccepted && allowSigning)
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _allRequiredGTCAccepted(schoolId, gtcSections) ? () => _acceptGTC(gtcService, uid, schoolId, lang) : null,
                  style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary),
                  child: Text(_t('Accept_And_Sign', lang)),
                ),
              ),
            )
          else if (isAccepted && isExpanded)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('${_t('Accepted_On', lang)} ${_formatGTCAcceptanceTime(acceptanceRecord)}',
                    style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  bool _allRequiredGTCAccepted(String schoolId, List<Map<String, dynamic>> gtcSections) {
    final sectionStates = _gtcCheckboxStatesBySchool[schoolId] ?? {};
    for (final entry in gtcSections.asMap().entries) {
      final sectionId = 'section_${entry.key}';
      if (!(sectionStates[sectionId] ?? false)) return false;
    }
    return true;
  }

  Future<void> _acceptGTC(GTCService gtcService, String uid, String schoolId, String lang) async {
    final success = await gtcService.acceptGTC(uid, schoolId);
    if (success) {
      _showSnack('Terms and conditions accepted!', backgroundColor: Colors.green);
      setState(() { _gtcExpandedBySchool[schoolId] = false; });
    } else {
      _showSnack('Failed to accept terms and conditions. Please try again.');
    }
  }

  String _formatGTCAcceptanceTime(Map<String, dynamic>? acceptance) {
    if (acceptance == null) return 'unknown date';
    final timestamp = acceptance['gtc_accepted_at'];
    if (timestamp == null) return 'unknown date';
    try {
      if (timestamp is Timestamp) {
        return DateFormat('yyyy-MM-dd HH:mm').format(timestamp.toDate());
      } else if (timestamp is DateTime) {
        return DateFormat('yyyy-MM-dd HH:mm').format(timestamp);
      }
    } catch (e) {
      debugPrint('Error formatting GTC acceptance time: $e');
    }
    return 'unknown date';
  }
}

// ---------------------------------------------------------------------------
// Test Card widget
// ---------------------------------------------------------------------------

class _TestCard extends StatelessWidget {
  final TestMetadata test;
  final String lang;
  final TestSubmission? submission;
  final bool isLocked;
  final VoidCallback? onTap;
  final Map<String, dynamic>? statsJson;

  const _TestCard({
    required this.test,
    required this.lang,
    this.submission,
    this.isLocked = false,
    this.onTap,
    this.statsJson,
  });

  @override
  Widget build(BuildContext context) {
    final isPassed = submission?.passed == true;
    final isFailed = submission?.passed == false;
    final canRetry = submission?.canRetryNow ?? true;
    final daysLeft = submission?.daysUntilRetry ?? 0;
    final score = submission?.scorePercent;
    final attempts = submission?.attempts ?? [];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: isLocked ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isLocked
                      ? Colors.grey.shade700
                      : isPassed
                          ? Colors.green.withValues(alpha: 0.2)
                          : isFailed
                              ? Colors.red.withValues(alpha: 0.2)
                              : Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isLocked
                      ? Icons.lock
                      : isPassed
                          ? Icons.check_circle
                          : isFailed
                              ? Icons.cancel
                              : Icons.assignment,
                  color: isLocked
                      ? Colors.grey.shade400
                      : isPassed
                          ? Colors.green
                          : isFailed
                              ? Colors.red
                              : Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Test name (localized)
                    Text(
                      test.getName(lang),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isLocked ? Colors.grey : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Status / info line
                    if (isLocked) ...[
                      Text(
                        lang == 'de' ? 'Voraussetzungen nicht erfüllt' : 'Requirements not met',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                      ),
                      const SizedBox(height: 2),
                      ...test.triggers.map((trigger) {
                        final met = statsJson != null ? trigger.evaluate(statsJson!) : false;
                        return Row(
                          children: [
                            Icon(met ? Icons.check : Icons.close, size: 14,
                              color: met ? Colors.green : Colors.red.shade300),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                trigger.getDescription(lang),
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: met ? Colors.green : Colors.red.shade300,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        );
                      }),
                    ] else if (isPassed) ...[
                      Text(
                        '${lang == 'de' ? 'Bestanden' : 'PASSED'} - ${score?.toStringAsFixed(0)}%',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.green, fontWeight: FontWeight.w600),
                      ),
                      if (attempts.isNotEmpty)
                        Text(
                          '${lang == 'de' ? 'Versuche' : 'Attempts'}: ${attempts.length}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey, fontSize: 11),
                        ),
                    ] else if (isFailed) ...[
                      Text(
                        '${lang == 'de' ? 'Nicht bestanden' : 'FAILED'} - ${score?.toStringAsFixed(0)}%',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.red),
                      ),
                      if (!canRetry)
                        Text(
                          lang == 'de'
                              ? 'Wiederholung möglich in $daysLeft Tagen'
                              : 'Retry available in $daysLeft days',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.orange, fontSize: 11),
                        )
                      else
                        Text(
                          lang == 'de' ? 'Tippen zum Wiederholen' : 'Tap to retry',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary),
                        ),
                      if (attempts.isNotEmpty)
                        Text(
                          '${lang == 'de' ? 'Versuche' : 'Attempts'}: ${attempts.length}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey, fontSize: 11),
                        ),
                    ] else ...[
                      Text(
                        lang == 'de' ? 'Tippen um den Test zu starten' : 'Tap to start test',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
              if (!isLocked)
                Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: isLocked ? Colors.grey : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Test Taking Screen
// ---------------------------------------------------------------------------

class TestTakingScreen extends StatefulWidget {
  final TestMetadata test;
  final String userId;

  const TestTakingScreen({super.key, required this.test, required this.userId});

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
  bool _showCorrectAnswers = false;
  Map<String, dynamic>? _perQuestionResults;
  int _currentQuestionIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadTestContent();
  }

  Future<void> _loadTestContent() async {
    setState(() { _isLoading = true; _error = null; });

    try {
      final testService = Provider.of<TestService>(context, listen: false);
      final content = await testService.loadTestContent(widget.test);

      // Check prior submission
      final existing = await testService.getSubmission(widget.userId, widget.test.id);
      bool ro = false;
      Map<String, dynamic>? per;
      bool showCorrectAnswers = false;

      if (existing != null) {
        // If passed, show read-only with results + correct answers (unlimited)
        if (existing.passed == true) {
          _answers.clear();
          _answers.addAll(existing.answers);
          ro = true;
          per = _evaluateLocally(content, _answers);
          showCorrectAnswers = true;
        }
        // If failed and hasn't reviewed yet, show read-only with results (one-time view)
        else if (existing.passed == false && !existing.reviewedOnce) {
          _answers.clear();
          _answers.addAll(existing.answers);
          ro = true;
          per = _evaluateLocally(content, _answers);
          showCorrectAnswers = true;
          // Mark as reviewed so next time they can't see answers
          testService.markReviewedOnce(userId: widget.userId, testId: widget.test.id);
        }
        // If failed and already reviewed once, but can't retry yet: show locked message
        else if (existing.passed == false && existing.reviewedOnce && !existing.canRetryNow) {
          _answers.clear();
          _answers.addAll(existing.answers);
          ro = true;
          per = _evaluateLocally(content, _answers);
          showCorrectAnswers = false; // No correct answers on repeat views
        }
        // If failed and can retry, allow new attempt (fresh answers)
        // If status is 'final', redirect to review screen
        else if (existing.status == 'final') {
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => TestReviewScreen(
                  test: _buildLegacyTestMeta(),
                  userId: widget.userId,
                  submission: existing,
                  testContent: content,
                ),
              ),
            );
          }
          return;
        }
      }

      setState(() {
        _testContent = content;
        _isLoading = false;
        _readOnly = ro;
        _perQuestionResults = per;
        _showCorrectAnswers = showCorrectAnswers;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  /// Build a legacy-compatible TestMetadata for the review screen
  /// TODO: Update TestReviewScreen to use new TestMetadata directly
  _buildLegacyTestMeta() => widget.test;

  @override
  Widget build(BuildContext context) {
    final lang = context.read<AppConfigService>().currentLanguageCode;
    return Scaffold(
      appBar: AppBar(title: Text(widget.test.getName(lang)), elevation: 0),
      body: _readOnly ? _buildReadOnlyBody() : _buildBody(),
    );
  }

  Widget _buildReadOnlyBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [CircularProgressIndicator(), SizedBox(height: 16), Text('Loading test...')],
        ),
      );
    }
    if (_error != null) return _buildErrorWidget();
    if (_testContent == null) return const Center(child: Text('No test content available'));

    final lang = context.read<AppConfigService>().currentLanguageCode;
    List<Question> questions = _getQuestions(lang);
    if (questions.isEmpty) return const Center(child: Text('No questions available in this test'));
    if (_currentQuestionIndex >= questions.length) _currentQuestionIndex = questions.length - 1;

    final currentQuestion = questions[_currentQuestionIndex];
    final isFirstQuestion = _currentQuestionIndex == 0;
    final isLastQuestion = _currentQuestionIndex == questions.length - 1;

    return Column(
      children: [
        _buildProgressHeader(questions.length),
        // Image section - local asset (also in read-only mode)
        if (currentQuestion.imageUrl != null && currentQuestion.imageUrl!.isNotEmpty)
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.3),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: currentQuestion.isLocalImage
                    ? Image.asset(
                        currentQuestion.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => _imageErrorPlaceholder(),
                      )
                    : Image.network(
                        currentQuestion.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => _imageErrorPlaceholder(),
                      ),
              ),
            ),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _QuestionWidget(
                question: currentQuestion,
                questionNumber: _currentQuestionIndex + 1,
                answer: _answers[currentQuestion.id],
                onAnswerChanged: (answer) { setState(() { _answers[currentQuestion.id] = answer; }); },
                readOnly: _readOnly,
                isCorrect: _perQuestionResults?[currentQuestion.id] as bool?,
                showCorrectAnswer: _showCorrectAnswers,
              ),
            ],
          ),
        ),
        _buildNavigationBar(isFirstQuestion, isLastQuestion, readOnly: true),
      ],
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [CircularProgressIndicator(), SizedBox(height: 16), Text('Loading test...')],
        ),
      );
    }
    if (_error != null) return _buildErrorWidget();
    if (_testContent == null) return const Center(child: Text('No test content available'));

    final lang = context.read<AppConfigService>().currentLanguageCode;
    List<Question> questions = _getQuestions(lang);
    if (questions.isEmpty) return const Center(child: Text('No questions available in this test'));
    if (_currentQuestionIndex >= questions.length) _currentQuestionIndex = questions.length - 1;

    final currentQuestion = questions[_currentQuestionIndex];
    final isFirstQuestion = _currentQuestionIndex == 0;
    final isLastQuestion = _currentQuestionIndex == questions.length - 1;

    return Column(
      children: [
        _buildProgressHeader(questions.length),
        // Image section - local asset
        if (currentQuestion.imageUrl != null && currentQuestion.imageUrl!.isNotEmpty)
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.3),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: currentQuestion.isLocalImage
                    ? Image.asset(
                        currentQuestion.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => _imageErrorPlaceholder(),
                      )
                    : Image.network(
                        currentQuestion.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => _imageErrorPlaceholder(),
                      ),
              ),
            ),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: [
              _QuestionWidget(
                question: currentQuestion,
                questionNumber: _currentQuestionIndex + 1,
                answer: _answers[currentQuestion.id],
                onAnswerChanged: (answer) { setState(() { _answers[currentQuestion.id] = answer; }); },
                readOnly: _readOnly,
                isCorrect: _perQuestionResults?[currentQuestion.id] as bool?,
                showCorrectAnswer: _showCorrectAnswers,
              ),
            ],
          ),
        ),
        _buildNavigationBar(isFirstQuestion, isLastQuestion, readOnly: false),
      ],
    );
  }

  Widget _imageErrorPlaceholder() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
      child: const Text('Failed to load image'),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 16),
          Text('Error loading test', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(_error!, textAlign: TextAlign.center),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(onPressed: _loadTestContent, icon: const Icon(Icons.refresh), label: const Text('Retry')),
        ],
      ),
    );
  }

  List<Question> _getQuestions(String lang) {
    if (_testContent == null) return [];
    List<Question> questions = _testContent!.questions[lang] ?? [];
    if (questions.isEmpty) questions = _testContent!.questions['en'] ?? [];
    if (questions.isEmpty && _testContent!.questions.isNotEmpty) {
      questions = _testContent!.questions.values.first;
    }
    return questions.where((q) => q.id != 'disclaimer').toList();
  }

  Widget _buildProgressHeader(int totalQuestions) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Question ${_currentQuestionIndex + 1} of $totalQuestions',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 16),
              child: LinearProgressIndicator(
                value: (_currentQuestionIndex + 1) / totalQuestions,
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationBar(bool isFirst, bool isLast, {required bool readOnly}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8, offset: const Offset(0, -2))],
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            if (!isFirst)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => setState(() { _currentQuestionIndex--; }),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Previous'),
                ),
              )
            else
              const Expanded(child: SizedBox.shrink()),
            if (!isFirst) const SizedBox(width: 12),
            if (!isLast)
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => setState(() { _currentQuestionIndex++; }),
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Next'),
                ),
              )
            else if (!readOnly)
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isSubmitting ? null : _submitTest,
                  icon: _isSubmitting
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                      : const Icon(Icons.check),
                  label: const Text('Submit Test'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitTest() async {
    // Show disclaimer if available
    if (_testContent?.disclaimer != null && _testContent!.disclaimer!.isNotEmpty) {
      final accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _DisclaimerDialog(disclaimer: _testContent!.disclaimer!),
      );
      if (accepted != true) return;
    }

    setState(() { _isSubmitting = true; });

    try {
      final testService = Provider.of<TestService>(context, listen: false);
      final result = await testService.submitAndGradeTest(
        userId: widget.userId,
        test: widget.test,
        content: _testContent!,
        answers: _answers,
      );

      if (!mounted) return;

      // Show result dialog
      final passed = result['passed'] as bool;
      final scorePercent = result['scorePercent'] as double;
      final correct = result['correct'] as int;
      final total = result['total'] as int;
      final retryAt = result['retryAvailableAt'] as DateTime?;
      final attempts = result['attempts'] as List;
      final lang = context.read<AppConfigService>().currentLanguageCode;

      // Also save result to school collection for scalability
      final profileService = context.read<ProfileService>();
      final schoolId = profileService.userProfile?.mainSchoolId;
      if (schoolId != null && schoolId.isNotEmpty) {
        testService.saveSchoolTestResult(
          schoolId: schoolId,
          userId: widget.userId,
          testId: widget.test.id,
          passed: passed,
          scorePercent: scorePercent,
          attemptCount: attempts.length,
          submittedAt: DateTime.now(),
        );
      }

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => _TestResultDialog(
          passed: passed,
          scorePercent: scorePercent,
          correct: correct,
          total: total,
          passThreshold: widget.test.passThreshold,
          retryAvailableAt: retryAt,
          retryDelayDays: widget.test.retryDelayDays,
          lang: lang,
        ),
      );

      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error submitting test: $e'), backgroundColor: Theme.of(context).colorScheme.error),
      );
    } finally {
      if (mounted) setState(() { _isSubmitting = false; });
    }
  }

  Map<String, dynamic> _evaluateLocally(TestContent content, Map<String, dynamic> answers) {
    List<Question> questions = content.questions.values.first;
    int bestMatches = -1;
    for (final list in content.questions.values) {
      final match = list.where((q) => answers.containsKey(q.id)).length;
      if (match > bestMatches) { bestMatches = match; questions = list; }
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

// ---------------------------------------------------------------------------
// Test Result Dialog
// ---------------------------------------------------------------------------

class _TestResultDialog extends StatelessWidget {
  final bool passed;
  final double scorePercent;
  final int correct;
  final int total;
  final int passThreshold;
  final DateTime? retryAvailableAt;
  final int retryDelayDays;
  final String lang;

  const _TestResultDialog({
    required this.passed,
    required this.scorePercent,
    required this.correct,
    required this.total,
    required this.passThreshold,
    this.retryAvailableAt,
    required this.retryDelayDays,
    required this.lang,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            passed ? Icons.check_circle : Icons.cancel,
            size: 80,
            color: passed ? Colors.green : Colors.red,
          ),
          const SizedBox(height: 16),
          Text(
            passed
                ? (lang == 'de' ? 'Bestanden!' : 'PASSED!')
                : (lang == 'de' ? 'Nicht bestanden' : 'FAILED'),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: passed ? Colors.green : Colors.red,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '${scorePercent.toStringAsFixed(0)}%',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            '$correct / $total ${lang == 'de' ? 'richtig' : 'correct'}',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 4),
          Text(
            '${lang == 'de' ? 'Bestehensgrenze' : 'Pass threshold'}: $passThreshold%',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
          ),
          if (!passed && retryAvailableAt != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.schedule, color: Colors.orange, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      lang == 'de'
                          ? 'Sie können den Test in $retryDelayDays Tagen wiederholen'
                          : 'You can retry this test in $retryDelayDays days',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.orange.shade800),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Question Widget
// ---------------------------------------------------------------------------

class _QuestionWidget extends StatefulWidget {
  final Question question;
  final int questionNumber;
  final dynamic answer;
  final ValueChanged<dynamic> onAnswerChanged;
  final bool readOnly;
  final bool? isCorrect;
  final bool showCorrectAnswer;

  const _QuestionWidget({
    required this.question,
    required this.questionNumber,
    required this.answer,
    required this.onAnswerChanged,
    this.readOnly = false,
    this.isCorrect,
    this.showCorrectAnswer = false,
  });

  @override
  State<_QuestionWidget> createState() => _QuestionWidgetState();
}

class _QuestionWidgetState extends State<_QuestionWidget> {
  TextEditingController? _textController;
  List<String>? _shuffledMatchingPairs;

  @override
  void initState() {
    super.initState();
    if (widget.question.type == QuestionType.text) {
      _textController = TextEditingController(text: widget.answer as String? ?? '');
      _textController!.addListener(() { widget.onAnswerChanged(_textController!.text); });
    }
    // Shuffle matching pairs once so order stays stable during the question
    // In read-only mode, keep original order for clarity
    if (widget.question.type == QuestionType.matching) {
      if (widget.readOnly) {
        _shuffledMatchingPairs = List<String>.from(widget.question.matchingPairs);
      } else {
        _shuffledMatchingPairs = List<String>.from(widget.question.matchingPairs)..shuffle();
      }
    }
  }

  @override
  void didUpdateWidget(covariant _QuestionWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.question.type == QuestionType.text) {
      final newText = widget.answer as String? ?? '';
      if (_textController != null && _textController!.text != newText) {
        _textController!.value = TextEditingValue(text: newText, selection: TextSelection.collapsed(offset: newText.length));
      }
    }
    // Re-shuffle matching pairs when navigating to a different matching question
    if (widget.question.id != oldWidget.question.id) {
      if (widget.question.type == QuestionType.matching && !widget.readOnly) {
        _shuffledMatchingPairs = List<String>.from(widget.question.matchingPairs)..shuffle();
      } else if (widget.question.type == QuestionType.matching && widget.readOnly) {
        _shuffledMatchingPairs = List<String>.from(widget.question.matchingPairs);
      } else {
        _shuffledMatchingPairs = null;
      }
      // Re-init text controller for new text question
      if (widget.question.type == QuestionType.text && oldWidget.question.type != QuestionType.text) {
        _textController?.dispose();
        _textController = TextEditingController(text: widget.answer as String? ?? '');
        _textController!.addListener(() { widget.onAnswerChanged(_textController!.text); });
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
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text('${widget.questionNumber}',
                      style: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(widget.question.text,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildAnswerInput(context),
            if (widget.readOnly)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    Icon(
                      widget.isCorrect == true ? Icons.check_circle
                          : widget.isCorrect == false ? Icons.cancel : Icons.hourglass_top,
                      color: widget.isCorrect == true ? Colors.green
                          : widget.isCorrect == false ? Colors.red : Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(widget.isCorrect == true ? 'Correct'
                        : widget.isCorrect == false ? 'Incorrect' : 'Awaiting review'),
                  ],
                ),
              ),
            // Show correct answer when wrong and showCorrectAnswer is enabled
            if (widget.readOnly && widget.isCorrect == false && widget.showCorrectAnswer)
              _buildCorrectAnswerHint(context),
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

  /// Shows the correct answer in a green box when the user got it wrong
  Widget _buildCorrectAnswerHint(BuildContext context) {
    final q = widget.question;
    String correctText = '';

    switch (q.type) {
      case QuestionType.singleChoice:
        if (q.correctOptionIndex != null && q.correctOptionIndex! < q.options.length) {
          correctText = q.options[q.correctOptionIndex!];
        }
        break;
      case QuestionType.multipleChoice:
        if (q.correctOptionIndices != null) {
          final labels = q.correctOptionIndices!
              .where((i) => i < q.options.length)
              .map((i) => q.options[i])
              .toList();
          correctText = labels.join(', ');
        }
        break;
      case QuestionType.trueFalse:
        if (q.correctBoolAnswer != null) {
          correctText = q.correctBoolAnswer! ? 'True' : 'False';
        }
        break;
      case QuestionType.matching:
        if (q.correctMatchingPairs != null) {
          correctText = q.correctMatchingPairs!
              .map((pair) => '${pair['left']} → ${pair['right']}')
              .join('\n');
        }
        break;
      case QuestionType.text:
        if (q.correctTextAnswer != null) {
          correctText = q.correctTextAnswer!;
        }
        break;
      default:
        break;
    }

    if (correctText.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.15),
        border: Border.all(color: Colors.green.shade400, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green.shade600, size: 20),
              const SizedBox(width: 8),
              Text(
                'Correct answer:',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Colors.green.shade400,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            correctText,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.green.shade300,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMultipleChoiceInput(BuildContext context) {
    final answer = widget.answer;
    List<String> selectedAnswers = [];
    if (answer is List) { selectedAnswers = answer.map((e) => e.toString()).toList(); }

    return Column(
      children: widget.question.options.map((option) {
        final isSelected = selectedAnswers.contains(option);
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            border: Border.all(
              color: isSelected ? const Color.fromARGB(255, 105, 167, 225) : Colors.grey.shade300,
              width: isSelected ? 2 : 1.5,
            ),
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected ? [BoxShadow(color: const Color.fromARGB(255, 12, 67, 99).withValues(alpha: 0.2), blurRadius: 6, offset: const Offset(0, 2))] : null,
          ),
          child: CheckboxListTile(
            title: Text(option,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? const Color.fromARGB(255, 255, 255, 255) : const Color.fromARGB(221, 255, 255, 255),
              )),
            value: isSelected,
            activeColor: const Color.fromARGB(255, 105, 167, 225),
            checkColor: Colors.white,
            onChanged: widget.readOnly ? null : (selected) {
              final newAnswers = List<String>.from(selectedAnswers);
              if (selected == true) { newAnswers.add(option); } else { newAnswers.remove(option); }
              widget.onAnswerChanged(newAnswers);
            },
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSingleChoiceInput(BuildContext context) {
    final selectedValue = widget.answer is String ? widget.answer : null;
    return Column(
      children: widget.question.options.map((option) {
        final isSelected = selectedValue == option;
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            border: Border.all(
              color: isSelected ? const Color.fromARGB(255, 105, 167, 225) : const Color.fromARGB(255, 228, 226, 226),
              width: isSelected ? 2 : 1.5,
            ),
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected ? [BoxShadow(color: const Color.fromARGB(255, 12, 67, 99).withValues(alpha: 0.2), blurRadius: 6, offset: const Offset(0, 2))] : null,
          ),
          child: RadioListTile<String>(
            title: Text(option,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? const Color.fromARGB(255, 255, 255, 255) : const Color.fromARGB(221, 255, 255, 255),
              )),
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

  Widget _buildTrueFalseInput(BuildContext context) {
    bool? selectedValue;
    if (widget.answer is bool) { selectedValue = widget.answer as bool?; }
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            border: Border.all(
              color: selectedValue == true ? const Color.fromARGB(255, 105, 167, 225) : const Color.fromARGB(255, 228, 226, 226),
              width: selectedValue == true ? 2 : 1.5,
            ),
            borderRadius: BorderRadius.circular(10),
            boxShadow: selectedValue == true ? [BoxShadow(color: const Color.fromARGB(255, 12, 67, 99).withValues(alpha: 0.2), blurRadius: 6, offset: const Offset(0, 2))] : null,
          ),
          child: RadioListTile<bool>(
            title: Text('True',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: selectedValue == true ? FontWeight.w600 : FontWeight.w400,
                color: const Color.fromARGB(255, 255, 255, 255),
              )),
            value: true,
            groupValue: selectedValue,
            activeColor: const Color.fromARGB(255, 255, 255, 255),
            onChanged: widget.readOnly ? null : widget.onAnswerChanged,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: selectedValue == false ? const Color.fromARGB(255, 105, 167, 225) : const Color.fromARGB(255, 228, 226, 226),
              width: selectedValue == false ? 2 : 1.5,
            ),
            borderRadius: BorderRadius.circular(10),
            boxShadow: selectedValue == false ? [BoxShadow(color: const Color.fromARGB(255, 12, 67, 99).withValues(alpha: 0.2), blurRadius: 6, offset: const Offset(0, 2))] : null,
          ),
          child: RadioListTile<bool>(
            title: Text('False',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: selectedValue == false ? FontWeight.w600 : FontWeight.w400,
                color: const Color.fromARGB(221, 255, 255, 255),
              )),
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

  Widget _buildTextInput(BuildContext context) {
    return TextField(
      decoration: const InputDecoration(hintText: 'Enter your answer here...', border: OutlineInputBorder()),
      maxLines: 3,
      controller: _textController,
      readOnly: widget.readOnly,
    );
  }

  Widget _buildMatchingInput(BuildContext context) {
    Map<String, String> matches = {};
    if (widget.answer is Map) { matches = (widget.answer as Map).cast<String, String>(); }
    final leftItems = widget.question.options;
    final rightItems = _shuffledMatchingPairs ?? widget.question.matchingPairs;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Select the correct option:',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        ...leftItems.map((leftItem) {
          final used = matches.entries.where((e) => e.key != leftItem).map((e) => e.value).toSet();
          final current = matches[leftItem];
          final availableOptions = rightItems.where((opt) => opt == current || !used.contains(opt)).toSet().toList();
          // Ensure current value exists in available options; if not, treat as unselected for display
          final displayValue = (current != null && availableOptions.contains(current)) ? current : null;

          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: const Color.fromARGB(255, 255, 255, 255), width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(leftItem,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600, color: const Color.fromARGB(255, 255, 255, 255))),
                      ),
                      const SizedBox(width: 12),
                      const Icon(Icons.arrow_forward, size: 20, color: Color.fromARGB(255, 255, 255, 255)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    decoration: InputDecoration(
                      isDense: false,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: current != null ? const Color.fromARGB(255, 105, 167, 225) : Colors.white.withValues(alpha: 0.5), width: 2)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: current != null ? const Color.fromARGB(255, 105, 167, 225) : Colors.white.withValues(alpha: 0.5), width: 2)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color.fromARGB(255, 105, 167, 225), width: 2)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      filled: true,
                      fillColor: current != null ? const Color.fromARGB(255, 105, 167, 225).withValues(alpha: 0.15) : Colors.transparent,
                    ),
                    isExpanded: true,
                    hint: Text('Select', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.7))),
                    initialValue: displayValue,
                    items: [
                      if (displayValue != null)
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Row(
                            children: [
                              Icon(Icons.close, size: 16, color: Colors.red.shade300),
                              const SizedBox(width: 8),
                              Text('Clear selection',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.red.shade300, fontWeight: FontWeight.w500, fontStyle: FontStyle.italic, fontSize: 12)),
                            ],
                          ),
                        ),
                      ...availableOptions.map((pair) => DropdownMenuItem<String?>(
                        value: pair,
                        child: Text(pair,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: const Color.fromARGB(255, 255, 255, 255), fontWeight: FontWeight.w500, fontSize: 12),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      )),
                    ],
                    dropdownColor: const Color.fromARGB(255, 40, 60, 90),
                    isDense: true,
                    menuMaxHeight: 300,
                    onChanged: widget.readOnly ? null : (value) {
                      final newMatches = Map<String, String>.from(matches);
                      if (value == null) { newMatches.remove(leftItem); } else { newMatches[leftItem] = value; }
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

// ---------------------------------------------------------------------------
// Disclaimer Dialog
// ---------------------------------------------------------------------------

class _DisclaimerDialog extends StatefulWidget {
  final String disclaimer;
  const _DisclaimerDialog({required this.disclaimer});

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
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.onPrimaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Please read and accept the following',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onPrimaryContainer)),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Text(widget.disclaimer, style: Theme.of(context).textTheme.bodyMedium),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('I understand and accept the above terms', style: Theme.of(context).textTheme.bodyMedium),
                  value: _accepted,
                  onChanged: (value) { setState(() { _accepted = value ?? false; }); },
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Decline')),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _accepted ? () => Navigator.of(context).pop(true) : null,
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


