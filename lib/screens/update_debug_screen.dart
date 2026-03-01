// Development UI for testing the update system

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
                // Version info
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Version Info',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        Text('App version (installed): ${updateService.appVersion}'),
                        const SizedBox(height: 8),
                        if (updateService.updateInfo != null) ...[
                          Text('Latest version (Firestore): ${updateService.updateInfo!.version}',
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text('Force update: ${updateService.updateInfo!.isForceUpdate}'),
                          const SizedBox(height: 4),
                          const Text('Changelog:'),
                          Text(updateService.updateInfo!.changelog,
                              style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        ] else
                          const Text('No update info loaded yet – click Check for Updates'),
                        if (updateService.lastError.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text('Last error: ${updateService.lastError}',
                              style: const TextStyle(color: Colors.red, fontSize: 12)),
                        ],
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
                        const Text('Debug Actions',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),

                        // 1. Check Firestore
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.cloud_download),
                            label: const Text('1. Check Firestore for Updates'),
                            onPressed: _isLoading
                                ? null
                                : () async {
                                    final messenger = ScaffoldMessenger.of(context);
                                    setState(() => _isLoading = true);
                                    try {
                                      final hasUpdate = await updateService.checkForUpdates();
                                      if (!mounted) return;
                                      messenger.showSnackBar(SnackBar(
                                        content: Text(hasUpdate
                                            ? 'Update available: ${updateService.updateInfo?.version}'
                                            : 'No update available'),
                                        backgroundColor: hasUpdate ? Colors.orange : Colors.green,
                                      ));
                                    } finally {
                                      if (mounted) setState(() => _isLoading = false);
                                    }
                                  },
                          ),
                        ),
                        const SizedBox(height: 8),

                        // 2. Show dialog
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.notification_important),
                            label: const Text('2. Show Update Dialog'),
                            onPressed: updateService.updateInfo == null
                                ? null
                                : () {
                                    showDialog(
                                      context: context,
                                      barrierDismissible: false,
                                      builder: (_) => UpdateDialog(
                                        onSkip: () => debugPrint('[Debug] skipped'),
                                        onUpdate: () => debugPrint('[Debug] opened update link'),
                                      ),
                                    );
                                  },
                          ),
                        ),
                        const SizedBox(height: 8),

                        // 3. Open platform update link
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.open_in_new),
                            label: const Text('3. Open Update Link (TestFlight/Firebase)'),
                            onPressed: () => updateService.openAppUpdateLink(),
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Clear
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.clear),
                            label: const Text('Clear cached update info'),
                            onPressed: () {
                              updateService.clear();
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Cache cleared')));
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Status
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Status',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        if (_isLoading)
                          const Row(children: [
                            SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2)),
                            SizedBox(width: 12),
                            Text('Checking Firestore...'),
                          ])
                        else
                          Text('Ready',
                              style: TextStyle(
                                  color: Colors.green[600], fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Instructions
                Card(
                  color: Colors.blue[50],
                  child: const Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('How it works',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        SizedBox(height: 12),
                        Text(
                          '1. Upload APK to Firebase App Distribution\n'
                          '   → testers get an email automatically\n\n'
                          '2. Update Firestore:\n'
                          '   → app_updates/android (Android)\n'
                          '   → app_updates/ios (iOS)\n'
                          '   → app_updates/latest (fallback)\n\n'
                          '3. App checks Firestore on startup\n'
                          '   → shows dialog if newer version found\n\n'
                          'isForceUpdate: true  →  no "Later" button\n'
                          'isForceUpdate: false →  user can dismiss',
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
