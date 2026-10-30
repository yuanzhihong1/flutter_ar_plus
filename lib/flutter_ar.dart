
import 'flutter_ar_platform_interface.dart';

class FlutterAr {
  Future<String?> getPlatformVersion() {
    return FlutterArPlatform.instance.getPlatformVersion();
  }
}
