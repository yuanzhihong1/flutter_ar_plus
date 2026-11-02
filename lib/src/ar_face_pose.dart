import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/widgets.dart' show Offset, Size;
import 'package:mediapipe_face_mesh/mediapipe_face_mesh.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Quaternion, Vector3;

/// [ArView] 人脸锚点使用的坐标原点。
enum ArFaceAnchorOrigin {
  /// 将锚点放在鼻尖表面。
  ///
  /// 适合需要直接定位鼻部挂件的场景。默认值使用
  /// [ArFaceAnchorOrigin.faceCenter]。
  noseTip,

  /// 将锚点放在脸部中心。
  ///
  /// 这是 [ArView] 与 [ArFacePoseMapper] 的默认值。内容可使用相对脸部
  /// 中心的偏移来定位鼻子、眼睛或其他面部区域。
  faceCenter,
}

/// 用于放置 [ArView] 场景锚点的人脸姿态。
///
/// [transform] 是以米为单位的相机空间变换。相机位于原点并朝向 +Z，
/// +X 向右，+Y 向上。变换的平移分量使用米作为单位。
class ArFacePose {
  /// 创建一份已完成映射的人脸姿态数据。
  const ArFacePose({
    required this.transform,
    required this.rotation,
    required this.position,
    required this.screenPosition,
    required this.headPose,
    required this.distanceMeters,
    required this.faceWidthMeters,
  });

  /// 场景节点的完整相机空间变换，单位为米。
  final Matrix4 transform;

  /// 相机空间中的人脸旋转。
  final Quaternion rotation;

  /// 相机空间中的锚点位置，单位为米。
  ///
  /// [ArFaceAnchorOrigin.noseTip] 使用鼻尖位置，
  /// [ArFaceAnchorOrigin.faceCenter] 使用脸部中心位置。
  final Vector3 position;

  /// 锚点在归一化显示坐标中的位置，原点位于左上角。
  final Offset screenPosition;

  /// MediaPipe 估计的人脸头部旋转。
  final FaceMeshHeadPose headPose;

  /// 估计的脸部中心相机空间深度，单位为米。
  final double distanceMeters;

  /// 估计的脸颊两侧实际宽度，单位为米。
  final double faceWidthMeters;
}

/// 将 MediaPipe 人脸关键点映射到 [ArView] 使用的米制相机空间。
///
/// MediaPipe 的关键点坐标与姿态采用左上角为原点、朝向 +Z 的相机坐标系。
/// [ArView] 使用相同约定，因此这里的投影工作只需处理相机画面通过
/// `BoxFit.cover` 裁剪后产生的偏移。
///
/// 默认锚点原点为 [ArFaceAnchorOrigin.faceCenter]。
class ArFacePoseMapper {
  /// 创建使用指定垂直视场角 [verticalFovDegrees] 的映射器。
  const ArFacePoseMapper({
    this.verticalFovDegrees = 63,
    this.anchorOrigin = ArFaceAnchorOrigin.faceCenter,
  }) : assert(
         verticalFovDegrees > 0 && verticalFovDegrees < 180,
         'verticalFovDegrees 必须大于 0 且小于 180。',
       );

  /// 相机预览的垂直视场角，单位为度。
  final double verticalFovDegrees;

  /// 返回的相机空间锚点所使用的坐标原点。
  final ArFaceAnchorOrigin anchorOrigin;

