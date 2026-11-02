import 'package:flutter/cupertino.dart';
import 'package:flutter_ar_plus/flutter_ar_plus.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

import 'face_image_test_page.dart';
import 'nose_pig_node.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

const bool _runFaceImageTest = bool.fromEnvironment('FACE_IMAGE_TEST');

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const CupertinoApp(
      debugShowCheckedModeBanner: false,
      home: _runFaceImageTest ? FaceImageTestPage() : ArDemoPage(),
    );
  }
}

class ArDemoPage extends StatefulWidget {
  const ArDemoPage({super.key});

  @override
  State<ArDemoPage> createState() => _ArDemoPageState();
}

class _ArDemoPageState extends State<ArDemoPage> {
  late final Scene _scene;
  late final ArViewController _arController;
  Node? _selectedModel;
  int _nextModelNumber = 1;

  @override
  void initState() {
    super.initState();
    _scene = Scene();
    _arController = ArViewController(scene: _scene);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _addModel();
      }
    });
  }

  @override
  void dispose() {
    _scene.dispose();
    super.dispose();
  }

  void _addModel() {
    final int number = _nextModelNumber++;
    final int index = number - 1;
    final Node model = createNosePigNode(faceWidthMeters: 0.32);
    _arController.addNode(
      model,
      name: 'scene-model-$number',
      position: Vector3(
        ((index % 3) - 1) * 0.16,
        ((index ~/ 3) % 2) * 0.09,
        1.0 + (index ~/ 6) * 0.12,
      ),
      scale: Vector3.all(1.6),
    );
    setState(() {
      _selectedModel = model;
    });
  }

  void _moveSelected(Vector3 offset) {
    final Node? model = _selectedModel;
    if (model == null) {
      return;
    }
    _arController.moveNode(model, offset);
    setState(() {});
  }

  void _removeSelected() {
    final Node? model = _selectedModel;
    if (model == null) {
      return;
    }
    _arController.removeNode(model);
    setState(() {
      _selectedModel = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ArView(
            scene: _scene,
            controller: _arController,
            delegate: const NosePigDelegate(),
            showTrackingIndicator: true,
          ),
          const IgnorePointer(
            child: SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: _DemoBadge(),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                child: _ModelPositionPanel(
                  position: _selectedModel?.position,
                  onAdd: _addModel,
                  onMove: _moveSelected,
                  onRemove: _selectedModel == null ? null : _removeSelected,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DemoBadge extends StatelessWidget {
  const _DemoBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xB3000000),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          '🐷  鼻尖 AR',
          style: TextStyle(
            color: Color(0xFFFFFFFF),
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ModelPositionPanel extends StatelessWidget {
  const _ModelPositionPanel({
    required this.position,
    required this.onAdd,
    required this.onMove,
    required this.onRemove,
  });

  final Vector3? position;
  final VoidCallback onAdd;
  final ValueChanged<Vector3> onMove;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final Vector3? selectedPosition = position;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xC7000000),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x33FFFFFF)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              selectedPosition == null
                  ? '添加一个 3D 模型到相机前方'
                  : '模型位置  '
                        'X ${selectedPosition.x.toStringAsFixed(2)}  '
                        'Y ${selectedPosition.y.toStringAsFixed(2)}  '
                        'Z ${selectedPosition.z.toStringAsFixed(2)}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFFFFFFF),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 9),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 7,
              runSpacing: 7,
              children: <Widget>[
                _ControlButton(label: '添加模型', onPressed: onAdd),
                _ControlButton(
                  label: 'X−',
                  onPressed: () => onMove(Vector3(-0.03, 0, 0)),
                ),
                _ControlButton(
                  label: 'X+',
                  onPressed: () => onMove(Vector3(0.03, 0, 0)),
                ),
                _ControlButton(
                  label: 'Y−',
                  onPressed: () => onMove(Vector3(0, -0.03, 0)),
                ),
                _ControlButton(
                  label: 'Y+',
                  onPressed: () => onMove(Vector3(0, 0.03, 0)),
                ),
                _ControlButton(
                  label: 'Z−',
                  onPressed: () => onMove(Vector3(0, 0, -0.03)),
                ),
                _ControlButton(
                  label: 'Z+',
                  onPressed: () => onMove(Vector3(0, 0, 0.03)),
                ),
                _ControlButton(
                  label: '删除',
                  onPressed: onRemove,
                  destructive: true,
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '把脸放入画面 · 鼻尖小猪会跟随头部',
              style: TextStyle(
                color: Color(0xCCFFFFFF),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.label,
    required this.onPressed,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: destructive
              ? const Color(0xCC7A2333)
              : const Color(0xCC3A3A3C),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          child: Text(
            label,
            style: TextStyle(
              color: enabled
                  ? const Color(0xFFFFFFFF)
                  : const Color(0x66FFFFFF),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// 从脸部中心锚点偏移并放置鼻尖小猪。
class NosePigDelegate extends ArViewDelegate {
  const NosePigDelegate();

  @override
  Node? nodeForFaceAnchor(ArView view, ArFaceAnchor anchor) {
    return createNosePigNodeAtFaceCenter(
      faceWidthMeters: anchor.faceWidthMeters,
    );
  }
}
