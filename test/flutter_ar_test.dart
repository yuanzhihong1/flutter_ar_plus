import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ar/flutter_ar.dart';
import 'package:flutter_ar/flutter_ar_platform_interface.dart';
import 'package:flutter_ar/flutter_ar_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFlutterArPlatform
    with MockPlatformInterfaceMixin
    implements FlutterArPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final FlutterArPlatform initialPlatform = FlutterArPlatform.instance;

  test('$MethodChannelFlutterAr is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFlutterAr>());
  });

  test('getPlatformVersion', () async {
    FlutterAr flutterArPlugin = FlutterAr();
    MockFlutterArPlatform fakePlatform = MockFlutterArPlatform();
    FlutterArPlatform.instance = fakePlatform;

    expect(await flutterArPlugin.getPlatformVersion(), '42');
  });
}
