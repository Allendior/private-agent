import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('manifest can resolve launcher packages without QUERY_ALL_PACKAGES', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();

    final queries =
        RegExp(r'<queries>([\s\S]*)</queries>')
            .firstMatch(manifest)
            ?.group(1) ??
        '';
    expect(manifest.contains('QUERY_ALL_PACKAGES'), isFalse);
    expect(queries.contains('android.intent.action.MAIN'), isTrue);
    expect(queries.contains('android.intent.category.LAUNCHER'), isTrue);
    expect(queries.contains('com.google.android.youtube'), isTrue);
  });

  test('manifest grants only the standard permission needed to set alarms', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();

    expect(manifest.contains('com.android.alarm.permission.SET_ALARM'), isTrue);
  });
}
