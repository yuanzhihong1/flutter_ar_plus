import 'package:camera/camera.dart';
import 'package:flutter_ar/flutter_ar.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final String? sceneSkipReason = _sceneSkipReason();
  late Scene scene;
  late ArViewController controller;

  setUp(() {
    scene = Scene();
    controller = ArViewController(scene: scene);
  });

  tearDown(() {
    scene.dispose();
  });

  test('ArView 使用与 ARKit 一致的默认参数', () {
    final ArView view = ArView(scene: scene);
    expect(view.scene, same(scene));
    expect(view.faceAnchorOrigin, ArFaceAnchorOrigin.faceCenter);
    expect(view.preferredFramesPerSecond, 60);
    expect(view.cameraResolution, ResolutionPreset.high);
    expect(view.enableFaceBlendshapes, isTrue);
  }, skip: sceneSkipReason);

  test('未挂载时状态查询返回安全值', () {
    expect(controller.isAttached, isFalse);
    expect(controller.isTracking, isFalse);
    expect(controller.currentFaceAnchor, isNull);
  }, skip: sceneSkipReason);

  test('使用相机空间变换添加节点', () {
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
  }, skip: sceneSkipReason);

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
  }, skip: sceneSkipReason);

  test('does not add a node to the scene twice', () {
    final Node node = controller.addNode(Node(name: 'once'));
    final int childCount = scene.root.children.length;

    controller.addNode(node, position: Vector3(0, 0, 1.5));

    expect(scene.root.children.length, childCount);
    expect(node.position.z, closeTo(1.5, 1e-6));
  }, skip: sceneSkipReason);

  test('rejects a node owned by another scene', () {
    final Scene otherScene = Scene();
    addTearDown(otherScene.dispose);
    final Node node = Node(name: 'foreign');
    otherScene.add(node);

    expect(() => controller.addNode(node), throwsArgumentError);
    expect(node.parent, same(otherScene.root));
  }, skip: sceneSkipReason);

  test('为匿名节点生成名称并清理显式名称', () {
    final Node anonymous = controller.addNode(Node());
    final Node named = controller.addNode(Node(), name: '  camera-prop  ');

    expect(anonymous.name, 'ar_node_1');
    expect(named.name, 'camera-prop');
  }, skip: sceneSkipReason);
}

String? _sceneSkipReason() {
  try {
    final Scene probe = Scene();
    probe.dispose();
    return null;
  } catch (_) {
    return 'Flutter Scene 需要 Flutter GPU，请运行 ./tool/test.sh。';
  }
}
