import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:provider/provider.dart';
import '../services/update_service.dart';
import '../services/app_config_service.dart';

class UpdateDialog extends StatefulWidget {
  final VoidCallback onSkip;
  final VoidCallback onUpdate;

  const UpdateDialog({
    super.key,
    required this.onSkip,
    required this.onUpdate,
  });

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  // ============================================================
  // RÉGI STATE VÁLTOZÓK – KOMMENTÁLVA (GitHub/GDrive letöltéshez kelltek)
  // bool _isDownloading = false;
  // bool _isInstalling = false;
  // ============================================================

  static const Map<String, Map<String, String>> _texts = {
    'new_version_available': {'en': 'New Version Available', 'de': 'Neue Version verfügbar', 'hu': 'Új verzió elérhető', 'it': 'Nuova versione disponibile', 'fr': 'Nouvelle version disponible'},
    'current_version': {'en': 'Current version:', 'de': 'Aktuelle Version:', 'hu': 'Jelenlegi verzió:', 'it': 'Versione attuale:', 'fr': 'Version actuelle :'},
    'available_version': {'en': 'Available version:', 'de': 'Verfügbare Version:', 'hu': 'Elérhető verzió:', 'it': 'Versione disponibile:', 'fr': 'Version disponible :'},
    'whats_new': {'en': 'What\'s new:', 'de': 'Neuigkeiten:', 'hu': 'Mi új:', 'it': 'Novità:', 'fr': 'Nouveautés :'},
    'firebase_info': {
      'en': 'A new version has been sent to you via Firebase App Distribution.\nCheck your email for the download link.',
      'de': 'Eine neue Version wurde Ihnen über Firebase App Distribution zugesandt.\nPrüfen Sie Ihre E-Mail für den Download-Link.',
      'hu': 'Új verziót kaptl Firebase App Distribution emailben.\nKeresd az emailt a letöltési linkkel.',
      'it': 'Una nuova versione è stata inviata tramite Firebase App Distribution.\nControlla la tua email per il link di download.',
      'fr': 'Une nouvelle version vous a été envoyée via Firebase App Distribution.\nVérifiez votre e-mail pour le lien de téléchargement.',
    },
    'testflight_info': {
      'en': 'A new version is available via TestFlight.\nOpen TestFlight and update the app.',
      'de': 'Eine neue Version ist über TestFlight verfügbar.\nÖffnen Sie TestFlight und aktualisieren Sie die App.',
      'hu': 'Új verzió elérhető TestFlight-on.\nNyisd meg a TestFlightot és frissítsd az appot.',
      'it': 'È disponibile una nuova versione tramite TestFlight.\nApri TestFlight e aggiorna l’app.',
      'fr': 'Une nouvelle version est disponible via TestFlight.\nOuvrez TestFlight et mettez l’app à jour.',
    },
    'open_firebase': {'en': 'Open Firebase App Distribution', 'de': 'Firebase App Distribution öffnen', 'hu': 'Firebase App Distribution megnyêtása', 'it': 'Apri Firebase App Distribution', 'fr': 'Ouvrir Firebase App Distribution'},
    'open_testflight': {'en': 'Open TestFlight', 'de': 'TestFlight öffnen', 'hu': 'TestFlight megnyitása', 'it': 'Apri TestFlight', 'fr': 'Ouvrir TestFlight'},
    'later': {'en': 'Later', 'de': 'Später', 'hu': 'Később', 'it': 'Più tardi', 'fr': 'Plus tard'},
    // Régi szövegek – kommentálva (GitHub/GDrive letöltés)
    // 'downloading': {'en': 'Downloading...', 'de': 'Wird heruntergeladen...'},
    // 'installing': {'en': 'Installing...', 'de': 'Wird installiert...'},
    // 'install': {'en': 'Install', 'de': 'Installieren'},
    // 'install_failed': {'en': 'Installation failed.\nError:', 'de': 'Installation fehlgeschlagen.\nFehler:'},
    // 'download_failed': {'en': 'Download failed.', 'de': 'Download fehlgeschlagen.'},
    // 'apk_not_ready': {'en': 'This version will be released in the next 30 minutes...', 'de': '...'},
    // 'permission_needed': {'en': 'Permission required!\n\n...', 'de': '...'},
  };

  String _getText(String key, String lang) {
    return _texts[key]?[lang] ?? _texts[key]?['en'] ?? key;
  }

  @override
  Widget build(BuildContext context) {
    final appConfig = Provider.of<AppConfigService>(context, listen: false);
    final lang = appConfig.currentLanguageCode;

    return Consumer<UpdateService>(
      builder: (context, updateService, _) {
        final updateInfo = updateService.updateInfo;
        if (updateInfo == null) return const SizedBox.shrink();

        final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
          backgroundColor: Theme.of(context).dialogTheme.backgroundColor ?? Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  child: Row(
                    children: [
                      const Icon(Icons.system_update, color: Colors.blue),
                      const SizedBox(width: 8),
                      Text(
                        _getText('new_version_available', lang),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${_getText('current_version', lang)} ${updateService.appVersion}'),
                      const SizedBox(height: 4),
                      Text('${_getText('available_version', lang)} ${updateInfo.version}',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      Text(_getText('whats_new', lang)),
                      const SizedBox(height: 4),
                      Text(updateInfo.changelog, style: const TextStyle(fontSize: 12)),
                      const SizedBox(height: 16),
                      // Platform-specific distribution info
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          border: Border.all(color: Colors.blue.shade200),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              isIOS ? Icons.ios_share : Icons.email_outlined,
                              color: Colors.blue,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _getText(isIOS ? 'testflight_info' : 'firebase_info', lang),
                                style: TextStyle(fontSize: 12, color: Colors.blue.shade800),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // "Később" gomb: forceUpdate esetén elrejtve
                      if (!updateInfo.isForceUpdate)
                        TextButton(
                          onPressed: () {
                            widget.onSkip();
                            Navigator.of(context).pop();
                          },
                          child: Text(_getText('later', lang)),
                        ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: Text(_getText(isIOS ? 'open_testflight' : 'open_firebase', lang)),
                        onPressed: () async {
                          await updateService.openAppUpdateLink();
                          widget.onUpdate();
                          if (context.mounted) Navigator.of(context).pop();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    // ============================================================
    // RÉGI DOWNLOAD/INSTALL UI – KOMMENTÁLVA
    // Visszatéréshez GitHub release-re: töröld a komment jeleket,
    // és add vissza az _isDownloading / _isInstalling state-eket.
    //
    // if (_isDownloading)
    //   Column(children: [
    //     Text(_getText('downloading', lang)),
    //     LinearProgressIndicator(value: updateService.downloadProgress),
    //     Text('${(updateService.downloadProgress * 100).toStringAsFixed(1)}%'),
    //   ]),
    // if (_isInstalling)
    //   Text(_getText('installing', lang)),
    //
    // ElevatedButton.icon(
    //   icon: const Icon(Icons.download),
    //   label: Text(_getText('install', lang)),
    //   onPressed: () async {
    //     setState(() => _isDownloading = true);
    //     final success = await updateService.downloadUpdate((p) => setState(() {}));
    //     if (success) {
    //       setState(() { _isDownloading = false; _isInstalling = true; });
    //       final installed = await updateService.installUpdate();
    //       if (installed) { widget.onUpdate(); Navigator.of(context).pop(); }
    //       else { setState(() => _isInstalling = false); }
    //     } else {
    //       setState(() => _isDownloading = false);
    //     }
    //   },
    // ),
    // ============================================================
  }
}
