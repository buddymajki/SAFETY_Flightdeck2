// Development UI for testing the update system
// Add this temporary screen to main_navigation.dart or create a debug screen

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/update_service.dart';
import '../widgets/update_dialog.dart';

class UpdateSystemDebugScreen extends StatefulWidget {
  const UpdateSystemDebugScreen({super.key});

  @override
  State<UpdateSystemDebugScreen> createState() => _UpdateSystemDebugScreenState();
}

class _UpdateSystemDebugScreenState extends State<UpdateSystemDebugScreen> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Update System Debug'),
      ),
      body: Consumer<UpdateService>(
        builder: (context, updateService, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Current version info
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Version Info',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text('App Version: ${updateService.appVersion}'),
                        const SizedBox(height: 8),
                        if (updateService.updateInfo != null) ...[
                          Text('Latest Version: ${updateService.updateInfo!.version}'),
                          const SizedBox(height: 8),
                          const Text('Changelog:'),
                          Text(
                            updateService.updateInfo!.changelog,
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(height: 8),
                          Text('Download URL: ${updateService.updateInfo!.downloadUrl}'),
                        ] else
                          const Text('No update info loaded'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Action buttons
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Debug Actions',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.refresh),
                          label: const Text('Check for Updates'),
                          onPressed: _isLoading
                              ? null
                              : () async {
                                  setState(() => _isLoading = true);
                                  try {
                                    final hasUpdate =
                                        await updateService.checkForUpdates();
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          hasUpdate
                                              ? 'Update available!'
                                              : 'No update available',
                                        ),
                                      ),
                                    );
                                  } finally {
                                    if (mounted) {
                                      setState(() => _isLoading = false);
                                    }
                                  }
                                },
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.notification_important),
                          label: const Text('Show Update Dialog'),
                          onPressed: updateService.updateInfo == null
                              ? null
                              : () {
                                  showDialog(
                                    context: context,
                                    barrierDismissible: false,
                                    builder: (BuildContext dialogContext) =>
                                        UpdateDialog(
                                      onSkip: () {
                                        debugPrint('[Debug] User skipped');
                                      },
                                      onUpdate: () {
                                        debugPrint('[Debug] Update complete');
                                      },
                                    ),
                                  );
                                },
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.download),
                          label: const Text('Download Only'),
                          onPressed: updateService.updateInfo == null
                              ? null
                              : () async {
                                  setState(() => _isLoading = true);
                                  try {
                                    final success =
                                        await updateService.downloadUpdate(
                                      (progress) {
                                        debugPrint(
                                          'Download progress: ${(progress * 100).toStringAsFixed(1)}%',
                                        );
                                      },
                                    );
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          success
                                              ? 'Download successful'
                                              : 'Download failed',
                                        ),
                                      ),
                                    );
                                  } finally {
                                    if (mounted) {
                                      setState(() => _isLoading = false);
                                    }
                                  }
                                },
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.install_mobile),
                          label: const Text('Install APK'),
                          onPressed: updateService.updateInfo == null
                              ? null
                              : () async {
                                  try {
                                    final success =
                                        await updateService.installUpdate();
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          success
                                              ? 'Installation started'
                                              : 'Installation failed',
                                        ),
                                      ),
                                    );
                                  } catch (e) {
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(
                                      SnackBar(content: Text('Error: $e')),
                                    );
                                  }
                                },
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.clear),
                          label: const Text('Clear Cache'),
                          onPressed: () {
                            updateService.clear();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Cache cleared'),
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Status section
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Status',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_isLoading)
                          const Row(
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: 12),
                              Text('Loading...'),
                            ],
                          )
                        else
                          Text(
                            'Ready',
                            style: TextStyle(
                              color: Colors.green[600],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        const SizedBox(height: 8),
                        if (updateService.downloadProgress > 0)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Download Progress:'),
                              const SizedBox(height: 4),
                              LinearProgressIndicator(
                                value: updateService.downloadProgress,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${(updateService.downloadProgress * 100).toStringAsFixed(1)}%',
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Documentation
                Card(
                  color: Colors.blue[50],
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Testing Instructions',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '1. Set up Firestore "app_updates/latest" document\n'
                          '2. Click "Check for Updates" to sync from Firestore\n'
                          '3. Click "Show Update Dialog" to test the UI\n'
                          '4. Use "Download Only" to test APK download\n'
                          '5. Use "Install APK" to trigger installation\n'
                          '\n'
                          'For full flow test:\n'
                          '- Restart app after checking updates\n'
                          '- Dialog appears automatically\n'
                          '- Click "Telepítés" to download & install',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
