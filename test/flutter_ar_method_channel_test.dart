import 'package:flutter/services.dart';
import 'package:flutter_ar/src/flutter_ar_method_channel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final MethodChannelFlutterAr platform = MethodChannelFlutterAr();
  const MethodChannel channel = MethodChannel('flutter_ar');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          return '42';
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('获取平台版本', () async {
    expect(await platform.getPlatformVersion(), '42');
  });
}
