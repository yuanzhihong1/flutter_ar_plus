import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:flutter/services.dart' show DeviceOrientation;

/// 返回 [CameraPreview] 所需的、保持宽高比的外层尺寸。
///
/// 相机后端始终以横向报告传感器尺寸。`CameraPreview` 会在竖屏设备方向下
/// 旋转纹理，因此外层容器必须使用相同方向，而不能直接采用原始传感器尺寸。
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
