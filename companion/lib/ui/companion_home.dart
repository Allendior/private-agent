import 'package:flutter/material.dart';

import '../pairing/pairing_controller.dart';
import '../pairing/pairing_import.dart';
import '../transport/status_client.dart';
import '../transport/job_poller.dart';

class CompanionHome extends StatefulWidget {
  const CompanionHome({
    super.key,
    required this.controller,
    this.probeController,
    this.jobPoller,
  });

  final PairingController controller;
  final StatusProbeController? probeController;
  final JobPoller? jobPoller;

  @override
  State<CompanionHome> createState() => _CompanionHomeState();
}

class _CompanionHomeState extends State<CompanionHome> {
  late Future<PairingStatus> _statusFuture;
  bool _probing = false;
  String? _lastResult;
  String? _lastJobResult;

  @override
  void initState() {
    super.initState();
    _statusFuture = widget.controller.status();
    // Wire up job execution callback
    widget.jobPoller?.onJobExecuted = (result) {
      if (mounted) {
        setState(() {
          _lastJobResult = result.status == 'ok'
              ? 'Job ${result.jobId}: OK'
              : 'Job ${result.jobId}: FAILED (${result.detail})';
        });
      }
    };
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

  Future<void> _testConnection() async {
    final probe = widget.probeController;
    if (probe == null || _probing) return;
    setState(() {
      _probing = true;
      _lastResult = null;
    });
    final result = await probe.probe();
    if (!mounted) return;
    setState(() {
      _probing = false;
      _lastResult = result.success ? 'OK' : 'FAILED: ${result.code}';
    });
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
          final canProbe = paired && widget.probeController != null;
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
                    'It does not run in the background or control your phone.',
                  ),
                  if (!paired) ...[
                    const SizedBox(height: 24),
                    OutlinedButton(
                      onPressed: _showPairingImport,
                      child: const Text('Import one-time pairing'),
                    ),
                  ],
                  if (canProbe) ...[
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _probing ? null : _testConnection,
                      child: _probing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Test private connection'),
                    ),
                    if (_lastResult != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _lastResult!,
                        style: TextStyle(
                          color: _lastResult == 'OK' ? Colors.green : Colors.red,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (_lastJobResult != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _lastJobResult!,
                        style: TextStyle(
                          color: _lastJobResult!.contains('OK') ? Colors.blue : Colors.red,
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                    ],
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
