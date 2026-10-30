// SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_ar/flutter_ar.dart';
import 'package:flutter_scene/scene.dart';
import 'package:image/image.dart' as image;
import 'package:mediapipe_face_mesh/mediapipe_face_mesh.dart';
import 'package:vector_math/vector_math.dart' show Quaternion, Vector3, Vector4;

/// Which overlay the AR view renders at the tracked face.
enum StackChanDecoration {
  /// No face-attached content.
  none,

  /// The StackChan GLB plus its animated expression display.
  stackChan,

  /// The emoji pig nose used by the second iOS decoration mode.
  nose,
}

/// Controls the Flutter counterpart of the iOS `StackChanArView` platform view.
///
/// The controller can be created before the widget is mounted and can emit
/// events before a listener subscribes because the streams are broadcast.
class StackChanArController {
  /// Creates a controller with the same decoration values as the iOS view.
  StackChanArController({
    this.decoration = StackChanDecoration.none,
    this.captureScreen = false,
  });

  /// Current decoration mode.
  StackChanDecoration decoration;

  /// Whether snapshots are emitted through [frames].
  bool captureScreen;

  final StreamController<String> _expressions =
      StreamController<String>.broadcast();
  final StreamController<Uint8List> _frames =
      StreamController<Uint8List>.broadcast();

  _StackChanArViewState? _view;
  bool _disposed = false;

  /// JSON payloads equivalent to the iOS `_expression` event channel.
  ///
  /// A payload is emitted at most twice per second, matching the 0.5 second
  /// throttle in the iOS implementation.
  Stream<String> get expressions => _expressions.stream;

  /// Center-cropped 320x240 JPEG snapshots, matching the iOS frame channel.
  Stream<Uint8List> get frames => _frames.stream;

  /// Changes the active decoration, equivalent to iOS `setDecorate`.
  void setDecorate(StackChanDecoration value) {
    if (_disposed || decoration == value) {
      return;
    }
    decoration = value;
    _view?._applyDecoration(value);
  }

  /// Integer compatibility helper for the iOS `setDecorate` arguments.
  ///
  /// 0 = none, 1 = StackChan, 2 = pig nose.
  void setDecorateIndex(int value) {
    setDecorate(switch (value) {
      0 => StackChanDecoration.none,
      1 => StackChanDecoration.stackChan,
      2 => StackChanDecoration.nose,
      _ => StackChanDecoration.none,
    });
  }

  /// Enables or disables frame delivery, equivalent to `setCaptureScreen`.
  void setCaptureScreen(bool value) {
    if (_disposed || captureScreen == value) {
      return;
    }
    captureScreen = value;
    _view?._applyCaptureScreen(value);
  }

  void _emitExpression(String payload) {
    if (!_disposed && _expressions.hasListener) {
      _expressions.add(payload);
    }
  }

  void _emitFrame(Uint8List bytes) {
    if (!_disposed && _frames.hasListener) {
      _frames.add(bytes);
    }
  }

  void _attach(_StackChanArViewState view) {
    final _StackChanArViewState? attached = _view;
    if (attached != null && !identical(attached, view)) {
      throw StateError(
        'StackChanArController is already attached to another view.',
      );
    }
    _view = view;
  }

  void _detach(_StackChanArViewState view) {
    if (identical(_view, view)) {
      _view = null;
    }
  }

  /// Closes the event streams. The widget closes a controller it created.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _view = null;
    await _expressions.close();
    await _frames.close();
  }
}

/// A face-attached StackChan AR example backed by [ARView].
///
/// This is the Flutter equivalent of the iOS `StackChanArView`:
/// - the GLB and expression display follow the tracked face,
/// - decoration mode 0/1/2 maps to none/StackChan/pig nose,
/// - expression JSON is emitted every 500 ms,
/// - optional center-cropped 320x240 JPEG snapshots are emitted every 500 ms.
class StackChanArView extends StatefulWidget {
  /// Creates the StackChan AR view.
  const StackChanArView({
    super.key,
    this.controller,
    this.initialDecoration = StackChanDecoration.stackChan,
    this.showControls = true,
    this.showTrackingBadge = true,
    this.showsStatistics = false,
    this.modelAsset = 'assets/stack_chan_model.glb',
    this.cameraResolution = ResolutionPreset.medium,
    this.preferredFramesPerSecond = 30,
  });

