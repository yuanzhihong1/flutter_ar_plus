import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:flutter_ar_plus/flutter_ar_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediapipe_face_mesh/mediapipe_face_mesh.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  const ArFacePoseMapper mapper = ArFacePoseMapper();

  test('正面人脸使 Flutter Scene 内容朝向相机', () {
    final Quaternion rotation = mapper.contentRotationFromPoseTransform(
      _rowMajorYaw(0),
    );
    final Vector3 forward = _forwardFor(rotation);

    expect(forward.x, closeTo(0, 1e-6));
    expect(forward.y, closeTo(0, 1e-6));
    expect(forward.z, closeTo(-1, 1e-6));
  });

  test('人脸偏航时内容与头部同向转动', () {
    const double yawDegrees = 46;
    final Quaternion rotation = mapper.contentRotationFromPoseTransform(
      _rowMajorYaw(yawDegrees * math.pi / 180),
    );
    final Vector3 forward = _forwardFor(rotation);
    final double yaw = yawDegrees * math.pi / 180;

    expect(forward.x, closeTo(math.sin(yaw), 1e-6));
    expect(forward.y, closeTo(0, 1e-6));
    expect(forward.z, closeTo(-math.cos(yaw), 1e-6));
  });

  test('人脸俯仰时内容随头部上下转动', () {
    const double pitchRadians = 30 * math.pi / 180;
    final Quaternion lookingUp = mapper.contentRotationFromPoseTransform(
      _rowMajorPitch(-pitchRadians),
    );
    final Quaternion lookingDown = mapper.contentRotationFromPoseTransform(
      _rowMajorPitch(pitchRadians),
    );

    expect(_forwardFor(lookingUp).y, closeTo(math.sin(pitchRadians), 1e-6));
    expect(_forwardFor(lookingDown).y, closeTo(-math.sin(pitchRadians), 1e-6));
  });

  test('视口或图像不可用时返回 null', () {
    final FaceMeshResult mesh = _mesh(
      landmarkCount: 454,
      width: 640,
      height: 480,
    );

    expect(mapper.map(mesh, viewportSize: Size.zero), isNull);
    expect(
      mapper.map(
        _mesh(landmarkCount: 454, width: 0, height: 480),
        viewportSize: const Size(390, 844),
      ),
      isNull,
    );
    expect(mapper.map(mesh, viewportSize: const Size(390, 844)), isNull);
  });

  test('姿态矩阵格式错误时回退到单位旋转', () {
    for (final List<double> matrix in <List<double>>[
      List<double>.filled(15, 0),
      List<double>.filled(16, 0),
    ]) {
      final Quaternion rotation = mapper.contentRotationFromPoseTransform(
        matrix,
      );
      expect(rotation.x, closeTo(0, 1e-6));
      expect(rotation.y, closeTo(0, 1e-6));
      expect(rotation.z, closeTo(0, 1e-6));
      expect(rotation.w, closeTo(1, 1e-6));
    }
  });
}

FaceMeshResult _mesh({
  required int landmarkCount,
  required int width,
  required int height,
}) {
  return FaceMeshResult(
    landmarks: List<FaceMeshLandmark>.generate(
      landmarkCount,
      (int index) => FaceMeshLandmark(x: 0.5, y: 0.5, z: 0),
    ),
    rect: const NormalizedRect(
      xCenter: 0.5,
      yCenter: 0.5,
      width: 0.5,
      height: 0.5,
    ),
    score: 1,
    imageWidth: width,
    imageHeight: height,
  );
}

List<double> _rowMajorYaw(double radians) {
  final double c = math.cos(radians);
  final double s = math.sin(radians);
  return <double>[
    c, 0, s, 0, //
    0, 1, 0, 0, //
    -s, 0, c, 0, //
    0, 0, 0, 1, //
  ];
}

List<double> _rowMajorPitch(double radians) {
  final double c = math.cos(radians);
  final double s = math.sin(radians);
  return <double>[
    1, 0, 0, 0, //
    0, c, -s, 0, //
    0, s, c, 0, //
    0, 0, 0, 1, //
  ];
}

Vector3 _forwardFor(Quaternion rotation) {
  final Matrix4 transform = Matrix4.compose(
    Vector3.zero(),
    rotation,
    Vector3(1, 1, 1),
  );
  return transform.getColumn(2).xyz;
}
