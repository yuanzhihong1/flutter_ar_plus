import 'package:flutter/services.dart';
import 'package:flutter_ar_plus/src/flutter_ar_plus_method_channel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final MethodChannelFlutterArPlus platform = MethodChannelFlutterArPlus();
  const MethodChannel channel = MethodChannel('flutter_ar_plus');

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