  /// 将 [mesh] 映射为适用于 [viewportSize] 的相机空间锚点。
  ///
  /// 当网格不可用，或人脸投影宽度没有实际意义时返回 `null`。
  ArFacePose? map(FaceMeshResult mesh, {required Size viewportSize}) {
    if (viewportSize.width <= 0 || viewportSize.height <= 0) {
      return null;
    }
    final double imageWidth = mesh.imageWidth.toDouble();
    final double imageHeight = mesh.imageHeight.toDouble();
    if (imageWidth <= 0 || imageHeight <= 0) {
      return null;
    }
    if (mesh.landmarks.length <= 454) {
      return null;
    }

    Offset mapLandmark(int index) {
      return mesh.landmarkAsOffset(
        mesh.landmarks[index],
        targetSize: Size(imageWidth, imageHeight),
        clampToBounds: false,
      );
    }

    final double contentAspect = imageWidth / imageHeight;
    final double viewAspect = viewportSize.width / viewportSize.height;
    final double coverX = math.max(1.0, contentAspect / viewAspect);
    final double coverY = math.max(1.0, viewAspect / contentAspect);

    Offset toDisplay(Offset point) {
      final double x = (point.dx / imageWidth - 0.5) * coverX + 0.5;
      final double y = (point.dy / imageHeight - 0.5) * coverY + 0.5;
      return Offset(x, y);
    }

    final Offset nose = toDisplay(mapLandmark(1));
    final Offset leftFace = mapLandmark(234);
    final Offset rightFace = mapLandmark(454);
    final double projectedDx =
        (rightFace.dx - leftFace.dx) * viewportSize.width / imageWidth * coverX;
    final double projectedDy =
        (rightFace.dy - leftFace.dy) *
        viewportSize.height /
        imageHeight *
        coverY;
    final double projectedFaceWidth = math.sqrt(
      projectedDx * projectedDx + projectedDy * projectedDy,
    );
    final double projectedFraction = projectedFaceWidth / viewportSize.width;
    if (!projectedFraction.isFinite || projectedFraction < 0.01) {
      return null;
    }

    final FaceMeshGeometry geometry = mesh.estimateGeometry(
      verticalFovDegrees: verticalFovDegrees,
    );
    final double faceWidthMeters = math.max(
      geometry.distanceCm(234, 454) / 100.0,
      0.07,
    );
    final FaceMeshHeadPose headPose = geometry.headPose;
    final double yaw = headPose.yawDegrees * math.pi / 180.0;
    final double verticalFovRadians = verticalFovDegrees * math.pi / 180.0;
    final double tanHalfFov = math.tan(verticalFovRadians * 0.5);

    // 米制求解器已经给出真实的三维脸宽。这里只投影相机可见分量，
    // 否则转头会被误判为人脸远离相机。
    final double effectiveFaceWidth =
        faceWidthMeters * math.max(math.cos(yaw).abs(), 0.35);
    final double projectedDistance =
        effectiveFaceWidth /
        (2.0 * tanHalfFov * viewAspect * projectedFraction);
    final double solvedDistance =
        _cameraDepthMeters(geometry.poseTransformMatrix) ?? projectedDistance;
    final double distance = solvedDistance.clamp(0.12, 6.0).toDouble();

    // 关键点 1 位于鼻尖表面，而米制脸部中心在其后方数厘米处。
    // 将锚点保留在鼻尖表面，避免鼻部效果看起来陷进头部。
    final double noseDistance = math.max(
      0.08,
      distance - math.min(faceWidthMeters * 0.14, distance * 0.2),
    );
    final double halfHeightAtNose = tanHalfFov * noseDistance;
    final Vector3 nosePosition = Vector3(
      (nose.dx - 0.5) * 2.0 * halfHeightAtNose * viewAspect,
      (0.5 - nose.dy) * 2.0 * halfHeightAtNose,
      noseDistance,
    );

    final Quaternion rotation = contentRotationFromPoseTransform(
      geometry.poseTransformMatrix,
    );

    final Vector3 position;
    final Offset anchorScreenPosition;
    switch (anchorOrigin) {
      case ArFaceAnchorOrigin.noseTip:
        position = nosePosition;
        anchorScreenPosition = Offset(
          nose.dx.clamp(0.0, 1.0).toDouble(),
          nose.dy.clamp(0.0, 1.0).toDouble(),
        );
      case ArFaceAnchorOrigin.faceCenter:
        // 局部 +Z 轴由人脸指向相机。沿该轴从鼻尖表面向后移动，
        // 得到估计的脸部中心。
        final Vector3 towardCamera = rotation.rotated(Vector3(0, 0, 1));
        position = nosePosition - towardCamera * (distance - noseDistance);
        final double halfHeightAtCenter = tanHalfFov * distance;
        anchorScreenPosition = Offset(
          (position.x / (2.0 * halfHeightAtCenter * viewAspect) + 0.5)
              .clamp(0.0, 1.0)
              .toDouble(),
          (0.5 - position.y / (2.0 * halfHeightAtCenter))
              .clamp(0.0, 1.0)
              .toDouble(),
        );
    }

    return ArFacePose(
      transform: Matrix4.compose(position, rotation, Vector3(1.0, 1.0, 1.0)),
      rotation: rotation,
      position: position,
      screenPosition: anchorScreenPosition,
      headPose: headPose,
      distanceMeters: distance,
      faceWidthMeters: faceWidthMeters,
    );
  }

  double? _cameraDepthMeters(List<double> poseTransformMatrix) {
    if (poseTransformMatrix.length != 16) {
      return null;
    }
    // MediaPipe 运行时相机朝向 -Z，因此米制平移量的深度是 tz 的绝对值，
    // 单位为厘米。优先使用原生的几何求解结果，而不是根据投影宽度反推距离；
    // 前者在头部转动时更稳定。
    final double depthCm = poseTransformMatrix[11].abs();
    return depthCm.isFinite ? depthCm / 100.0 : null;
  }

  /// 将 MediaPipe 姿态矩阵转换为 Flutter Scene 内容旋转。
  ///
  /// MediaPipe 返回行主序的规范人脸到相机变换。转换结果遵循 Flutter Scene
  /// 内容局部 +Z 轴朝前的约定：静止时人脸正面朝向相机，头部偏航时内容
  /// 也会沿相同方向转动。
  @visibleForTesting
  Quaternion contentRotationFromPoseTransform(
    List<double> poseTransformMatrix,
  ) {
    if (poseTransformMatrix.length != 16) {
      return Quaternion.identity();
    }

    // pose_transform_matrix 将 MediaPipe 规范人脸坐标映射到相机空间，
    // 并包含统一缩放。这里提取归一化旋转，而不是手动重建欧拉角。
    final double scale = math.sqrt(
      poseTransformMatrix[0] * poseTransformMatrix[0] +
          poseTransformMatrix[4] * poseTransformMatrix[4] +
          poseTransformMatrix[8] * poseTransformMatrix[8],
    );
    if (!scale.isFinite || scale <= 1e-8) {
      return Quaternion.identity();
    }

    final Matrix4 poseRotation = Matrix4.identity();
    for (int row = 0; row < 3; row++) {
      for (int column = 0; column < 3; column++) {
        poseRotation.setEntry(
          row,
          column,
          poseTransformMatrix[row * 4 + column] / scale,
        );
      }
    }

    // MediaPipe 运行时相机朝向 -Z，而 Flutter Scene 相机朝向 +Z。
    // S 翻转相机空间 Z 轴，F 将内容左右约定映射到 MediaPipe 规范人脸轴。
    // 应用 S * R * F 后，偏航方向与头部一致，同时不会镜像俯仰。
    final Matrix4 contentRotation = Matrix4.diagonal3Values(1, 1, -1)
      ..multiply(poseRotation)
      ..multiply(Matrix4.diagonal3Values(-1, 1, 1));
    return Quaternion.fromRotation(contentRotation.getRotation()).normalized();
  }
}
