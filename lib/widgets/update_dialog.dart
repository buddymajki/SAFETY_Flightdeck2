import 'package:flutter/material.dart';
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
  bool _isDownloading = false;
  bool _isInstalling = false;

  // Localization texts
  static const Map<String, Map<String, String>> _texts = {
    'new_version_available': {'en': 'New Version Available', 'de': 'Neue Version verfügbar'},
    'current_version': {'en': 'Current version:', 'de': 'Aktuelle Version:'},
    'available_version': {'en': 'Available version:', 'de': 'Verfügbare Version:'},
    'whats_new': {'en': 'What\'s new:', 'de': 'Neuigkeiten:'},
    'downloading': {'en': 'Downloading...', 'de': 'Wird heruntergeladen...'},
    'installing': {'en': 'Installing...', 'de': 'Wird installiert...'},
    'error': {'en': 'Error:', 'de': 'Fehler:'},
    'later': {'en': 'Later', 'de': 'Später'},
    'install': {'en': 'Install', 'de': 'Installieren'},
    'install_failed': {'en': 'Installation failed.\nError:', 'de': 'Installation fehlgeschlagen.\nFehler:'},
    'download_failed': {'en': 'Download failed.', 'de': 'Download fehlgeschlagen.'},
    'apk_not_ready': {'en': 'This version will be released in the next 30 minutes. Click Update in the version menu (hamburger menu).', 'de': 'Diese Version wird in den nächsten 30 Minuten veröffentlicht. Klicken Sie auf Update im Versionsmenü (Hamburger-Menü).'},
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

        return AlertDialog(
          title: Text(_getText('new_version_available', lang)),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${_getText('current_version', lang)} ${updateService.appVersion}'),
                const SizedBox(height: 8),
                Text('${_getText('available_version', lang)} ${updateInfo.version}'),
                const SizedBox(height: 16),
                Text(_getText('whats_new', lang)),
                const SizedBox(height: 8),
                Text(
                  updateInfo.changelog,
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 16),
                if (_isDownloading)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_getText('downloading', lang)),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: updateService.downloadProgress,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${(updateService.downloadProgress * 100).toStringAsFixed(1)}%',
                      ),
                    ],
                  ),
                if (_isInstalling)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(_getText('installing', lang)),
                  ),
                if (updateService.lastError.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Container(
                      padding: const EdgeInsets.all(8.0),
                      decoration: BoxDecoration(
                        color: Colors.red.shade100,
                        border: Border.all(color: Colors.red),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getText('error', lang),
                            style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            updateService.lastError,
                            style: const TextStyle(color: Colors.red, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            if (!_isDownloading && !_isInstalling)
              TextButton(
                onPressed: () {
                  widget.onSkip();
                  Navigator.of(context).pop();
                },
                child: Text(_getText('later', lang)),
              ),
            if (!_isDownloading && !_isInstalling)
              ElevatedButton.icon(
                icon: const Icon(Icons.download),
                label: Text(_getText('install', lang)),
                onPressed: () async {
                  setState(() => _isDownloading = true);

                  final success = await updateService.downloadUpdate(
                    (progress) {
                      setState(() {});
                    },
                  );

                  if (success) {
                    setState(() {
                      _isDownloading = false;
                      _isInstalling = true;
                    });

                    final installed = await updateService.installUpdate();

                    if (installed) {
                      widget.onUpdate();
                      if (context.mounted) {
                        Navigator.of(context).pop();
                      }
                    } else {
                      setState(() => _isInstalling = false);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '${_getText('install_failed', lang)} ${updateService.lastError}',
                            ),
                            duration: const Duration(seconds: 5),
                          ),
                        );
                      }
                    }
                  } else {
                    setState(() => _isDownloading = false);
                    if (context.mounted) {
                      // Check if APK is not ready yet (404 error)
                      final isApkNotReady = updateService.lastError.contains('404') || 
                                           updateService.lastError.contains('APK_NOT_READY');
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            isApkNotReady 
                              ? _getText('apk_not_ready', lang)
                              : _getText('download_failed', lang),
                          ),
                          duration: Duration(seconds: isApkNotReady ? 8 : 3),
                        ),
                      );
                    }
                  }
                },
              ),
            if (_isDownloading || _isInstalling)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: _isDownloading ? null : 1.0,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
