// This is a basic Flutter integration test.
//
// Since integration tests run in a full Flutter application, they can interact
// with the host side of a plugin implementation, unlike Dart unit tests.
//
// For more information about Flutter integration tests, please see
// https://flutter.dev/to/integration-testing

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_ar/flutter_ar.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native plugin reports the host platform', (
    WidgetTester tester,
  ) async {
    final FlutterAr plugin = FlutterAr();
    final String? version = await plugin.getPlatformVersion();
    final String expectedPrefix = switch (defaultTargetPlatform) {
      TargetPlatform.android => 'Android ',
      TargetPlatform.iOS => 'iOS ',
      _ => throw StateError('Run this test on Android or iOS.'),
    };
    expect(version, startsWith(expectedPrefix));
  });

  testWidgets('native plugin rejects unknown methods', (
    WidgetTester tester,
  ) async {
    const MethodChannel channel = MethodChannel('flutter_ar');
    await expectLater(
      channel.invokeMethod<void>('unknownMethod'),
      throwsA(isA<MissingPluginException>()),
    );
  });
}
