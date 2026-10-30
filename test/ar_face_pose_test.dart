import 'dart:math' as math;

import 'package:flutter_ar/ar_face_pose.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  const ArFacePoseMapper mapper = ArFacePoseMapper();

  test('frontal face points Flutter Scene content toward the camera', () {
    final Quaternion rotation = mapper.contentRotationFromPoseTransform(
      _rowMajorYaw(0),
    );
    final Vector3 forward = _forwardFor(rotation);

    expect(forward.x, closeTo(0, 1e-6));
    expect(forward.y, closeTo(0, 1e-6));
    expect(forward.z, closeTo(-1, 1e-6));
  });

  test('face yaw turns content in the same direction as the head', () {
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

  test('face pitch turns content up and down with the head', () {
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
