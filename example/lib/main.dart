import 'package:camera/camera.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_ar/ar_view.dart';
import 'package:flutter_scene/scene.dart';

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

  @override
  void initState() {
    super.initState();
    _scene = Scene();
  }

  @override
  void dispose() {
    _scene.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ArView(
            scene: _scene,
            delegate: const NosePigDelegate(),
            preferredFramesPerSecond: 30,
            cameraResolution: ResolutionPreset.medium,
            showsStatistics: true,
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
          const IgnorePointer(
            child: SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(24, 0, 24, 28),
                  child: Text(
                    '把脸放入画面 · 🐷 会贴在鼻尖并跟随头部',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFFFFFFFF),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      shadows: <Shadow>[
                        Shadow(color: Color(0xCC000000), blurRadius: 8),
                      ],
                    ),
                  ),
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
          '🐷  Nose AR',
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

/// Places a widget-rendered pig emoji at the tracked nose anchor.
class NosePigDelegate extends ArViewDelegate {
  const NosePigDelegate();

  @override
  Node? nodeForFaceAnchor(ArView view, ArFaceAnchor anchor) {
    return createNosePigNode(faceWidthMeters: anchor.faceWidthMeters);
  }
}
