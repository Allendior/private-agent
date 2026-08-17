import 'package:flutter/material.dart';

import '../pairing/pairing_controller.dart';
import '../pairing/pairing_import.dart';

class CompanionHome extends StatefulWidget {
  const CompanionHome({super.key, required this.controller});

  final PairingController controller;

  @override
  State<CompanionHome> createState() => _CompanionHomeState();
}

class _CompanionHomeState extends State<CompanionHome> {
  late Future<PairingStatus> _statusFuture;

  @override
  void initState() {
    super.initState();
    _statusFuture = widget.controller.status();
  }

  Future<void> _showPairingImport() async {
    final payloadController = TextEditingController();
    String? error;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Import one-time pairing'),
          content: TextField(
            controller: payloadController,
            autocorrect: false,
            enableSuggestions: false,
            maxLines: 6,
            decoration: InputDecoration(
              labelText: 'Pairing payload',
              errorText: error,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  final imported = PairingImport.parse(
                    payloadController.text,
                    nowSeconds: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                  );
                  await widget.controller.pair(imported.record);
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  if (mounted) {
                    setState(() {
                      _statusFuture = widget.controller.status();
                    });
                  }
                } on FormatException {
                  setDialogState(() => error = 'Invalid or expired pairing payload');
                } on ArgumentError {
                  setDialogState(() => error = 'Invalid pairing credentials');
                }
              },
              child: const Text('Save pairing'),
            ),
          ],
        ),
      ),
    );
    payloadController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PrivateAgent Companion')),
      body: FutureBuilder<PairingStatus>(
        future: _statusFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final status = snapshot.requireData;
          final paired = status.deviceId != null;
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    paired ? Icons.verified_user_outlined : Icons.link_off,
                    size: 48,
                    color: paired ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    paired ? 'Paired: ${status.deviceId}' : 'Not paired',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text('No active connection'),
                  const SizedBox(height: 20),
                  const Text(
                    'This companion can only verify a signed status proof. '
                    'It does not run in the background, connect to a server, '
                    'or control your phone.',
                  ),
                  if (!paired) ...[
                    const SizedBox(height: 24),
                    OutlinedButton(
                      onPressed: _showPairingImport,
                      child: const Text('Import one-time pairing'),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
