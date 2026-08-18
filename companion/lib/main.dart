import 'dart:io';

import 'package:flutter/material.dart';

import 'pairing/pairing_controller.dart';
import 'pairing/pairing_import.dart';
import 'pairing/secure_key_store.dart';
import 'transport/status_client.dart';
import 'transport/job_poller.dart';
import 'ui/companion_home.dart';

/// Bootstrap-only import path: a one-time activation payload written by the
/// host into this app's private files dir (via `adb push` + `run-as`). Kept
/// deliberately out of the runtime control surface so the normal pairing flow
/// remains the sole user-facing path.
const _bootstrapActivationPath =
    '/data/data/com.allendior.private_agent_companion/files/pending_activation.json';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final pairing = PairingController(SecureKeyStore());
  final transport = const IoStatusHttpTransport();
  final probe = StatusProbeController(
    pairing: pairing,
    transport: transport,
  );
  final poller = JobPoller(pairing: pairing, transport: transport);
  final imported = await _importBootstrapActivation(pairing);
  if (imported) {
    // Provisioning verification: the operator just pushed a fresh activation,
    // so immediately confirm the signed handshake end-to-end and log it.
    final result = await probe.probe();
    debugPrint(
      '[bootstrap] auto-probe: ${result.success ? 'OK' : 'FAILED ${result.code}'}',
    );
    if (result.success) {
      poller.start();
      debugPrint('[bootstrap] job poller started');
    }
  }
  runApp(MyApp(controller: pairing, probeController: probe, jobPoller: poller));
}

Future<bool> _importBootstrapActivation(PairingController pairing) async {
  final file = File(_bootstrapActivationPath);
  try {
    if (!await file.exists()) return false;
    final text = (await file.readAsString()).trim();
    final imported = PairingImport.parse(
      text,
      nowSeconds: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
    await pairing.pair(imported.record);
    await file.delete();
    debugPrint('[bootstrap] imported pairing for ${imported.record.deviceId}');
    return true;
  } on FormatException {
    await file.delete();
    debugPrint('[bootstrap] rejected invalid or expired activation');
    return false;
  } on ArgumentError {
    await file.delete();
    debugPrint('[bootstrap] rejected invalid pairing credentials');
    return false;
  } catch (error) {
    debugPrint('[bootstrap] activation import failed: $error');
    return false;
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.controller, this.probeController, this.jobPoller});
  final PairingController controller;
  final StatusProbeController? probeController;
  final JobPoller? jobPoller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PrivateAgent Companion',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: CompanionHome(controller: controller, probeController: probeController, jobPoller: jobPoller),
    );
  }
}
