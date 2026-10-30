import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_ar/flutter_ar.dart';
import 'package:flutter_scene/scene.dart';
import 'package:mediapipe_face_mesh/face_mesh_painter.dart';
import 'package:mediapipe_face_mesh/mediapipe_face_mesh.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

import 'nose_pig_node.dart';

/// Runs MediaPipe Face Mesh against a bundled still image.
///
/// Launch the example with `--dart-define=FACE_IMAGE_TEST=true` to isolate
/// tracking correctness from the live camera.
class FaceImageTestPage extends StatefulWidget {
  const FaceImageTestPage({super.key});

  @override
  State<FaceImageTestPage> createState() => _FaceImageTestPageState();
}

class _FaceImageTestPageState extends State<FaceImageTestPage> {
  static const String _asset = 'assets/face_test.jpg';
  static const Size _fallbackImageSize = Size(1144, 1024);

  Uint8List? _imageBytes;
  Size _imageSize = _fallbackImageSize;
  late final Scene _scene;
  FaceMeshInferenceResult? _inference;
  ArFacePose? _pose;
  Node? _pigNode;
  String _status = 'Waiting to run';
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _scene = Scene();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runTest();
    });
  }

  @override
  void dispose() {
    _scene.dispose();
    super.dispose();
  }

  Future<void> _runTest() async {
    if (_running) return;
    setState(() {
      _running = true;
      _status = 'Loading image and MediaPipe models…';
      _inference = null;
    });

    FaceDetectorProcessor? detector;
    FaceMeshProcessor? meshProcessor;
    ui.Image? decodedImage;
    try {
      final ByteData assetData = await rootBundle.load(_asset);
      _imageBytes = assetData.buffer.asUint8List(
        assetData.offsetInBytes,
        assetData.lengthInBytes,
      );

      final ui.Codec codec = await ui.instantiateImageCodec(_imageBytes!);
      final ui.FrameInfo frame = await codec.getNextFrame();
      decodedImage = frame.image;
      final ByteData? rgba = await decodedImage.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (rgba == null) {
        throw StateError('Could not decode image pixels.');
      }

      detector = await FaceDetectorProcessor.create(
        model: FaceDetectionModel.shortRange,
        delegate: FaceMeshDelegate.xnnpack,
      );
      meshProcessor = await FaceMeshProcessor.create(
        model: FaceMeshModel.v2,
        delegate: FaceMeshDelegate.xnnpack,
      );
      final FaceMeshInferencePipeline pipeline = FaceMeshInferencePipeline(
        detector: detector,
        mesh: meshProcessor,
      );

      final Stopwatch stopwatch = Stopwatch()..start();
      final FaceMeshInferenceResult inference = pipeline.process(
        FaceMeshImage(
          pixels: rgba.buffer.asUint8List(
            rgba.offsetInBytes,
            rgba.lengthInBytes,
          ),
          width: decodedImage.width,
          height: decodedImage.height,
          bytesPerRow: decodedImage.width * 4,
          pixelFormat: FaceMeshPixelFormat.rgba,
        ),
      );
      stopwatch.stop();

      final FaceMeshResult? mesh = inference.meshResult;
      if (mesh == null || mesh.landmarks.isEmpty) {
        throw StateError('MediaPipe did not detect a face in $_asset.');
      }
      final FaceMeshGeometry geometry = mesh.estimateGeometry(
        verticalFovDegrees: 63.0,
      );
      final FaceMeshMeasurements measurements = geometry.measurements;
      final double imageAspect = mesh.imageWidth / mesh.imageHeight;
      final ArFacePose? pose = const ArFacePoseMapper().map(
        mesh,
        viewportSize: Size(1000, 1000 / imageAspect),
      );
      if (pose == null) {
        throw StateError(
          'Could not map the detected face into AR camera space.',
        );
      }

      _logResult(
        inference: inference,
        mesh: mesh,
        geometry: geometry,
        measurements: measurements,
        arPose: pose,
        elapsed: stopwatch.elapsed,
      );

      if (!mounted) return;
      final Node? oldPig = _pigNode;
      if (oldPig != null) {
        _scene.remove(oldPig);
      }
      final Node pig = createNosePigNode(faceWidthMeters: pose.faceWidthMeters)
        ..localTransform = pose.transform;
      _scene.add(pig);
      setState(() {
        _imageSize = Size(
          mesh.imageWidth.toDouble(),
          mesh.imageHeight.toDouble(),
        );
        _inference = inference;
        _pose = pose;
        _pigNode = pig;
        _status =
            'OK · ${mesh.landmarks.length} landmarks · '
            'mesh ${geometry.metricLandmarks.length} points · '
            'face width ${measurements.faceWidth.valueCm.toStringAsFixed(1)} cm · '
            'anchor ${pose.position.z.toStringAsFixed(2)} m · '
            '${stopwatch.elapsedMilliseconds} ms';
      });
    } catch (error, stackTrace) {
      debugPrint('[FACE_IMAGE_TEST] FAILED: $error\n$stackTrace');
      if (mounted) {
        setState(() {
          _status = 'FAILED · $error';
        });
      }
    } finally {
      detector?.close();
      meshProcessor?.close();
      decodedImage?.dispose();
      if (mounted) {
        setState(() {
          _running = false;
        });
      }
    }
  }

  void _logResult({
    required FaceMeshInferenceResult inference,
    required FaceMeshResult mesh,
    required FaceMeshGeometry geometry,
    required FaceMeshMeasurements measurements,
    required ArFacePose arPose,
    required Duration elapsed,
  }) {
    final FaceMeshHeadPose headPose = geometry.headPose;
    final FaceMeshMetricPoint metricNose = geometry.metricLandmarks[1];
    final List<double> matrix = geometry.poseTransformMatrix;
    final String message =
        '[FACE_IMAGE_TEST] OK '
        'image=${mesh.imageWidth}x${mesh.imageHeight} '
        'detections=${inference.detectionResult?.detections.length ?? 0} '
        'landmarks=${mesh.landmarks.length} '
        'iris=${mesh.hasIris} '
        'metricLandmarks=${geometry.metricLandmarks.length} '
        'score=${mesh.score.toStringAsFixed(4)} '
        'headPose=(${headPose.yawDegrees.toStringAsFixed(2)},'
        '${headPose.pitchDegrees.toStringAsFixed(2)},'
        '${headPose.rollDegrees.toStringAsFixed(2)}) '
        'faceWidthCm=${measurements.faceWidth.valueCm.toStringAsFixed(2)} '
        'faceHeightCm=${measurements.faceHeight.valueCm.toStringAsFixed(2)} '
        'interpupillaryCm=${measurements.interpupillaryDistance?.valueCm.toStringAsFixed(2)} '
        'metricNose=(${metricNose.xCm.toStringAsFixed(2)},'
        '${metricNose.yCm.toStringAsFixed(2)},'
        '${metricNose.zCm.toStringAsFixed(2)}) '
        'poseTranslationCm=(${matrix[3].toStringAsFixed(2)},'
        '${matrix[7].toStringAsFixed(2)},'
        '${matrix[11].toStringAsFixed(2)}) '
        'arPositionM=(${arPose.position.x.toStringAsFixed(3)},'
        '${arPose.position.y.toStringAsFixed(3)},'
        '${arPose.position.z.toStringAsFixed(3)}) '
        'arDistanceM=${arPose.distanceMeters.toStringAsFixed(3)} '
        'arScreen=(${arPose.screenPosition.dx.toStringAsFixed(3)},'
        '${arPose.screenPosition.dy.toStringAsFixed(3)}) '
        'elapsed=${elapsed.inMilliseconds}ms';
    debugPrint(message);
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      child: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: <Widget>[
                  const Expanded(
                    child: Text(
                      'MediaPipe Face Mesh · image test',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    onPressed: _running ? null : _runTest,
                    child: const Text('Run'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: _imageSize.width / _imageSize.height,
                  child: LayoutBuilder(
                    builder:
                        (BuildContext context, BoxConstraints constraints) {
                          final ArFacePose? pose = _pose;
                          return Stack(
                            fit: StackFit.expand,
                            children: <Widget>[
                              if (_imageBytes != null)
                                Image.memory(_imageBytes!, fit: BoxFit.contain)
                              else
                                const ColoredBox(color: Color(0xFF202020)),
                              if (pose != null)
                                IgnorePointer(
                                  child: SceneView(
                                    _scene,
                                    maxFrameRate: 30,
                                    camera: PerspectiveCamera(
                                      fovRadiansY: 63 * 3.141592653589793 / 180,
                                      position: Vector3.zero(),
                                      target: Vector3(0, 0, 1),
                                      up: Vector3(0, 1, 0),
                                      fovNear: 0.02,
                                      fovFar: 20,
                                    ),
                                    loadingBuilder: (
                                      BuildContext context,
                                      double progress,
                                    ) => const SizedBox.shrink(),
                                  ),
                                ),
                              if (_inference != null)
                                IgnorePointer(
                                  child: CustomPaint(
                                    painter: FaceMeshPainter.fromInference(
                                      _inference!,
                                      drawDots: true,
                                      scaleWithFace: true,
                                    ),
                                  ),
                                ),
                              if (pose != null)
                                Positioned(
                                  left:
                                      constraints.maxWidth *
                                          pose.screenPosition.dx -
                                      9,
                                  top:
                                      constraints.maxHeight *
                                          pose.screenPosition.dy -
                                      9,
                                  child: const IgnorePointer(
                                    child: _NoseTarget(),
                                  ),
                                ),
                            ],
                          );
                        },
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (_running) const CupertinoActivityIndicator(),
                  if (_running) const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _status,
                      style: const TextStyle(fontSize: 13, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoseTarget extends StatelessWidget {
  const _NoseTarget();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 18,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF00E5FF), width: 2),
          color: const Color(0x3300E5FF),
        ),
      ),
    );
  }
}
