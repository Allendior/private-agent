import 'package:flutter/material.dart';

import 'pairing/pairing_controller.dart';
import 'pairing/secure_key_store.dart';
import 'ui/companion_home.dart';

void main() {
  runApp(MyApp(controller: PairingController(SecureKeyStore())));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.controller});

  final PairingController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PrivateAgent Companion',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: CompanionHome(controller: controller),
    );
  }
}