  /// Optional external controller. The caller owns its lifetime.
  final StackChanArController? controller;

  /// Decoration used when [controller] is omitted.
  final StackChanDecoration initialDecoration;

  /// Whether to show the in-app decoration and capture controls.
  final bool showControls;

  /// Whether to show the live face-tracking badge.
  final bool showTrackingBadge;

  /// Whether [ARView] displays its tracking/FPS statistics.
  final bool showsStatistics;

  /// Runtime glTF binary used for decoration mode 1.
  final String modelAsset;

  /// Camera resolution requested from [ARView].
  final ResolutionPreset cameraResolution;

  /// Preferred camera, inference, and render rate.
  final int preferredFramesPerSecond;

  @override
  State<StackChanArView> createState() => _StackChanArViewState();
}

class _StackChanArViewState extends State<StackChanArView> {
  static const int _captureWidth = 320;
  static const int _captureHeight = 240;
  static const Duration _eventInterval = Duration(milliseconds: 500);

  // These are the offsets used by the iOS StackChanArView. They are relative
  // to ARKit's face-center anchor, which is selected below.
  static final Vector3 _modelOffset = Vector3(0, 0.03, 0);
  static final Vector3 _faceScreenOffset = Vector3(0, 0.03, 0.07);
  static final Vector3 _noseOffset = Vector3(0, 0, 0.07);
  static const double _modelScale = 0.004;

  final GlobalKey _captureBoundaryKey = GlobalKey();
  final ValueNotifier<StackChanExpressionData> _expression =
      ValueNotifier<StackChanExpressionData>(StackChanExpressionData.neutral());

  late final Scene _scene;
  late final ARViewController _arController;
  late StackChanArController _controller;
  late bool _ownsController;
  late _StackChanFaceDelegate _delegate;
  late Future<Node> _modelFuture;

