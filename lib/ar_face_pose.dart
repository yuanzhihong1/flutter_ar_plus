import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/widgets.dart' show Offset, Size;
import 'package:mediapipe_face_mesh/mediapipe_face_mesh.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Quaternion, Vector3;

/// The face pose used to place a [ArView] scene anchor.
///
/// [transform] is a metric camera-space transform. The camera is at the
/// origin, looking toward +Z, with +X to the right and +Y up. The transform's
/// translation is the nose tip in meters.
class ArFacePose {
  const ArFacePose({
    required this.transform,
    required this.rotation,
    required this.position,
    required this.screenPosition,
    required this.headPose,
    required this.distanceMeters,
    required this.faceWidthMeters,
  });

  /// Full metric camera-space transform for a scene node.
  final Matrix4 transform;

  /// Head rotation in camera space.
  final Quaternion rotation;

  /// Nose-tip position in camera space, in meters.
  final Vector3 position;

  /// Nose position in normalized display coordinates, top-left origin.
  final Offset screenPosition;

  /// MediaPipe head rotation estimate.
  final FaceMeshHeadPose headPose;

  /// Estimated camera-space depth of the face center in meters.
  final double distanceMeters;

  /// Estimated physical cheek-to-cheek face width in meters.
  final double faceWidthMeters;
}

/// Maps MediaPipe face landmarks into the metric camera space used by [ArView].
///
/// MediaPipe's landmark coordinates and pose use a top-left-origin camera
/// looking down +Z. [ArView] uses the same convention, so the only projection
/// work here is accounting for the displayed camera image being cropped with
/// `BoxFit.cover` around the face.
class ArFacePoseMapper {
  /// Creates a mapper for a camera with [verticalFovDegrees].
  const ArFacePoseMapper({this.verticalFovDegrees = 63})
    : assert(
        verticalFovDegrees > 0 && verticalFovDegrees < 180,
        'verticalFovDegrees must be between 0 and 180.',
      );

  /// Vertical field of view of the camera preview, in degrees.
  final double verticalFovDegrees;

  /// Maps [mesh] to a camera-space anchor for [viewportSize].
  ///
  /// Returns `null` when the mesh is not usable or the face has no meaningful
  /// projected width.
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

    // The metric solver already reports a true 3D face width. Project only the
    // component visible to the camera, otherwise a turned head is mistaken for
    // a face that moved farther away.
    final double effectiveFaceWidth =
        faceWidthMeters * math.max(math.cos(yaw).abs(), 0.35);
    final double projectedDistance =
        effectiveFaceWidth /
        (2.0 * tanHalfFov * viewAspect * projectedFraction);
    final double solvedDistance =
        _cameraDepthMeters(geometry.poseTransformMatrix) ?? projectedDistance;
    final double distance = solvedDistance.clamp(0.12, 6.0).toDouble();

    // Landmark 1 is on the nose surface; the metric face center is several
    // centimetres behind it. Keep the anchor on that surface to avoid making
    // a nose effect look sunk into the head.
    final double noseDistance = math.max(
      0.08,
      distance - math.min(faceWidthMeters * 0.14, distance * 0.2),
    );
    final double halfHeightAtNose = tanHalfFov * noseDistance;
    final Vector3 position = Vector3(
      (nose.dx - 0.5) * 2.0 * halfHeightAtNose * viewAspect,
      (0.5 - nose.dy) * 2.0 * halfHeightAtNose,
      noseDistance,
    );

    final Quaternion rotation = contentRotationFromPoseTransform(
      geometry.poseTransformMatrix,
    );

    return ArFacePose(
      transform: Matrix4.compose(position, rotation, Vector3(1.0, 1.0, 1.0)),
      rotation: rotation,
      position: position,
      screenPosition: Offset(
        nose.dx.clamp(0.0, 1.0).toDouble(),
        nose.dy.clamp(0.0, 1.0).toDouble(),
      ),
      headPose: headPose,
      distanceMeters: distance,
      faceWidthMeters: faceWidthMeters,
    );
  }

  double? _cameraDepthMeters(List<double> poseTransformMatrix) {
    if (poseTransformMatrix.length != 16) {
      return null;
    }
    // MediaPipe's runtime camera looks down -Z, so the metric translation's
    // depth is abs(tz) in centimetres. Prefer it over deriving distance from
    // projected width; it is the native geometry solve and stays stable while
    // the head turns.
    final double depthCm = poseTransformMatrix[11].abs();
    return depthCm.isFinite ? depthCm / 100.0 : null;
  }

  /// Converts a MediaPipe pose matrix into a Flutter Scene content rotation.
  ///
  /// MediaPipe returns a row-major canonical-face-to-camera transform. The
  /// resulting rotation preserves the Flutter Scene convention that content's
  /// local +Z axis is forward: at rest the face-front direction points toward
  /// the camera, and yaw turns it in the same direction as the tracked head.
  @visibleForTesting
  Quaternion contentRotationFromPoseTransform(
    List<double> poseTransformMatrix,
  ) {
    if (poseTransformMatrix.length != 16) {
      return Quaternion.identity();
    }

    // pose_transform_matrix maps MediaPipe's canonical face coordinates into
    // camera space and includes a uniform scale. Extract the normalized
    // rotation instead of rebuilding Euler angles by hand.
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

    // MediaPipe's runtime camera looks down -Z, while Flutter Scene's camera
    // looks down +Z. S flips the camera-space Z axis, while F maps content's
    // left/right convention onto MediaPipe's canonical face axes. Applying
    // S * R * F keeps yaw in the same direction as the head without mirroring
    // its pitch.
    final Matrix4 contentRotation = Matrix4.diagonal3Values(1, 1, -1)
      ..multiply(poseRotation)
      ..multiply(Matrix4.diagonal3Values(-1, 1, 1));
    return Quaternion.fromRotation(contentRotation.getRotation()).normalized();
  }
}
