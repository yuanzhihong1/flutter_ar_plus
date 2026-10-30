import 'package:flutter_ar/ar_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('camera permission errors can open app settings', () {
    for (final ArViewErrorCode code in <ArViewErrorCode>[
      ArViewErrorCode.cameraPermissionDenied,
      ArViewErrorCode.cameraPermissionPermanentlyDenied,
      ArViewErrorCode.cameraPermissionRestricted,
    ]) {
      expect(ArViewException(code, 'denied').canOpenSettings, isTrue);
    }
  });

  test('non-permission errors do not offer app settings', () {
    for (final ArViewErrorCode code in ArViewErrorCode.values) {
      if (code == ArViewErrorCode.cameraPermissionDenied ||
          code == ArViewErrorCode.cameraPermissionPermanentlyDenied ||
          code == ArViewErrorCode.cameraPermissionRestricted) {
        continue;
      }
      expect(ArViewException(code, 'failed').canOpenSettings, isFalse);
    }
  });

  test('exception includes its machine-readable code in toString', () {
    const ArViewException error = ArViewException(
      ArViewErrorCode.cameraUnavailable,
      'No camera',
    );

    expect(error.toString(), contains('cameraUnavailable'));
    expect(error.toString(), contains('No camera'));
  });
}