  Timer? _captureTimer;
  bool _captureInFlight = false;
  bool _faceTracked = false;
  bool _modelLoaded = false;
  String? _modelError;
  DateTime _lastExpressionSent = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _scene = Scene();
    _arController = ARViewController(scene: _scene);
    _attachController(widget.controller);
    _modelFuture = _loadStackChanModel();
    unawaited(
      _modelFuture.then<void>(
        (_) {
          if (mounted) {
            setState(() {
              _modelLoaded = true;
            });
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!mounted) {
            return;
          }
          setState(() {
            _modelError = error.toString();
          });
        },
      ),
    );
    _delegate = _StackChanFaceDelegate(
      modelFuture: _modelFuture,
      expression: _expression,
      onFaceUpdated: _handleFaceUpdated,
      onFaceRemoved: _handleFaceRemoved,
    );
    _delegate.decoration = _controller.decoration;
    _applyCaptureScreen(_controller.captureScreen);
  }

  @override
  void didUpdateWidget(StackChanArView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _controller._detach(this);
      if (_ownsController) {
        unawaited(_controller.dispose());
      }
      _attachController(widget.controller);
      _delegate.applyDecoration(_controller.decoration);
      _applyCaptureScreen(_controller.captureScreen);
    }
  }

  void _attachController(StackChanArController? requested) {
    _ownsController = requested == null;
    _controller =
        requested ??
        StackChanArController(decoration: widget.initialDecoration);
    _controller._attach(this);
  }

  Future<Node> _loadStackChanModel() async {
    final Node model = await Node.fromGlbAsset(
      widget.modelAsset,
      maxTextureSize: 1024,
    );
    model.name = 'StackChanModel';
    model.scale = Vector3.all(_modelScale);

    // Rotate the imported model +90 degrees around its local Y axis so the
    // face is upright and the display side follows the tracked face.
    final Node modelNode = model.getChildByName('StackChanModel') ?? model;
    modelNode.rotation = Quaternion.axisAngle(Vector3(0, 1, 0), math.pi);

    // These are the two body sections hidden by the iOS sample.
    model.getChildByName('_00_stackchan450_3')?.visible = false;
    model.getChildByName('_00_stackchan450_2')?.visible = false;
    _setTreeOpacity(model, 0.4);
    return model;
  }

  void _setTreeOpacity(Node node, double opacity) {
    for (final MeshComponent component in node.getComponents<MeshComponent>()) {
      for (final MeshPrimitive primitive in component.mesh.primitives) {
        final Material material = primitive.material;
        if (material is PhysicallyBasedMaterial) {
          final Vector4 color = material.baseColorFactor;
          material.baseColorFactor = Vector4(
            color.x,
            color.y,
            color.z,
            opacity,
          );
          material.alphaMode = AlphaMode.blend;
        }
      }
    }
    for (final Node child in node.children) {
      _setTreeOpacity(child, opacity);
    }
  }

  void _handleFaceUpdated(ArFaceAnchor anchor) {
    final StackChanExpressionData data = StackChanExpressionData.fromAnchor(
      anchor,
    );
    _expression.value = data;

    if (!_faceTracked) {
      setState(() {
        _faceTracked = true;
      });
    }

    final DateTime now = DateTime.now();
    if (now.difference(_lastExpressionSent) < _eventInterval) {
      return;
    }
    _lastExpressionSent = now;
    _controller._emitExpression(
      StackChanDanceData(
        leftEye: data.leftEye,
        rightEye: data.rightEye,
        mouth: data.mouth,
        yawServo: StackChanMotionData.fromYaw(anchor.headPose.yawDegrees),
        pitchServo: StackChanMotionData.fromPitch(anchor.headPose.pitchDegrees),
        durationMs: 1000,
      ).toJsonString(),
    );
  }

  void _handleFaceRemoved(ArFaceAnchor anchor) {
    if (!mounted || !_faceTracked) {
      return;
    }
    setState(() {
      _faceTracked = false;
    });
  }

  void _applyDecoration(StackChanDecoration value) {
    if (!mounted) {
      return;
    }
    setState(() {});
    _delegate.applyDecoration(value);
  }

  void _applyCaptureScreen(bool value) {
    _captureTimer?.cancel();
    _captureTimer = null;
    if (!value || !mounted) {
      return;
    }
    unawaited(_captureFrame());
    _captureTimer = Timer.periodic(_eventInterval, (_) {
      unawaited(_captureFrame());
    });
  }

  Future<void> _captureFrame() async {
    if (_captureInFlight || !_controller.captureScreen || !mounted) {
      return;
    }
    final RenderObject? renderObject = _captureBoundaryKey.currentContext
        ?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) {
      return;
    }

    _captureInFlight = true;
    try {
      final ui.Image source = await renderObject.toImage();
      ui.Image? cropped;
      ui.Picture? picture;
      try {
        final double sourceAspect = source.width / source.height;
        const double targetAspect = _captureWidth / _captureHeight;
        final double cropWidth = sourceAspect > targetAspect
            ? source.height * targetAspect
            : source.width.toDouble();
        final double cropHeight = sourceAspect > targetAspect
            ? source.height.toDouble()
            : source.width / targetAspect;
        final ui.Rect sourceRect = ui.Rect.fromLTWH(
          (source.width - cropWidth) / 2,
          (source.height - cropHeight) / 2,
          cropWidth,
          cropHeight,
        );

        final ui.PictureRecorder recorder = ui.PictureRecorder();
        final ui.Canvas canvas = ui.Canvas(recorder);
        canvas.drawImageRect(
          source,
          sourceRect,
          ui.Rect.fromLTWH(
            0,
            0,
            _captureWidth.toDouble(),
            _captureHeight.toDouble(),
          ),
          ui.Paint()..filterQuality = ui.FilterQuality.high,
        );
        picture = recorder.endRecording();
        cropped = await picture.toImage(_captureWidth, _captureHeight);
        final ByteData? rgba = await cropped.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        if (rgba == null || !mounted) {
          return;
        }
        final image.Image jpegSource = image.Image.fromBytes(
          width: _captureWidth,
          height: _captureHeight,
          bytes: rgba.buffer,
          bytesOffset: rgba.offsetInBytes,
          numChannels: 4,
          order: image.ChannelOrder.rgba,
        );
        _controller._emitFrame(image.encodeJpg(jpegSource, quality: 72));
      } finally {
        cropped?.dispose();
        picture?.dispose();
        source.dispose();
      }
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('StackChanArView snapshot failed: $error\n$stackTrace');
      }
    } finally {
      _captureInFlight = false;
    }
  }

  @override
  void dispose() {
    _captureTimer?.cancel();
    _captureTimer = null;
    _controller._detach(this);
    if (_ownsController) {
      unawaited(_controller.dispose());
    }
    _expression.dispose();
    _scene.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        RepaintBoundary(
          key: _captureBoundaryKey,
          child: ARView(
            scene: _scene,
            controller: _arController,
            delegate: _delegate,
            enableFaceBlendshapes: true,
            faceAnchorOrigin: ArFaceAnchorOrigin.faceCenter,
            cameraResolution: widget.cameraResolution,
            preferredFramesPerSecond: widget.preferredFramesPerSecond,
            showsStatistics: widget.showsStatistics,
          ),
        ),
        if (widget.showTrackingBadge)
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _TrackingBadge(
                  tracked: _faceTracked,
                  modelLoaded: _modelLoaded,
                  modelError: _modelError,
                ),
              ),
            ),
          ),
        if (widget.showControls)
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
                child: _StackChanControls(
                  decoration: _controller.decoration,
                  captureScreen: _controller.captureScreen,
                  onDecorationChanged: _controller.setDecorate,
                  onCaptureChanged: _controller.setCaptureScreen,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _StackChanFaceDelegate extends ArViewDelegate {
  _StackChanFaceDelegate({
    required this.modelFuture,
    required this.expression,
    required this.onFaceUpdated,
    required this.onFaceRemoved,
  });

  final Future<Node> modelFuture;
  final ValueNotifier<StackChanExpressionData> expression;
  final ValueChanged<ArFaceAnchor> onFaceUpdated;
  final ValueChanged<ArFaceAnchor> onFaceRemoved;
  StackChanDecoration decoration = StackChanDecoration.none;

  Node? _root;
  Node? _modelHost;
  Node? _faceHost;
  Node? _noseHost;

  @override
  Node? nodeForFaceAnchor(ArView view, ArFaceAnchor anchor) {
    final Node root = Node(name: 'stackchan-face-anchor');
    final Node modelHost = Node(name: 'stackchan-model-host');
    final Node faceHost = Node(name: 'stackchan-face-screen')
      ..position = _StackChanArViewState._faceScreenOffset;
    final Node noseHost = Node(name: 'stackchan-pig-nose')
      ..position = _StackChanArViewState._noseOffset;

    faceHost.addComponent(
      WidgetComponent(
        child: _StackChanExpressionDisplay(expression: expression),
        size: const Size(320, 240),
        pixelRatio: 2,
        worldHeight: 0.12,
        input: WidgetInput.manual,
        update: WidgetUpdatePolicy.everyFrame,
      ),
    );
    noseHost.addComponent(
      WidgetComponent(
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: Text('🐽', style: TextStyle(fontSize: 150, height: 1)),
          ),
        ),
        size: const Size(180, 180),
        pixelRatio: 2,
        worldHeight: 0.05,
        input: WidgetInput.manual,
      ),
    );

    root.addAll(<Node>[modelHost, faceHost, noseHost]);
    _root = root;
    _modelHost = modelHost;
    _faceHost = faceHost;
    _noseHost = noseHost;
    _updateVisibility();

    unawaited(
      modelFuture.then<void>((Node template) {
        if (!identical(root, _root)) {
          return;
        }
        modelHost.add(
          template.clone()
            ..name = 'StackChanModel'
            ..position = _StackChanArViewState._modelOffset,
        );
      }),
    );
    return root;
  }

  void applyDecoration(StackChanDecoration value) {
    decoration = value;
    _updateVisibility();
  }

  void _updateVisibility() {
    _modelHost?.visible = decoration == StackChanDecoration.stackChan;
    _faceHost?.visible = decoration == StackChanDecoration.stackChan;
    _noseHost?.visible = decoration == StackChanDecoration.nose;
  }

  @override
  void didUpdateNode(ArView view, ArFaceAnchor anchor) {
    if (identical(anchor.node, _root)) {
      onFaceUpdated(anchor);
    }
  }

  @override
  void didRemoveNode(ArView view, ArFaceAnchor anchor) {
    if (!identical(anchor.node, _root)) {
      return;
    }
    _root = null;
    _modelHost = null;
    _faceHost = null;
    _noseHost = null;
    onFaceRemoved(anchor);
  }
}

