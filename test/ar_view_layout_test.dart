import 'dart:ui' show Size;

import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:flutter_ar/src/ar_view_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps landscape camera dimensions for landscape orientations', () {
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

  test('rotates sensor dimensions for portrait orientations', () {
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

  test('preserves empty dimensions', () {
    expect(
      arCameraPreviewLayoutSize(Size.zero, DeviceOrientation.portraitUp),
      Size.zero,
    );
  });
}
