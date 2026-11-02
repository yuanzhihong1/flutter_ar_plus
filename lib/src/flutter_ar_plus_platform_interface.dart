import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_ar_plus_method_channel.dart';

/// 平台实现需要继承的 Flutter AR 平台接口。
abstract class FlutterArPlusPlatform extends PlatformInterface {
  /// 创建 FlutterArPlusPlatform。
  FlutterArPlusPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterArPlusPlatform _instance = MethodChannelFlutterArPlus();

  /// 默认使用的 [FlutterArPlusPlatform] 实例。
  ///
  /// 默认为 [MethodChannelFlutterArPlus]。
  static FlutterArPlusPlatform get instance => _instance;

  /// 平台相关实现应在注册时将其派生自 [FlutterArPlusPlatform] 的类设置为此值。
  static set instance(FlutterArPlusPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// 返回当前原生平台的版本描述。
  Future<String?> getPlatformVersion() {
    throw UnimplementedError('尚未实现 platformVersion()。');
  }
}