class _StackChanExpressionDisplay extends StatelessWidget {
  const _StackChanExpressionDisplay({required this.expression});

  final ValueListenable<StackChanExpressionData> expression;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<StackChanExpressionData>(
      valueListenable: expression,
      builder: (BuildContext context, StackChanExpressionData data, _) {
        return RepaintBoundary(
          child: CustomPaint(
            painter: _StackChanExpressionPainter(data),
            size: const Size(320, 240),
          ),
        );
      },
    );
  }
}

class _StackChanExpressionPainter extends CustomPainter {
  const _StackChanExpressionPainter(this.data);

  final StackChanExpressionData data;

  static const Color _ink = Color(0xFF59ECFF);
  static const Color _screen = Color(0xFF05080A);

  @override
  void paint(Canvas canvas, Size size) {
    final RRect screen = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(22),
    );
    canvas.drawRRect(screen, Paint()..color = _screen);

    final double eyeY = size.height * 0.4 + data.leftEye.y * 0.18;
    final double leftX = size.width * 0.32 + data.leftEye.x * 0.12;
    final double rightX = size.width * 0.68 + data.rightEye.x * 0.12;
    _drawEye(canvas, size, Offset(leftX, eyeY), data.leftEye);
    _drawEye(canvas, size, Offset(rightX, eyeY), data.rightEye);

