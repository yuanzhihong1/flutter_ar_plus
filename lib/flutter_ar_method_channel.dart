import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_ar_platform_interface.dart';

/// An implementation of [FlutterArPlatform] that uses method channels.
class MethodChannelFlutterAr extends FlutterArPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_ar');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
