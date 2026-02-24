import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_config_service.dart';
import '../widgets/responsive_layout.dart';

// --- Color constants for consistency ---
const Color theoryButtonColor = Color(0xFF805ad5); // Purple

// --- Data structure for theory topics ---
class TheoryTopic {
  final String titleEn;
  final String titleDe;
  final String titleIt;
  final String titleFr;
  final String url;

  TheoryTopic({
    required this.titleEn,
    required this.titleDe,
    required this.titleIt,
    required this.titleFr,
    required this.url,
  });

  String getTitle(String languageCode) {
    switch (languageCode) {
      case 'de': return titleDe;
      case 'it': return titleIt;
      case 'fr': return titleFr;
      default: return titleEn;
    }
  }
}

// Complete list of theory topics
final List<TheoryTopic> theoryTopics = [
  TheoryTopic(
    titleEn: "Aerodynamics",
    titleDe: "Aerodynamik",
    titleIt: "Aerodinamica",
    titleFr: "Aérodynamique",
    url: "https://flywithmiki.com/theory/aerodynamics.pdf",
  ),
  TheoryTopic(
    titleEn: "Flying Practice",
    titleDe: "Flugpraxis",
    titleIt: "Pratica di volo",
    titleFr: "Pratique de vol",
    url: "https://flywithmiki.com/theory/flightpraxis.pdf",
  ),
  TheoryTopic(
    titleEn: "Legislation (Airspaces)",
    titleDe: "Luftfahrtgesetze (Lufträume)",
    titleIt: "Legislazione (Spazi aerei)",
    titleFr: "Législation (Espaces aériens)",
    url: "https://flywithmiki.com/theory/law.pdf",
  ),
  TheoryTopic(
    titleEn: "Material Sciences",
    titleDe: "Materialwissenschaften",
    titleIt: "Scienza dei materiali",
    titleFr: "Sciences des matériaux",
    url: "https://flywithmiki.com/theory/material.pdf",
  ),
  TheoryTopic(
    titleEn: "Weather",
    titleDe: "Wetter",
    titleIt: "Meteorologia",
    titleFr: "Météorologie",
    url: "https://flywithmiki.com/theory/meteo.pdf",
  ),
];

class TheoryScreen extends StatelessWidget {
  const TheoryScreen({super.key});

  // Localization map
  static const Map<String, Map<String, String>> _texts = {
    'Core_Theory': {'en': 'Core Theory', 'de': 'Kerntheorie', 'it': 'Teoria di base', 'fr': 'Théorie fondamentale'},
    'Select_Topic': {
      'en': 'Please select the theoretical topic to download or open the corresponding PDF.',
      'de': 'Bitte wählen Sie das Thema zum Herunterladen oder Öffnen der entsprechenden PDF-Datei.',
      'it': 'Selezionare l\'argomento teorico per scaricare o aprire il PDF corrispondente.',
      'fr': 'Veuillez sélectionner le sujet théorique pour télécharger ou ouvrir le PDF correspondant.',
    },
    'Coming_Soon': {
      'en': 'Visit this site from time to time - new content will come soon...',
      'de': 'Besuchen Sie diese Website von Zeit zu Zeit - neue Inhalte werden bald verfügbar...',
      'it': 'Visitate questo sito di tanto in tanto - nuovi contenuti arriveranno presto...',
      'fr': 'Visitez ce site de temps en temps - de nouveaux contenus arriveront bientôt...',
    },
  };

  String _t(String key, String lang) {
    return _texts[key]?[lang] ?? key;
  }

  // Launch URL
  Future<void> _launchUrl(String urlString) async {
    final Uri url = Uri.parse(urlString);
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw Exception('Could not launch $url');
      }
    } catch (e) {
      debugPrint('Error launching URL: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final appConfig = context.watch<AppConfigService>();
    final lang = appConfig.currentLanguageCode;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: ResponsiveListView(
        children: [
          // Main Title (centered and bold)
          Center(
            child: Text(
              _t('Core_Theory', lang),
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),

          const SizedBox(height: 24),

          // Introductory text
          Text(
            _t('Select_Topic', lang),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
            ),
          ),

          const SizedBox(height: 24),

          // Theory topic buttons
          for (final topic in theoryTopics)
            Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton.icon(
                  onPressed: () => _launchUrl(topic.url),
                  icon: const Icon(Icons.picture_as_pdf),
                  label: Text(
                    topic.getTitle(lang),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theoryButtonColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 4,
                  ),
                ),
              ),
            ),

          const SizedBox(height: 30),
          Divider(
            color: theme.dividerColor.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 10),

          // Note for future expansion
          Text(
            _t('Coming_Soon', lang),
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.amberAccent,
            ),
          ),
        ],
      ),
    );
  }
}
