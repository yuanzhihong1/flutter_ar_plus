import 'dart:ui' show Size;

import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:flutter_ar_plus/src/ar_view_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('横屏方向保留相机的横向尺寸', () {
    expect(
      arCameraPreviewLayoutSize(
        const Size(1280, 720),
        DeviceOrientation.landscapeLeft,
      ),
      const Size(1280, 720),
    );
    expect(
      arCameraPreviewLayoutSize(
        const Size(640, 480),
        DeviceOrientation.landscapeRight,
      ),
      const Size(640, 480),
    );
  });

  test('竖屏方向旋转传感器尺寸', () {
    expect(
      arCameraPreviewLayoutSize(
        const Size(1280, 720),
        DeviceOrientation.portraitUp,
      ),
      const Size(720, 1280),
    );
    expect(
      arCameraPreviewLayoutSize(
        const Size(640, 480),
        DeviceOrientation.portraitDown,
      ),
      const Size(480, 640),
    );
  });

  test('保留空尺寸', () {
    expect(
      arCameraPreviewLayoutSize(Size.zero, DeviceOrientation.portraitUp),
      Size.zero,
    );
  });
}
