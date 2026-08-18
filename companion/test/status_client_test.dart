import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:private_agent_companion/pairing/pairing_controller.dart';
import 'package:private_agent_companion/transport/status_client.dart';

class MemoryStore implements KeyValueStore {
  final Map<String, String> values = {};
  @override
  Future<void> delete(String key) async => values.remove(key);
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class FakeTransport implements StatusHttpTransport {
  int calls = 0;
  String? lastBody;
  StatusHttpResponse Function(String body)? responder;
  Completer<StatusHttpResponse>? pending;

  @override
  Future<StatusHttpResponse> post(Uri endpoint, String body) async {
    calls++;
    lastBody = body;
    if (pending != null) return pending!.future;
    return responder!(body);
  }
}

void main() {
  late MemoryStore store;
  late PairingController pairing;
  late FakeTransport transport;
  late StatusProbeController controller;

  setUp(() async {
    store = MemoryStore();
    pairing = PairingController(store);
    await pairing.pair(
      const PairingRecord(
        deviceId: 'pixel-test',
        sharedKey: 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8',
        endpoint: 'http://192.168.0.196:8787/v1/status',
        activationId: '00112233445566778899aabbccddeeff',
      ),
    );
    transport = FakeTransport();
    controller = StatusProbeController(
      pairing: pairing,
      transport: transport,
      nowSeconds: () => 1700000000,
      randomBytes: (_) => List<int>.generate(16, (index) => 255 - index * 17),
    );
  });

  test('does not send traffic until probe is explicitly called', () {
    expect(transport.calls, 0);
  });

  test('one manual probe sends one request and removes activation after verified success', () async {
    transport.responder = (_) => const StatusHttpResponse(
          statusCode: 200,
          body:
              '{"payload":{"created_at":1700000001,"device_id":"pixel-test","expires_at":1700000061,"kind":"host.status.response","request_id":"ffeeddccbbaa99887766554433221100","status":"ok","version":1},"signature":"cr-nzS8YWLrbd-MlUGXMwCutbEWtYtfpf8E8pCpYG3I"}',
          redirected: false,
        );

    final result = await controller.probe();

    expect(result.success, isTrue);
    expect(transport.calls, 1);
    expect((await pairing.record())!.activationId, isNull);
  });

  test('rejects redirects and keeps activation for a safe retry', () async {
    transport.responder = (_) => const StatusHttpResponse(
          statusCode: 307,
          body: '',
          redirected: true,
        );

    final result = await controller.probe();

    expect(result.success, isFalse);
    expect(result.code, 'REDIRECT_REJECTED');
    expect(transport.calls, 1);
    expect((await pairing.record())!.activationId, isNotNull);
  });

  test('coalesces no concurrent presses and sends only one in-flight request', () async {
    transport.pending = Completer<StatusHttpResponse>();
    final first = controller.probe();
    await Future<void>.delayed(Duration.zero);
    final second = await controller.probe();
    expect(second.code, 'PROBE_IN_PROGRESS');
    expect(transport.calls, 1);
    transport.pending!.complete(const StatusHttpResponse(statusCode: 500, body: '', redirected: false));
    await first;
  });
}
