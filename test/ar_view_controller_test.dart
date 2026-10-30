import 'package:flutter_ar/ar_view.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  late Scene scene;
  late ARViewController controller;

  setUp(() {
    scene = Scene();
    controller = ARViewController(scene: scene);
  });

  tearDown(() {
    scene.dispose();
  });

  test('ARView is the canonical constructor alias', () {
    final ARView view = ARView(scene: scene);
    expect(view.scene, same(scene));
  });

  test('adds a node with a camera-space transform', () {
    final Node node = Node(name: 'chair');

    expect(
      controller.addNode(
        node,
        position: Vector3(0.2, 0.1, 1.4),
        rotation: Quaternion.axisAngle(Vector3(0, 1, 0), 0.5),
        scale: Vector3.all(0.75),
      ),
      same(node),
    );

    expect(node.parent, same(scene.root));
    expect(node.position.x, closeTo(0.2, 1e-6));
    expect(node.position.y, closeTo(0.1, 1e-6));
    expect(node.position.z, closeTo(1.4, 1e-6));
    expect(node.scale.x, closeTo(0.75, 1e-6));
  });

  test('moves, locates, and removes a node', () {
    final Node node = controller.addNode(
      Node(name: 'lamp'),
      position: Vector3(0, 0, 1),
    );

    controller.moveNode(node, Vector3(0.25, -0.1, 0.2));
    expect(controller.nodeNamed('lamp'), same(node));
    expect(node.position.x, closeTo(0.25, 1e-6));
    expect(node.position.y, closeTo(-0.1, 1e-6));
    expect(node.position.z, closeTo(1.2, 1e-6));

    controller.setWorldPosition(node, Vector3(-0.4, 0.3, 2));
    final Vector3 worldPosition = controller.getWorldPosition(node);
    expect(worldPosition.x, closeTo(-0.4, 1e-6));
    expect(worldPosition.y, closeTo(0.3, 1e-6));
    expect(worldPosition.z, closeTo(2, 1e-6));

    controller.removeNode(node);
    expect(node.parent, isNull);
    expect(controller.nodeNamed('lamp'), isNull);
  });

  test('does not add a node to the scene twice', () {
    final Node node = controller.addNode(Node(name: 'once'));
    final int childCount = scene.root.children.length;

    controller.addNode(node, position: Vector3(0, 0, 1.5));

    expect(scene.root.children.length, childCount);
    expect(node.position.z, closeTo(1.5, 1e-6));
  });
}
