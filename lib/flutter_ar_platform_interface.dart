import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_ar_method_channel.dart';

abstract class FlutterArPlatform extends PlatformInterface {
  /// Constructs a FlutterArPlatform.
  FlutterArPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterArPlatform _instance = MethodChannelFlutterAr();

  /// The default instance of [FlutterArPlatform] to use.
  ///
  /// Defaults to [MethodChannelFlutterAr].
  static FlutterArPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutterArPlatform] when
  /// they register themselves.
  static set instance(FlutterArPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
