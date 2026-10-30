import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_ar_platform_interface.dart';

/// 使用 MethodChannel 与原生平台通信的 [FlutterArPlatform] 实现。
class MethodChannelFlutterAr extends FlutterArPlatform {
  /// 用于与原生平台通信的方法通道。
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_ar');

  /// 通过方法通道获取当前原生平台的版本描述。
  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
