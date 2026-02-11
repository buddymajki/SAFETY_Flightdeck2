import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/update_service.dart';

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

  @override
  Widget build(BuildContext context) {
    return Consumer<UpdateService>(
      builder: (context, updateService, _) {
        final updateInfo = updateService.updateInfo;
        if (updateInfo == null) return const SizedBox.shrink();

        return AlertDialog(
          title: const Text('Új verzió elérhető'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('A jelenlegi verzió: ${updateService.appVersion}'),
                const SizedBox(height: 8),
                Text('Elérhető verzió: ${updateInfo.version}'),
                const SizedBox(height: 16),
                const Text('Újdonságok:'),
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
                      const Text('Letöltés folyamatban...'),
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
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text('Telepítés folyamatban...'),
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
                          const Text(
                            'Hiba:',
                            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
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
                child: const Text('Később'),
              ),
            if (!_isDownloading && !_isInstalling)
              ElevatedButton.icon(
                icon: const Icon(Icons.download),
                label: const Text('Telepítés'),
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
                              'A telepítés sikertelen volt.\nHiba: ${updateService.lastError}',
                            ),
                            duration: const Duration(seconds: 5),
                          ),
                        );
                      }
                    }
                  } else {
                    setState(() => _isDownloading = false);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('A letöltés sikertelen volt.'),
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
