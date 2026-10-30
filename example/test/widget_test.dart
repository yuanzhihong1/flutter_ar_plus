import 'package:flutter_ar_example/nose_pig_node.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final String? sceneSkipReason = _sceneSkipReason();

  test('场景节点层级保留名称', () {
    final Node root = Node(name: 'example-root')..add(Node(name: 'pig-child'));

    expect(root.name, 'example-root');
    expect(root.getChildByName('pig-child'), isNotNull);
  });

  test('从 ARKit 脸部中心偏移到鼻尖', () {
    final Node node = createNosePigNodeAtFaceCenter(faceWidthMeters: 0.15);

    expect(node.position.y, closeTo(-0.024, 1e-6));
    expect(node.position.z, closeTo(0.075, 1e-6));
  }, skip: sceneSkipReason);

  test('创建挂载在鼻尖上的三维猪头', () {
    final Node node = createNosePigNode(faceWidthMeters: 0.15);

    expect(node.name, 'pig-at-nose');
    expect(node.children.length, 11);
    expect(
      node.children.every(
        (Node child) => child.getComponents<MeshComponent>().length == 1,
      ),
      isTrue,
    );
    expect(
      node.children.map((Node child) => child.name),
      containsAll(<String>[
        'pig-head',
        'pig-snout',
        'pig-mouth',
        'pig-eye-left',
        'pig-eye-right',
        'pig-pupil-left',
        'pig-pupil-right',
        'pig-ear-left',
        'pig-ear-right',
      ]),
    );
  }, skip: sceneSkipReason);
}

String? _sceneSkipReason() {
  try {
    final Scene probe = Scene();
    probe.dispose();
    return null;
  } catch (_) {
    return 'Flutter Scene 需要 Flutter GPU，请运行 ../../tool/test.sh。';
  }
}
