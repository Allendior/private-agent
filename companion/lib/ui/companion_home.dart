import 'package:flutter/material.dart';

import '../pairing/pairing_controller.dart';

class CompanionHome extends StatelessWidget {
  const CompanionHome({super.key, required this.controller});

  final PairingController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PrivateAgent Companion')),
      body: FutureBuilder<PairingStatus>(
        future: controller.status(),
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
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
