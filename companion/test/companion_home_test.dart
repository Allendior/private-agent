import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_agent_companion/pairing/pairing_controller.dart';
import 'package:private_agent_companion/ui/companion_home.dart';

class MemoryStore implements KeyValueStore {
  final Map<String, String> values;
  MemoryStore([Map<String, String>? initial]) : values = {...?initial};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

void main() {
  testWidgets('unpaired screen states there is no active connection', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: CompanionHome(controller: PairingController(MemoryStore()))),
    );
    await tester.pump();

    expect(find.text('Not paired'), findsOneWidget);
    expect(find.text('No active connection'), findsOneWidget);
    expect(find.textContaining('Accessibility'), findsNothing);
  });

  testWidgets('paired screen shows its device identity but never the key', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CompanionHome(
          controller: PairingController(
            MemoryStore({
              'fleet.device_id': 'pixel-test',
              'fleet.shared_key': '0123456789abcdefghijklmnopqrstuvwxyz',
            }),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Paired: pixel-test'), findsOneWidget);
    expect(find.text('0123456789abcdefghijklmnopqrstuvwxyz'), findsNothing);
  });
}