    final double mouthX = size.width * 0.5 + data.mouth.x * 0.16;
    final double mouthY = size.height * 0.68 + data.mouth.y * 0.12;
    final double mouthWidth = 78 + data.mouth.rotation.abs() * 0.008;
    final double mouthHeight = 6 + data.mouth.weight * 0.34;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(mouthX, mouthY),
          width: mouthWidth,
          height: mouthHeight,
        ),
        Radius.circular(mouthHeight / 2),
      ),
      Paint()..color = _ink,
    );
  }

  void _drawEye(
    Canvas canvas,
    Size size,
    Offset center,
    StackChanExpressionItem item,
  ) {
    final double openness = (item.weight / 100).clamp(0.0, 1.0);
    final double rotation = item.rotation / 1000;
    final Paint glow = Paint()
      ..color = _ink.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    final Paint fill = Paint()..color = _ink;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);
    if (openness < 0.22) {
      final Rect line = Rect.fromCenter(
        center: Offset.zero,
        width: 64,
        height: 5,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(line, const Radius.circular(3)),
        fill,
      );
    } else if (rotation.abs() > 1.2) {
      final Rect arcRect = Rect.fromCenter(
        center: Offset(0, 8),
        width: 62,
        height: 36,
      );
      canvas.drawArc(
        arcRect,
        math.pi * 1.08,
        math.pi * 0.84,
        false,
        Paint()
          ..color = _ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 9
          ..strokeCap = StrokeCap.round,
      );
    } else {
      final Rect eye = Rect.fromCenter(
        center: Offset.zero,
        width: 58,
        height: 12 + openness * 22,
      );
      final RRect capsule = RRect.fromRectAndRadius(
        eye,
        Radius.circular(eye.height / 2),
      );
      canvas.drawRRect(capsule.inflate(3), glow);
      canvas.drawRRect(capsule, fill);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StackChanExpressionPainter oldDelegate) =>
      oldDelegate.data != data;
}

class _TrackingBadge extends StatelessWidget {
  const _TrackingBadge({
    required this.tracked,
    required this.modelLoaded,
    required this.modelError,
  });

  final bool tracked;
  final bool modelLoaded;
  final String? modelError;

