import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:flutter/services.dart' show DeviceOrientation;

/// Returns the aspect-correct size consumed by [CameraPreview].
///
/// Camera backends report the sensor dimensions in landscape. `CameraPreview`
/// rotates the texture for portrait device orientations, so its outer box must
/// use the same orientation instead of forcing the raw sensor dimensions.
Size arCameraPreviewLayoutSize(
  Size previewSize,
  DeviceOrientation orientation,
) {
  if (previewSize.isEmpty) {
    return previewSize;
  }
  final double shortSide = math.min(previewSize.width, previewSize.height);
  final double longSide = math.max(previewSize.width, previewSize.height);
  final bool landscape =
      orientation == DeviceOrientation.landscapeLeft ||
      orientation == DeviceOrientation.landscapeRight;
  return landscape ? Size(longSide, shortSide) : Size(shortSide, longSide);
}
