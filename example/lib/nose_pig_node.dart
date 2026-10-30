import 'package:flutter/widgets.dart' show Color;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' show Quaternion, Vector3, Vector4;

/// 构建一个佩戴在追踪鼻尖上的小型程序化 3D 猪头。
///
/// 节点沿局部 +Z 方向构建鼻口，遵循 Flutter Scene 的前向轴约定。
/// [ArFaceAnchor] 会将 MediaPipe 人脸姿态转换到该坐标系，因此耳朵、眼睛、
/// 鼻口和嘴巴都会随人物一起转动，而不是始终朝向相机。
Node createNosePigNode({required double faceWidthMeters}) {
  final double width = (faceWidthMeters * 0.54).clamp(0.058, 0.105);
  final double height = width * 0.9;
  final double depth = width * 0.72;

  final Node root = Node(name: 'pig-at-nose');
  final Geometry sphere = SphereGeometry(radius: 0.5, segments: 32, rings: 16);
  final Geometry smallSphere = SphereGeometry(
    radius: 0.5,
    segments: 16,
    rings: 8,
  );
  final Geometry mouth = CuboidGeometry(
    Vector3(width * 0.34, width * 0.055, width * 0.03),
  );

  // 圆润的粉色头部。PBR 着色能让轮廓和表面法线在头部转动时清晰可见。
  root.add(
    _meshNode(
      name: 'pig-head',
      geometry: sphere,
      color: const Color(0xFFFFA6C4),
      scale: Vector3(width, height, depth),
      lit: true,
    ),
  );

  // 突出的鼻口是用户转动头部时最清晰的深度提示。
  final double snoutZ = depth * 0.48 + width * 0.17;
  root.add(
    _meshNode(
      name: 'pig-snout',
      geometry: sphere,
      color: const Color(0xFFFF4F8B),
      position: Vector3(0, -height * 0.08, snoutZ),
      scale: Vector3(width * 0.58, height * 0.43, width * 0.3),
      lit: true,
    ),
  );

  // 嘴巴位于鼻口下方，从四分之三侧面观察时仍然可见。
  root.add(
    _meshNode(
      name: 'pig-mouth',
      geometry: mouth,
      color: const Color(0xFF7E2444),
      position: Vector3(0, -height * 0.3, depth * 0.47),
    ),
  );

  for (final double side in <double>[-1, 1]) {
    // 白色眼球与前方的瞳孔都位于头部表面之外，
    // 避免被球体吞没并保持清晰可辨。
    root.add(
      _meshNode(
        name: side < 0 ? 'pig-eye-left' : 'pig-eye-right',
        geometry: smallSphere,
        color: const Color(0xFFFFFDF8),
        position: Vector3(side * width * 0.19, height * 0.13, depth * 0.48),
        scale: Vector3(width * 0.14, width * 0.16, width * 0.08),
      ),
    );
    root.add(
      _meshNode(
        name: side < 0 ? 'pig-pupil-left' : 'pig-pupil-right',
        geometry: smallSphere,
        color: const Color(0xFF24141A),
        position: Vector3(
          side * width * 0.19,
          height * 0.13,
          depth * 0.48 + width * 0.052,
        ),
        scale: Vector3.all(width * 0.06),
      ),
    );
    root.add(
      _meshNode(
        name: side < 0 ? 'pig-nostril-left' : 'pig-nostril-right',
        geometry: smallSphere,
        color: const Color(0xFF792141),
        position: Vector3(
          side * width * 0.12,
          -height * 0.12,
          snoutZ + width * 0.145,
        ),
        scale: Vector3(width * 0.075, width * 0.052, width * 0.03),
      ),
    );
    root.add(
      _meshNode(
        name: side < 0 ? 'pig-ear-left' : 'pig-ear-right',
        geometry: sphere,
        color: const Color(0xFFFF89B1),
        position: Vector3(side * width * 0.29, height * 0.34, 0),
        rotation: Quaternion.axisAngle(Vector3(0, 0, 1), side * 0.42),
        scale: Vector3(width * 0.22, height * 0.31, depth * 0.18),
        lit: true,
      ),
    );
  }
  return root;
}

Node _meshNode({
  required String name,
  required Geometry geometry,
  required Color color,
  Vector3? position,
  Quaternion? rotation,
  Vector3? scale,
  bool lit = false,
}) {
  final Vector4 rgba = Vector4(color.r, color.g, color.b, color.a);
  final Material material = lit
      ? (PhysicallyBasedMaterial()
          ..baseColorFactor = rgba
          ..roughnessFactor = 0.8)
      : (UnlitMaterial()..baseColorFactor = rgba);
  final Node node = Node(name: name)
    ..addComponent(MeshComponent(Mesh(geometry, material)));
  if (position != null) {
    node.position = position;
  }
  if (rotation != null) {
    node.rotation = rotation;
  }
  if (scale != null) {
    node.scale = scale;
  }
  return node;
}

/// 创建从 ARKit 脸部中心锚点偏移到鼻尖的猪头节点。
Node createNosePigNodeAtFaceCenter({required double faceWidthMeters}) {
  final Node node = createNosePigNode(faceWidthMeters: faceWidthMeters);
  node.position = Vector3(0, -faceWidthMeters * 0.16, faceWidthMeters * 0.5);
  return node;
}
