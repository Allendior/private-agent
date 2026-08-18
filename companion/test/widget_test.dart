import 'package:flutter_test/flutter_test.dart';
import 'package:private_agent_companion/main.dart';
import 'package:private_agent_companion/pairing/pairing_controller.dart';

class MemoryStore implements KeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

void main() {
  testWidgets('app starts as a local unpaired companion', (tester) async {
    await tester.pumpWidget(MyApp(controller: PairingController(MemoryStore())));
    await tester.pump();

    expect(find.text('PrivateAgent Companion'), findsOneWidget);
    expect(find.text('Not paired'), findsOneWidget);
    expect(find.text('Outbound poll: host jobs only while app is open'), findsOneWidget);
  });
}
