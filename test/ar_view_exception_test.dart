import 'package:flutter_ar_plus/flutter_ar_plus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('相机权限错误可以打开应用设置', () {
    for (final ArViewErrorCode code in <ArViewErrorCode>[
      ArViewErrorCode.cameraPermissionDenied,
      ArViewErrorCode.cameraPermissionPermanentlyDenied,
      ArViewErrorCode.cameraPermissionRestricted,
    ]) {
      expect(ArViewException(code, '已拒绝').canOpenSettings, isTrue);
    }
  });

  test('非权限错误不提供应用设置入口', () {
    for (final ArViewErrorCode code in ArViewErrorCode.values) {
      if (code == ArViewErrorCode.cameraPermissionDenied ||
          code == ArViewErrorCode.cameraPermissionPermanentlyDenied ||
          code == ArViewErrorCode.cameraPermissionRestricted) {
        continue;
      }
      expect(ArViewException(code, '失败').canOpenSettings, isFalse);
    }
  });

  test('异常文本包含可供程序判断的错误码', () {
    const ArViewException error = ArViewException(
      ArViewErrorCode.cameraUnavailable,
      '没有相机',
    );

    expect(error.toString(), contains('cameraUnavailable'));
    expect(error.toString(), contains('没有相机'));
  });
}