  @override
  Widget build(BuildContext context) {
    final String status;
    final Color dotColor;
    if (modelError != null) {
      status = '模型加载失败';
      dotColor = const Color(0xFFFF5A52);
    } else if (!modelLoaded) {
      status = '正在加载模型';
      dotColor = const Color(0xFFFFC857);
    } else if (tracked) {
      status = '面部追踪中';
      dotColor = const Color(0xFF4DE58B);
    } else {
      status = '请将脸放入画面';
      dotColor = const Color(0xCCFFFFFF);
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xB8000000),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x26FFFFFF)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'StackChan AR',
              style: TextStyle(
                color: Color(0xFFFFFFFF),
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              status,
              style: const TextStyle(
                color: Color(0xB3FFFFFF),
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

class _StackChanControls extends StatelessWidget {
  const _StackChanControls({
    required this.decoration,
    required this.captureScreen,
    required this.onDecorationChanged,
    required this.onCaptureChanged,
  });

  final StackChanDecoration decoration;
  final bool captureScreen;
  final ValueChanged<StackChanDecoration> onDecorationChanged;
  final ValueChanged<bool> onCaptureChanged;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 430),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xD10B0D10),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0x2EFFFFFF)),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 24,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              CupertinoSlidingSegmentedControl<StackChanDecoration>(
                groupValue: decoration,
                backgroundColor: const Color(0x331D2025),
                thumbColor: const Color(0xFF2A2F36),
                onValueChanged: (StackChanDecoration? value) {
                  if (value != null) {
                    onDecorationChanged(value);
                  }
                },
                children: const <StackChanDecoration, Widget>{
                  StackChanDecoration.none: Padding(
                    padding: EdgeInsets.symmetric(vertical: 7),
                    child: Text('隐藏'),
                  ),
                  StackChanDecoration.stackChan: Padding(
                    padding: EdgeInsets.symmetric(vertical: 7),
                    child: Text('StackChan'),
                  ),
                  StackChanDecoration.nose: Padding(
                    padding: EdgeInsets.symmetric(vertical: 7),
                    child: Text('猪鼻'),
                  ),
                },
              ),
              const SizedBox(height: 11),
              Row(
                children: <Widget>[
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '画面采集',
                          style: TextStyle(
                            color: Color(0xFFFFFFFF),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          '每 0.5 秒输出 320×240 JPEG',
                          style: TextStyle(
                            color: Color(0x8FFFFFFF),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  CupertinoSwitch(
                    value: captureScreen,
                    onChanged: onCaptureChanged,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Expression values sent to the StackChan firmware.
class StackChanExpressionItem {
  const StackChanExpressionItem({
    this.x = 0,
    this.y = 0,
    this.rotation = 0,
    this.weight = 100,
  });

  final int x;
  final int y;
  final int rotation;
  final int weight;

  Map<String, Object> toJson() => <String, Object>{
    'x': x,
    'y': y,
    'rotation': rotation,
    'weight': weight,
  };
}

/// The eye and mouth expression for one tracked frame.
class StackChanExpressionData {
  const StackChanExpressionData({
    required this.leftEye,
    required this.rightEye,
    required this.mouth,
  });

  factory StackChanExpressionData.neutral() => const StackChanExpressionData(
    leftEye: StackChanExpressionItem(),
    rightEye: StackChanExpressionItem(),
    mouth: StackChanExpressionItem(weight: 0),
  );

  /// Derives expression values with the same formulas as the iOS sample.
  factory StackChanExpressionData.fromAnchor(ArFaceAnchor anchor) {
    final FaceBlendshapes? shapes = anchor.blendshapes;
    if (shapes == null) {
      return StackChanExpressionData.neutral();
    }

    double score(FaceBlendshape shape) => shapes[shape];
    int percent(double value) => (value * 100).round().clamp(-100, 100);

    final int leftEyeWeight = (100 - score(FaceBlendshape.eyeBlinkLeft) * 100)
        .round()
        .clamp(0, 100);
    final int rightEyeWeight = (100 - score(FaceBlendshape.eyeBlinkRight) * 100)
        .round()
        .clamp(0, 100);

    // ARKit exposes a single lookAtPoint; MediaPipe exposes six eye-look
    // coefficients. Combining the inward/outward and up/down terms gives the
    // equivalent horizontal and vertical gaze offsets.
    final double gazeX =
        (score(FaceBlendshape.eyeLookOutLeft) +
            score(FaceBlendshape.eyeLookInRight) -
            score(FaceBlendshape.eyeLookInLeft) -
            score(FaceBlendshape.eyeLookOutRight)) /
        2;
    final double gazeY =
        (score(FaceBlendshape.eyeLookDownLeft) +
            score(FaceBlendshape.eyeLookDownRight) -
            score(FaceBlendshape.eyeLookUpLeft) -
            score(FaceBlendshape.eyeLookUpRight)) /
        2;
    final int eyeX = percent(gazeX);
    final int eyeY = percent(gazeY);

    final double jawOpen = score(FaceBlendshape.jawOpen);
    final double smileLeft = score(FaceBlendshape.mouthSmileLeft);
    final double smileRight = score(FaceBlendshape.mouthSmileRight);
    final int mouthX = percent(smileRight - smileLeft);
    final int mouthWeight = (jawOpen * 100).round().clamp(0, 100);

    var leftEye = StackChanExpressionItem(
      x: eyeX,
      y: eyeY,
      weight: leftEyeWeight,
    );
    var rightEye = StackChanExpressionItem(
      x: eyeX,
      y: eyeY,
      weight: rightEyeWeight,
    );
    final StackChanExpressionItem mouth = StackChanExpressionItem(
      x: mouthX,
      weight: mouthWeight,
    );

    final double smileIntensity = (smileLeft + smileRight) / 2;
    final double eyeSquintIntensity =
        (score(FaceBlendshape.eyeSquintLeft) +
            score(FaceBlendshape.eyeSquintRight)) /
        2;
    final double cheekSquintIntensity =
        (score(FaceBlendshape.cheekSquintLeft) +
            score(FaceBlendshape.cheekSquintRight)) /
        2;
    final bool happy =
        smileIntensity > 0.3 &&
        (eyeSquintIntensity > 0.15 || cheekSquintIntensity > 0.1);
    if (happy) {
      leftEye = StackChanExpressionItem(
        x: leftEye.x,
        y: leftEye.y,
        rotation: -2150,
        weight: leftEye.weight - 35,
      );
      rightEye = StackChanExpressionItem(
        x: rightEye.x,
        y: rightEye.y,
        rotation: 2150,
        weight: rightEye.weight - 35,
      );
    }

    final double averageBrowDown =
        (score(FaceBlendshape.browDownLeft) +
            score(FaceBlendshape.browDownRight)) /
        2;
    final double averageEyeSquint =
        (score(FaceBlendshape.eyeSquintLeft) +
            score(FaceBlendshape.eyeSquintRight)) /
        2;
    final double averageMouthFrown =
        (score(FaceBlendshape.mouthFrownLeft) +
            score(FaceBlendshape.mouthFrownRight)) /
        2;
    final double averageMouthPress =
        (score(FaceBlendshape.mouthPressLeft) +
            score(FaceBlendshape.mouthPressRight)) /
        2;
    final double averageNoseSneer =
        (score(FaceBlendshape.noseSneerLeft) +
            score(FaceBlendshape.noseSneerRight)) /
        2;
    int angerScore = 0;
    if (averageBrowDown > 0.35) angerScore += 3;
    if (averageEyeSquint > 0.25) angerScore += 2;
    if (averageMouthFrown > 0.2) angerScore += 2;
    if (averageMouthPress > 0.2) angerScore += 1;
    if (averageNoseSneer > 0.15) angerScore += 1;
    final bool angry = angerScore >= 5 && averageBrowDown > 0.35;
    if (angry) {
      leftEye = StackChanExpressionItem(
        x: leftEye.x,
        y: leftEye.y,
        rotation: 450,
        weight: leftEye.weight,
      );
      rightEye = StackChanExpressionItem(
        x: rightEye.x,
        y: rightEye.y,
        rotation: -450,
        weight: rightEye.weight,
      );
    }

    return StackChanExpressionData(
      leftEye: leftEye,
      rightEye: rightEye,
      mouth: mouth,
    );
  }

  final StackChanExpressionItem leftEye;
  final StackChanExpressionItem rightEye;
  final StackChanExpressionItem mouth;
}

/// Servo command used by the StackChan motion payload.
class StackChanMotionData {
  const StackChanMotionData({required this.angle, this.speed = 500});

  factory StackChanMotionData.fromYaw(double yawDegrees) {
    return StackChanMotionData(
      angle: (-yawDegrees * 20).round().clamp(-1280, 1280),
    );
  }

  factory StackChanMotionData.fromPitch(double pitchDegrees) {
    return StackChanMotionData(
      angle: (-pitchDegrees * 10).round().clamp(0, 900),
    );
  }

  final int angle;
  final int speed;

  Map<String, Object> toJson() => <String, Object>{
    'angle': angle,
    'speed': speed,
  };
}

/// Payload emitted on [StackChanArController.expressions].
class StackChanDanceData {
  const StackChanDanceData({
    required this.leftEye,
    required this.rightEye,
    required this.mouth,
    required this.yawServo,
    required this.pitchServo,
    required this.durationMs,
  });

  final StackChanExpressionItem leftEye;
  final StackChanExpressionItem rightEye;
  final StackChanExpressionItem mouth;
  final StackChanMotionData yawServo;
  final StackChanMotionData pitchServo;
  final int durationMs;

  Map<String, Object> toJson() => <String, Object>{
    'leftEye': leftEye.toJson(),
    'rightEye': rightEye.toJson(),
    'mouth': mouth.toJson(),
    'yawServo': yawServo.toJson(),
    'pitchServo': pitchServo.toJson(),
    'durationMs': durationMs,
  };

  String toJsonString() => jsonEncode(toJson());
}
