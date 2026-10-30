import 'package:flutter/widgets.dart' show Color;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' show Quaternion, Vector3, Vector4;

/// Builds a small procedural 3D pig head worn on the tracked nose.
///
/// The node is authored with its snout along local +Z, following Flutter
/// Scene's forward-axis convention. [ArFaceAnchor] converts the MediaPipe face
/// pose into that convention, so the ears, eyes, snout, and mouth turn with the
/// person instead of billboarding toward the camera.
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

  // Rounded pink head. PBR shading makes the silhouette and surface normal
  // visible as the head turns.
  root.add(
    _meshNode(
      name: 'pig-head',
      geometry: sphere,
      color: const Color(0xFFFFA6C4),
      scale: Vector3(width, height, depth),
      lit: true,
    ),
  );

  // The protruding snout is the clearest depth cue when the user turns.
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

  // Mouth sits below the snout and remains visible from a three-quarter view.
  root.add(
    _meshNode(
      name: 'pig-mouth',
      geometry: mouth,
      color: const Color(0xFF7E2444),
      position: Vector3(0, -height * 0.3, depth * 0.47),
    ),
  );

  for (final double side in <double>[-1, 1]) {
    // White eyeball plus a forward pupil. Both are outside the head surface so
    // they remain legible instead of being swallowed by the sphere.
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
