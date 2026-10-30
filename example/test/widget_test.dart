import 'package:flutter_ar_example/nose_pig_node.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('creates a three-dimensional pig head attached at the nose', () {
    final Node node = createNosePigNode(faceWidthMeters: 0.15);

    expect(node.name, 'pig-at-nose');
    expect(node.children.length, 13);
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
  });
}
