import 'package:flutter_ar/flutter_ar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('公开入口导出核心人脸姿态 API', () {
    const ArFacePoseMapper mapper = ArFacePoseMapper();

    expect(mapper.verticalFovDegrees, 63);
    expect(mapper.anchorOrigin, ArFaceAnchorOrigin.faceCenter);
  });

  test('公开入口导出错误回调类型', () {
    void onError(Object error, StackTrace stackTrace) {}

    final ArViewErrorCallback callback = onError;

    expect(callback, same(onError));
  });
}
