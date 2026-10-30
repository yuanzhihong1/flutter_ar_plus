import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:camera_macos/camera_macos.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:flutter/widgets.dart' hide Matrix4;
import 'package:flutter_scene/scene.dart' hide CameraController;
import 'package:mediapipe_face_mesh/mediapipe_face_mesh.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Quaternion, Vector3;

import 'ar_face_pose.dart';
import 'src/ar_view_layout.dart';

/// Builds the content shown while the camera or face pipeline is starting.
typedef ArViewLoadingBuilder = Widget Function(
  BuildContext context,
  double progress,
);

/// Builds the error UI shown when camera access or face tracking fails.
typedef ArViewErrorBuilder = Widget Function(
  BuildContext context,
  ArViewException error,
  VoidCallback retry,
  Future<void> Function() openSettings,
);

/// Why an [ArView] could not start or continue tracking.
enum ArViewErrorCode {
  /// The camera permission request was denied.
  cameraPermissionDenied,

  /// The user must enable camera access in the system settings.
  cameraPermissionPermanentlyDenied,

  /// Camera access is restricted by device policy or parental controls.
  cameraPermissionRestricted,

  /// No usable camera was reported by the platform.
  cameraUnavailable,

  /// Camera initialization or image streaming failed.
  cameraInitializationFailed,

  /// The MediaPipe face pipeline failed.
  faceTrackingFailed,

  /// A glTF/GLB model could not be loaded.
  modelLoadFailed,

  /// This platform does not provide the required camera/FFI support.
  unsupportedPlatform,
}

/// An error surfaced by [ArView].
class ArViewException implements Exception {
  /// Creates an AR view error.
  const ArViewException(this.code, this.message, {this.cause, this.stackTrace});

  /// Machine-readable failure category.
  final ArViewErrorCode code;

  /// Human-readable explanation.
  final String message;

  /// The original exception, when one exists.
  final Object? cause;

  /// The original stack trace, when one exists.
  final StackTrace? stackTrace;

  /// Whether showing the system app settings is useful for this error.
  bool get canOpenSettings =>
      code == ArViewErrorCode.cameraPermissionDenied ||
      code == ArViewErrorCode.cameraPermissionPermanentlyDenied ||
      code == ArViewErrorCode.cameraPermissionRestricted;

  @override
  String toString() => 'ArViewException($code): $message';
}

/// Receives node and anchor lifecycle callbacks from an [ArView].
///
/// This mirrors the useful part of `ARSCNViewDelegate`: the view owns face
/// tracking and anchor updates, while the delegate supplies the scene node
/// placed at the face anchor.
abstract class ArViewDelegate {
  /// Creates an AR view delegate.
  const ArViewDelegate();

  /// Returns the node rendered for a newly acquired face anchor.
  ///
  /// The returned node is attached to [ArView.scene] automatically. Add
  /// meshes, models, particles, or a [WidgetComponent] to this node. Return
  /// `null` to keep an empty tracking node.
  Node? nodeForFaceAnchor(ArView view, ArFaceAnchor anchor) => null;

  /// Called after the node for [anchor] has been attached to the scene.
  void didAddNode(ArView view, ArFaceAnchor anchor) {}

  /// Called whenever the face transform or landmarks are updated.
  ///
  /// The node has already been moved. Use this callback for animation or
  /// renderer-side effects.
  void didUpdateNode(ArView view, ArFaceAnchor anchor) {}

  /// Called after the face anchor and its node have been removed.
  void didRemoveNode(ArView view, ArFaceAnchor anchor) {}
}

/// Imperative controls for an [ArView], modeled after the useful parts of
/// `ARSCNView`'s node and projection APIs.
///
/// A controller writes to the app-owned [Scene] directly, so a node can be
/// prepared before the view is mounted. The view is only required for
/// screen-space queries such as [projectPoint] and [hitTest].
///
/// All positions are expressed in AR camera space: the camera is at the
/// origin, +X points right, +Y points up, and +Z points away from the camera.
/// For a node attached to another node, [setPosition] changes its position
/// relative to that parent, just like `SCNNode.position`.
///
/// ```dart
/// final scene = Scene();
/// final arController = ARViewController(scene: scene);
///
/// arController.addNode(
///   Node(name: 'cube')..addComponent(
///     MeshComponent(Mesh(CuboidGeometry(Vector3.all(0.2)), material)),
///   ),
///   position: Vector3(0, 0, 1),
/// );
///
/// ARView(scene: scene, controller: arController);
/// ```
class ARViewController {
  /// Creates a controller backed by [scene].
  ///
  /// The same scene must be supplied to [ArView.scene]. The scene remains
  /// application-owned and is not disposed by the controller or the view.
  ARViewController({required this.scene});

  /// The scene controlled by this controller.
  final Scene scene;

  _ArViewState? _view;
  int _nextGeneratedName = 1;

  /// Whether this controller is currently mounted to an [ArView].
  bool get isAttached => _view?.mounted ?? false;

  /// The mounted view's current logical size.
  ///
  /// Throws a [StateError] when called before the view has been mounted.
  Size get viewportSize {
    final _ArViewState view = _requireView();
    return view._viewportSize;
  }

  /// The camera used to render the AR scene.
  ///
  /// This is the Flutter Scene equivalent of `ARSCNView.pointOfView`.
  /// Throws a [StateError] when called before the view has been mounted.
  Camera get pointOfView => _requireView().pointOfView;

  /// Adds [node] to the root of [scene] and applies optional local transforms.
  ///
  /// If [node] already belongs to this scene, this method updates its
  /// placement without adding it a second time. Nodes owned by another scene
  /// are rejected.
  ///
  /// Prefer passing an explicit camera-space [position]. A common visible
  /// placement is `Vector3(0, 0, 1)`, one meter in front of the camera.
  Node addNode(
    Node node, {
    String? name,
    Vector3? position,
    Quaternion? rotation,
    Vector3? scale,
  }) {
    _ensureNodeBelongsToScene(node);
    final String trimmedName = name?.trim() ?? '';
    if (trimmedName.isNotEmpty) {
      node.name = trimmedName;
    } else if (node.name.isEmpty) {
      node.name = 'ar_node_${_nextGeneratedName++}';
    }
    _applyLocalTransform(
      node,
      position: position,
      rotation: rotation,
      scale: scale,
    );
    if (node.parent == null) {
      scene.add(node);
    }
    return node;
  }

  /// Loads a runtime glTF binary (`.glb`) and adds it in front of the camera.
  ///
  /// [position] defaults to `Vector3(0, 0, 1)`, which places the model one
  /// meter from the camera. Use [scale] to fit models authored at a different
  /// unit size.
  ///
  /// Throws an [ArViewException] with [ArViewErrorCode.modelLoadFailed] when
  /// the asset cannot be decoded.
  Future<Node> addModel(
    String assetPath, {
    String? name,
    Vector3? position,
    Quaternion? rotation,
    Vector3? scale,
    int? maxTextureSize,
  }) async {
    late final Node node;
    try {
      node = await Node.fromGlbAsset(assetPath, maxTextureSize: maxTextureSize);
    } catch (error, stackTrace) {
      throw ArViewException(
        ArViewErrorCode.modelLoadFailed,
        'Unable to load model "$assetPath": $error',
        cause: error,
        stackTrace: stackTrace,
      );
    }
    return addNode(
      node,
      name: name,
      position: position ?? Vector3(0.0, 0.0, 1.0),
      rotation: rotation,
      scale: scale,
    );
  }

  /// Removes [node] from the scene. Does nothing if it is already detached.
  void removeNode(Node node) {
    if (node.parent != null) {
      node.detach();
    }
  }

  /// Finds the first node named [name] in the scene graph.
  Node? nodeNamed(String name) => scene.root.getChildByName(name);

  /// Sets [node]'s position relative to its parent.
  void setPosition(Node node, Vector3 position) {
    node.position = position.clone();
  }

  /// Moves [node] by [offset] relative to its parent.
  void moveNode(Node node, Vector3 offset) {
    node.position = node.position + offset;
  }

  /// Sets [node]'s local rotation.
  void setRotation(Node node, Quaternion rotation) {
    node.rotation = rotation.clone();
  }

  /// Sets [node]'s local scale.
  void setScale(Node node, Vector3 scale) {
    node.scale = scale.clone();
  }

  /// Replaces [node]'s local transform.
  void setTransform(Node node, Matrix4 transform) {
    node.localTransform = transform.clone();
  }

  /// Sets [node]'s world-space position, accounting for its parent transform.
  void setWorldPosition(Node node, Vector3 position) {
    final Matrix4 transform = node.globalTransform.clone()
      ..setTranslation(position);
    node.globalTransform = transform;
  }

  /// Replaces [node]'s world-space transform.
  void setWorldTransform(Node node, Matrix4 transform) {
    node.globalTransform = transform.clone();
  }

  /// Returns [node]'s world-space position in AR camera space.
  Vector3 getWorldPosition(Node node) => node.globalTransform.getTranslation();

  /// Projects a world-space point to logical viewport coordinates.
  ///
  /// This is the Flutter Scene counterpart of `ARSCNView.projectPoint`.
  /// Returns `null` for points at or behind the camera plane.
  Offset? projectPoint(Vector3 point) {
    final _ArViewState view = _requireView();
    if (view._viewportSize.isEmpty) {
      return null;
    }
    return view.pointOfView.worldToScreen(point, view._viewportSize);
  }

  /// Converts a logical viewport point into a world-space point at [distance]
  /// meters from the camera.
  ///
  /// The counterpart of `ARSCNView.unprojectPoint` for a camera without a
  /// depth map. Throws a [StateError] when the view is not mounted.
  Vector3 unprojectPoint(Offset point, {double distance = 1.0}) {
    final _ArViewState view = _requireView();
    return view.pointOfView
        .screenPointToRay(point, view._viewportSize)
        .at(distance);
  }

  /// Returns the nearest rendered surface under [point], if any.
  ///
  /// This performs a mesh raycast, the closest Flutter Scene equivalent of
  /// `ARSCNView.hitTest(_:options:)` without an ARKit depth map.
  SceneRaycastHit? hitTest(Offset point) {
    final _ArViewState view = _requireView();
    if (view._viewportSize.isEmpty) {
      return null;
    }
    return scene.raycast(
      view.pointOfView.screenPointToRay(point, view._viewportSize),
    );
  }

  /// Returns every rendered surface under [point], nearest first.
  List<SceneRaycastHit> hitTestAll(Offset point) {
    final _ArViewState view = _requireView();
    if (view._viewportSize.isEmpty) {
      return const <SceneRaycastHit>[];
    }
    return scene.raycastAll(
      view.pointOfView.screenPointToRay(point, view._viewportSize),
    );
  }

  void _applyLocalTransform(
    Node node, {
    Vector3? position,
    Quaternion? rotation,
    Vector3? scale,
  }) {
    if (position != null) {
      node.position = position.clone();
    }
    if (rotation != null) {
      node.rotation = rotation.clone();
    }
    if (scale != null) {
      node.scale = scale.clone();
    }
  }

  void _ensureNodeBelongsToScene(Node node) {
    if (node.parent == null) {
      return;
    }
    Node root = node;
    while (root.parent != null) {
      root = root.parent!;
    }
    if (!identical(root, scene.root)) {
      throw ArgumentError.value(
        node,
        'node',
        'The node already belongs to another scene.',
      );
    }
  }

  _ArViewState _requireView() {
    final _ArViewState? view = _view;
    if (view == null || !view.mounted) {
      throw StateError(
        'ARViewController is not attached to an ArView. '
        'Pass it to ArView.controller and wait until the view is mounted.',
      );
    }
    return view;
  }

  void _attach(_ArViewState view) {
    final _ArViewState? attached = _view;
    if (attached != null && !identical(attached, view)) {
      throw StateError(
        'ARViewController is already attached to another ArView.',
      );
    }
    if (!identical(scene, view.widget.scene)) {
      throw StateError(
        'ARViewController.scene must be the same Scene passed to ArView.',
      );
    }
    _view = view;
  }

  void _detach(_ArViewState view) {
    if (identical(_view, view)) {
      _view = null;
    }
  }
}

/// A tracked face anchor backed by a Flutter Scene [Node].
///
/// The transform is expressed in meters in the AR camera space: +X points
/// right, +Y points up, and +Z points away from the camera. The node follows
/// the estimated head pose and is placed at either the nose tip or the face
/// center according to [origin]. Child content should
/// use Flutter Scene's local +Z-forward convention so its front follows the
/// direction the tracked face is looking.
class ArFaceAnchor {
  ArFaceAnchor._(this.identifier, this._node, this.origin);

  /// Stable identifier while the face remains tracked.
  final int identifier;

  /// Coordinate-system origin used by this anchor.
  final ArFaceAnchorOrigin origin;

  Node _node;
  Matrix4 _transform = Matrix4.identity();
  Quaternion _rotation = Quaternion.identity();
  Offset _screenPosition = Offset.zero;
  FaceMeshResult? _mesh;
  FaceMeshHeadPose? _headPose;
  FaceBlendshapes? _blendshapes;
  double _distanceMeters = 0;
  double _faceWidthMeters = 0;

  /// The scene node attached at this anchor.
  Node get node => _node;

  /// Current anchor transform in AR camera space.
  Matrix4 get transform => _transform.clone();

  /// Current rotation of the anchor.
  Quaternion get rotation => _rotation.clone();

  /// Nose position in normalized display coordinates, with top-left origin.
  Offset get screenPosition => _screenPosition;

  /// Estimated distance from the camera in meters.
  double get distanceMeters => _distanceMeters;

  /// Estimated physical face width in meters.
  double get faceWidthMeters => _faceWidthMeters;

  /// Current MediaPipe face mesh.
  FaceMeshResult get mesh => _mesh!;

  /// Current head rotation estimate.
  FaceMeshHeadPose get headPose => _headPose!;

  /// The 52 ARKit-style facial coefficients for the current frame.
  ///
  /// This is `null` unless [ArView.enableFaceBlendshapes] is enabled. The
  /// coefficients map directly to the categories used by ARKit face anchors,
  /// which makes ports of ARKit expression logic straightforward.
  FaceBlendshapes? get blendshapes => _blendshapes;

  /// All 478 landmarks for the current frame.
  List<FaceMeshLandmark> get landmarks => mesh.landmarks;

  void _update({
    required Matrix4 transform,
    required Quaternion rotation,
    required Offset screenPosition,
    required FaceMeshResult mesh,
    required FaceMeshHeadPose headPose,
    required FaceBlendshapes? blendshapes,
    required double distanceMeters,
    required double faceWidthMeters,
  }) {
    _transform = transform;
    _rotation = rotation;
    _screenPosition = screenPosition;
    _mesh = mesh;
    _headPose = headPose;
    _blendshapes = blendshapes;
    _distanceMeters = distanceMeters;
    _faceWidthMeters = faceWidthMeters;
  }
}

/// A camera-backed face AR view inspired by `ARSCNView`.
///
/// [ArView] owns the camera preview, MediaPipe face tracking, and the mapping
/// from face landmarks into a Flutter Scene perspective camera. The supplied
/// [scene] stays application-owned. The view creates one persistent
/// [ArFaceAnchor.node] while a face is tracked and updates its transform every
/// inference frame. The node is placed at the nose by default; set
/// [faceAnchorOrigin] to [ArFaceAnchorOrigin.faceCenter] when porting code that
/// uses ARKit face-center coordinates.
///
/// Face tracking runs in a worker isolate. Camera permission is requested with
/// `permission_handler` before the camera controller is created.
class ArView extends StatefulWidget {
  /// Creates an AR face view.
  const ArView({
    required this.scene,
    super.key,
    this.controller,
    this.delegate,
    this.onFaceAnchorUpdated,
    this.cameraLensDirection = CameraLensDirection.front,
    this.cameraResolution = ResolutionPreset.medium,
    this.cameraVerticalFovDegrees = 63,
    this.preferredFramesPerSecond = 30,
    this.anchorLostGracePeriod = const Duration(milliseconds: 350),
    this.isFaceTrackingEnabled = true,
    this.enableFaceBlendshapes = false,
    this.faceAnchorOrigin = ArFaceAnchorOrigin.noseTip,
    this.showCameraPreview = true,
    this.showsStatistics = false,
    this.loadingBuilder,
    this.errorBuilder,
    this.onError,
  }) : assert(
         cameraVerticalFovDegrees > 0 && cameraVerticalFovDegrees < 180,
         'cameraVerticalFovDegrees must be between 0 and 180.',
       ),
       assert(
         preferredFramesPerSecond > 0,
         'preferredFramesPerSecond must be greater than zero.',
       );

  /// Application-owned Flutter Scene rendered over the camera feed.
  final Scene scene;

  /// Imperative controller for adding, removing, and moving scene nodes.
  ///
  /// The controller must use the same [scene]. It may be used before this
  /// widget is mounted for node and transform operations.
  final ARViewController? controller;

  /// Receives node and face-anchor lifecycle callbacks.
  final ArViewDelegate? delegate;

  /// Called after each tracked face update.
  final ValueChanged<ArFaceAnchor>? onFaceAnchorUpdated;

  /// Preferred physical camera. Falls back to the first available camera.
  final CameraLensDirection cameraLensDirection;

  /// Requested camera resolution.
  final ResolutionPreset cameraResolution;

  /// Vertical field of view used by the tracking perspective camera.
  ///
  /// Set this to the camera's real vertical FOV when known. The default 63°
  /// matches MediaPipe's reference camera.
  final double cameraVerticalFovDegrees;

  /// Preferred camera, face-tracking, and scene rendering rate.
  ///
  /// Camera frames are sampled at this rate before being sent to MediaPipe,
  /// and Flutter Scene is capped to the same frame rate.
  final int preferredFramesPerSecond;

  /// How long a missing face is kept before its anchor is removed.
  final Duration anchorLostGracePeriod;

  /// Whether face inference is enabled.
  final bool isFaceTrackingEnabled;

  /// Whether to calculate MediaPipe's 52 ARKit-style facial coefficients.
  ///
  /// Disabled by default because it adds one inference pass per frame. When
  /// enabled, the latest coefficients are exposed through
  /// [ArFaceAnchor.blendshapes].
  final bool enableFaceBlendshapes;

  /// Origin used for [ArFaceAnchor.node] and [ArFaceAnchor.transform].
  ///
  /// [ArFaceAnchorOrigin.noseTip] is the default and works well for small
  /// face-worn props. Use [ArFaceAnchorOrigin.faceCenter] when porting ARKit
  /// code that applies offsets relative to Apple's face-anchor origin.
  final ArFaceAnchorOrigin faceAnchorOrigin;

  /// Whether the live camera image is visible behind the scene.
  final bool showCameraPreview;

  /// Whether a small tracking/FPS badge is shown.
  final bool showsStatistics;

  /// Optional loading UI. Camera start progress is currently reported as 0.
  final ArViewLoadingBuilder? loadingBuilder;

  /// Optional error UI.
  final ArViewErrorBuilder? errorBuilder;

  /// Reports camera and tracking errors.
  final void Function(Object error, StackTrace stackTrace)? onError;

  @override
  State<ArView> createState() => _ArViewState();
}

/// Canonical Apple-style name for [ArView].
///
/// `ARView` is the preferred spelling in new code. The older [ArView] name is
/// retained as the underlying implementation and remains source-compatible.
typedef ARView = ArView;

Future<FaceMeshInferencePipeline> _createFaceMeshPipeline(
  FaceMeshModel model,
) async {
  return FaceMeshInferencePipeline(
    detector: await FaceDetectorProcessor.create(
      model: FaceDetectionModel.shortRange,
      delegate: FaceMeshDelegate.xnnpack,
    ),
    mesh: await FaceMeshProcessor.create(
      model: model,
      delegate: FaceMeshDelegate.xnnpack,
    ),
  );
}

class _ArViewState extends State<ArView> with WidgetsBindingObserver {
  static const Map<DeviceOrientation, int> _deviceOrientationDegrees =
      <DeviceOrientation, int>{
        DeviceOrientation.portraitUp: 0,
        DeviceOrientation.landscapeLeft: 90,
        DeviceOrientation.portraitDown: 180,
        DeviceOrientation.landscapeRight: 270,
      };

  CameraController? _cameraController;
  CameraDescription? _cameraDescription;
  CameraMacOSController? _macOSCameraController;
  bool _macOSCameraRequested = false;
  bool _macOSCameraErrorReported = false;
  int _macOSCameraSession = 0;
  FaceMeshIsolatePipeline? _pipeline;
  Future<FaceMeshIsolatePipeline>? _pipelineFuture;
  FaceBlendshapesProcessor? _blendshapesProcessor;
  Future<FaceBlendshapesProcessor>? _blendshapesProcessorFuture;
  bool _blendshapeErrorReported = false;

  ArFaceAnchor? _faceAnchor;
  Timer? _faceLostTimer;
  int _nextAnchorId = 1;
  int _generation = 0;
  bool _active = true;
  bool _disposed = false;
  bool _initializing = true;
  ArViewException? _error;

  Size _viewportSize = Size.zero;
  DateTime? _lastProcessedAt;
  DateTime? _fpsWindowStartedAt;
  int _fpsFrames = 0;
  double _fps = 0;
  int? _lastInputRotation;
  bool? _lastInputMirror;
  bool _reportedTrackingError = false;
  DateTime? _lastDebugTraceAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller?._attach(this);
    unawaited(_start());
  }

  @override
  void didUpdateWidget(ArView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
    if (!identical(oldWidget.scene, widget.scene)) {
      _removeFaceAnchor(scene: oldWidget.scene, notify: false);
      _faceLostTimer?.cancel();
      _faceLostTimer = null;
    }
    if (oldWidget.cameraLensDirection != widget.cameraLensDirection ||
        oldWidget.cameraResolution != widget.cameraResolution) {
      unawaited(_start());
    }
    if (oldWidget.isFaceTrackingEnabled && !widget.isFaceTrackingEnabled) {
      _removeFaceAnchor();
    }
    if (oldWidget.enableFaceBlendshapes && !widget.enableFaceBlendshapes) {
      _closeBlendshapesProcessor();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _active = true;
        if (_cameraController?.value.isInitialized != true) {
          unawaited(_start());
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _active = false;
        _generation++;
        _removeFaceAnchor();
        unawaited(_stopCamera());
    }
  }

  Future<FaceBlendshapesProcessor> _ensureBlendshapesProcessor() {
    final FaceBlendshapesProcessor? existing = _blendshapesProcessor;
    if (existing != null) {
      return Future<FaceBlendshapesProcessor>.value(existing);
    }
    final Future<FaceBlendshapesProcessor>? pending =
        _blendshapesProcessorFuture;
    if (pending != null) {
      return pending;
    }
    final Future<FaceBlendshapesProcessor> loading =
        FaceBlendshapesProcessor.create(delegate: FaceMeshDelegate.xnnpack);
    _blendshapesProcessorFuture = loading;
    loading.then(
      (FaceBlendshapesProcessor processor) {
        if (_disposed || !widget.enableFaceBlendshapes) {
          processor.close();
        } else {
          _blendshapesProcessor = processor;
        }
      },
      onError: (Object _) {
        if (identical(_blendshapesProcessorFuture, loading)) {
          _blendshapesProcessorFuture = null;
        }
      },
    );
    return loading;
  }

  Future<FaceBlendshapes?> _faceBlendshapesFor(FaceMeshResult mesh) async {
    if (!widget.enableFaceBlendshapes) {
      return null;
    }
    try {
      final FaceBlendshapesProcessor processor =
          await _ensureBlendshapesProcessor();
      if (_disposed || !widget.enableFaceBlendshapes) {
        return null;
      }
      return processor.process(mesh);
    } catch (error) {
      if (!_blendshapeErrorReported && kDebugMode) {
        _blendshapeErrorReported = true;
        debugPrint('ArView: face blendshapes disabled: $error');
      }
      return null;
    }
  }

  void _closeBlendshapesProcessor() {
    _blendshapesProcessor?.close();
    _blendshapesProcessor = null;
    _blendshapesProcessorFuture = null;
  }

  Future<FaceMeshIsolatePipeline> _ensurePipeline() {
    final FaceMeshIsolatePipeline? existing = _pipeline;
    if (existing != null && !existing.isClosed) {
      return Future<FaceMeshIsolatePipeline>.value(existing);
    }
    final Future<FaceMeshIsolatePipeline>? pending = _pipelineFuture;
    if (pending != null) {
      return pending;
    }
    final Future<FaceMeshIsolatePipeline> loading =
        FaceMeshIsolatePipeline.spawn<FaceMeshModel>(
          _createFaceMeshPipeline,
          FaceMeshModel.v2,
        );
    _pipelineFuture = loading;
    loading.then(
      (FaceMeshIsolatePipeline pipeline) {
        if (_disposed || !identical(_pipelineFuture, loading)) {
          unawaited(_closePipeline(pipeline));
        } else {
          _pipeline = pipeline;
        }
      },
      onError: (Object _) {
        if (identical(_pipelineFuture, loading)) {
          _pipelineFuture = null;
        }
      },
    );
    return loading;
  }

  Future<void> _requestCameraPermission() async {
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }

    final PermissionStatus status = await Permission.camera.request();
    if (status.isGranted || status.isLimited) {
      return;
    }
    if (status.isPermanentlyDenied) {
      throw const ArViewException(
        ArViewErrorCode.cameraPermissionPermanentlyDenied,
        'Camera access is permanently denied. Enable it in Settings.',
      );
    }
    if (status.isRestricted) {
      throw const ArViewException(
        ArViewErrorCode.cameraPermissionRestricted,
        'Camera access is restricted on this device.',
      );
    }
    throw const ArViewException(
      ArViewErrorCode.cameraPermissionDenied,
      'Camera access was denied.',
    );
  }

  Future<void> _start() async {
    if (_disposed || !_active) {
      return;
    }
    final int generation = ++_generation;
    _faceLostTimer?.cancel();
    _faceLostTimer = null;
    _removeFaceAnchor(notify: false);
    await _stopCamera();
    if (!_isCurrent(generation)) {
      return;
    }

    _setState(() {
      _initializing = true;
      _error = null;
    });

    try {
      if (!_isSupportedPlatform) {
        throw const ArViewException(
          ArViewErrorCode.unsupportedPlatform,
          'ArView currently supports Android, iOS, and macOS.',
        );
      }
      if (_isMacOS) {
        final Future<FaceMeshIsolatePipeline> pipelineFuture =
            _ensurePipeline();
        unawaited(
          pipelineFuture.then<void>(
            (_) {},
            onError: (Object error, StackTrace stackTrace) {
              if (_isCurrent(generation)) {
                _reportError(
                  ArViewException(
                    ArViewErrorCode.faceTrackingFailed,
                    'Unable to start MediaPipe face tracking: $error',
                    cause: error,
                    stackTrace: stackTrace,
                  ),
                  stackTrace,
                );
              }
            },
          ),
        );
        _setState(() {
          _macOSCameraErrorReported = false;
          _macOSCameraRequested = true;
          _macOSCameraSession++;
        });
        return;
      }
      await _requestCameraPermission();
      if (!_isCurrent(generation)) {
        return;
      }

      final Future<FaceMeshIsolatePipeline> pipelineFuture = _ensurePipeline();
      final List<CameraDescription> cameras = await availableCameras();
      if (!_isCurrent(generation)) {
        return;
      }
      if (cameras.isEmpty) {
        throw const ArViewException(
          ArViewErrorCode.cameraUnavailable,
          'No cameras are available on this device.',
        );
      }

      final CameraDescription description = _selectCamera(cameras);
      final CameraController controller = CameraController(
        description,
        widget.cameraResolution,
        enableAudio: false,
        imageFormatGroup: _imageFormatForPlatform(),
      );
      try {
        await controller.initialize();
      } catch (_) {
        await controller.dispose();
        rethrow;
      }
      if (!_isCurrent(generation)) {
        await controller.dispose();
        return;
      }

      _cameraDescription = description;
      _cameraController = controller;
      _setState(() {});

      try {
        await pipelineFuture;
      } catch (error, stackTrace) {
        throw ArViewException(
          ArViewErrorCode.faceTrackingFailed,
          'Unable to start MediaPipe face tracking: $error',
          cause: error,
          stackTrace: stackTrace,
        );
      }
      if (!_isCurrent(generation)) {
        await _stopCamera();
        return;
      }
      if (!controller.value.isStreamingImages) {
        await controller.startImageStream(_handleCameraFrame);
      }
      if (!_isCurrent(generation)) {
        await _stopCamera();
        return;
      }
      _setState(() {
        _initializing = false;
      });
    } catch (error, stackTrace) {
      if (!_isCurrent(generation)) {
        return;
      }
      await _stopCamera();
      if (!_isCurrent(generation)) {
        return;
      }
      _reportError(
        error is ArViewException
            ? error
            : ArViewException(
                ArViewErrorCode.cameraInitializationFailed,
                'Unable to start the camera: $error',
                cause: error,
                stackTrace: stackTrace,
              ),
        stackTrace,
      );
    }
  }

  bool _isCurrent(int generation) =>
      !_disposed && _active && mounted && generation == _generation;

  bool get _isSupportedPlatform =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      _isMacOS;

  bool get _isMacOS => defaultTargetPlatform == TargetPlatform.macOS;

  CameraDescription _selectCamera(List<CameraDescription> cameras) {
    for (final CameraDescription camera in cameras) {
      if (camera.lensDirection == widget.cameraLensDirection) {
        return camera;
      }
    }
    return cameras.first;
  }

  ImageFormatGroup _imageFormatForPlatform() {
    return defaultTargetPlatform == TargetPlatform.iOS || _isMacOS
        ? ImageFormatGroup.bgra8888
        : ImageFormatGroup.nv21;
  }

  void _handleCameraFrame(CameraImage image) {
    if (!_active || !widget.isFaceTrackingEnabled) {
      return;
    }
    final FaceMeshIsolatePipeline? pipeline = _pipeline;
    final CameraController? controller = _cameraController;
    final CameraDescription? description = _cameraDescription;
    if (pipeline == null ||
        pipeline.isClosed ||
        pipeline.isBusy ||
        controller == null ||
        description == null ||
        !controller.value.isInitialized) {
      return;
    }

    final DateTime now = DateTime.now();
    final Duration frameInterval = Duration(
      microseconds: 1000000 ~/ widget.preferredFramesPerSecond,
    );
    final DateTime? last = _lastProcessedAt;
    if (last != null && now.difference(last) < frameInterval) {
      return;
    }

    final int? rotation = _rotationDegrees(controller, description);
    if (rotation == null) {
      return;
    }
    final bool mirror =
        defaultTargetPlatform == TargetPlatform.android &&
        description.lensDirection == CameraLensDirection.front;
    if (_lastInputRotation != rotation || _lastInputMirror != mirror) {
      _lastInputRotation = rotation;
      _lastInputMirror = mirror;
      unawaited(pipeline.resetTracking());
    }

    final FaceMeshFrame? frame = _cameraImageToFaceMesh(image);
    if (frame == null) {
      return;
    }
    _lastProcessedAt = now;
    unawaited(
      _processFrame(
        pipeline,
        frame,
        rotationDegrees: rotation,
        mirrorHorizontal: mirror,
      ),
    );
  }

  Future<void> _startMacOSImageStream(CameraMacOSController controller) async {
    if (!_isMacOS ||
        !_active ||
        !_macOSCameraRequested ||
        !identical(controller, _macOSCameraController)) {
      return;
    }
    try {
      await _ensurePipeline();
      if (!_isMacOS ||
          !_active ||
          !_macOSCameraRequested ||
          !identical(controller, _macOSCameraController)) {
        return;
      }
      if (!controller.isStreamingImageData) {
        await controller.startImageStream(
          _handleMacOSCameraFrame,
          onError: _handleMacOSStreamError,
        );
      }
      if (!_isMacOS ||
          !_active ||
          !_macOSCameraRequested ||
          !identical(controller, _macOSCameraController)) {
        return;
      }
      _setState(() {
        _initializing = false;
      });
    } catch (error, stackTrace) {
      if (!_active || _disposed) {
        return;
      }
      _reportError(
        ArViewException(
          ArViewErrorCode.cameraInitializationFailed,
          'Unable to start the macOS camera stream: $error',
          cause: error,
          stackTrace: stackTrace,
        ),
        stackTrace,
      );
    }
  }

  void _handleMacOSCameraFrame(CameraImageData? image) {
    if (image == null || !_active || !widget.isFaceTrackingEnabled) {
      return;
    }
    final FaceMeshIsolatePipeline? pipeline = _pipeline;
    if (pipeline == null || pipeline.isClosed || pipeline.isBusy) {
      return;
    }

    final DateTime now = DateTime.now();
    final Duration frameInterval = Duration(
      microseconds: 1000000 ~/ widget.preferredFramesPerSecond,
    );
    final DateTime? last = _lastProcessedAt;
    if (last != null && now.difference(last) < frameInterval) {
      return;
    }
    _lastProcessedAt = now;

    final FaceMeshFrame frame = FaceMeshImage(
      pixels: image.bytes,
      width: image.width,
      height: image.height,
      bytesPerRow: image.bytesPerRow,
      pixelFormat: FaceMeshPixelFormat.bgra,
    );
    unawaited(
      _processFrame(
        pipeline,
        frame,
        rotationDegrees: 0,
        // CameraMacOSView mirrors the preview and streamed BGRA image
        // together, so applying MediaPipe mirroring again would move the
        // landmarks to the opposite side of the preview.
        mirrorHorizontal: false,
      ),
    );
  }

  void _handleMacOSStreamError(dynamic error) {
    if (!_active || _disposed || _reportedTrackingError) {
      return;
    }
    _reportedTrackingError = true;
    _reportError(
      ArViewException(
        ArViewErrorCode.cameraInitializationFailed,
        'The macOS camera stream stopped: $error',
        cause: error,
      ),
      StackTrace.current,
    );
  }

  void _handleMacOSCameraInitError(Object? error) {
    if (error == null || _macOSCameraErrorReported || !_active || _disposed) {
      return;
    }
    _macOSCameraErrorReported = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_active || _disposed) {
        return;
      }
      final String message = error.toString();
      final bool permissionDenied = message.toLowerCase().contains(
        'permission',
      );
      _setState(() {
        _macOSCameraRequested = false;
      });
      _reportError(
        ArViewException(
          permissionDenied
              ? ArViewErrorCode.cameraPermissionDenied
              : ArViewErrorCode.cameraInitializationFailed,
          permissionDenied
              ? 'Camera access was denied. Enable it in System Settings.'
              : 'Unable to initialize the macOS camera: $message',
          cause: error,
        ),
        StackTrace.current,
      );
    });
  }

  Future<void> _processFrame(
    FaceMeshIsolatePipeline pipeline,
    FaceMeshFrame frame, {
    required int rotationDegrees,
    required bool mirrorHorizontal,
  }) async {
    try {
      final FaceMeshInferenceResult result = await pipeline.process(
        frame,
        rotationDegrees: rotationDegrees,
        mirrorHorizontal: mirrorHorizontal,
      );
      if (!_active || _disposed || !identical(pipeline, _pipeline)) {
        return;
      }
      _recordInferenceFrame();
      final FaceMeshResult? mesh = result.meshResult;
      if (mesh == null) {
        _markFaceLost();
        return;
      }
      final FaceBlendshapes? blendshapes = await _faceBlendshapesFor(mesh);
      if (!_active || _disposed || !identical(pipeline, _pipeline)) {
        return;
      }
      _faceLostTimer?.cancel();
      _faceLostTimer = null;
      _updateFaceAnchor(mesh, blendshapes: blendshapes);
    } catch (error, stackTrace) {
      if (_reportedTrackingError || !_active || _disposed) {
        return;
      }
      _reportedTrackingError = true;
      _pipeline = null;
      _pipelineFuture = null;
      unawaited(_closePipeline(pipeline));
      _reportError(
        ArViewException(
          ArViewErrorCode.faceTrackingFailed,
          'Face tracking stopped: $error',
          cause: error,
          stackTrace: stackTrace,
        ),
        stackTrace,
      );
    }
  }

  void _updateFaceAnchor(FaceMeshResult mesh, {FaceBlendshapes? blendshapes}) {
    if (_viewportSize.isEmpty) {
      return;
    }
    final ArFacePose? pose = ArFacePoseMapper(
      verticalFovDegrees: widget.cameraVerticalFovDegrees,
      anchorOrigin: widget.faceAnchorOrigin,
    ).map(mesh, viewportSize: _viewportSize);
    if (pose == null) {
      _markFaceLost();
      return;
    }

    final bool isNew = _faceAnchor == null;
    final ArFaceAnchor anchor = _faceAnchor ??= ArFaceAnchor._(
      _nextAnchorId++,
      Node(name: 'ar_face_anchor_${_nextAnchorId - 1}'),
      widget.faceAnchorOrigin,
    );
    anchor._update(
      transform: pose.transform,
      rotation: pose.rotation,
      screenPosition: pose.screenPosition,
      mesh: mesh,
      headPose: pose.headPose,
      blendshapes: blendshapes,
      distanceMeters: pose.distanceMeters,
      faceWidthMeters: pose.faceWidthMeters,
    );
    anchor.node.localTransform = pose.transform;

    if (isNew) {
      Node? node;
      try {
        node = widget.delegate?.nodeForFaceAnchor(widget, anchor);
      } catch (error, stackTrace) {
        _reportError(
          ArViewException(
            ArViewErrorCode.faceTrackingFailed,
            'nodeForFaceAnchor failed: $error',
            cause: error,
            stackTrace: stackTrace,
          ),
          stackTrace,
        );
      }
      if (node != null) {
        anchor._node = node;
        anchor.node.localTransform = pose.transform;
        if (anchor.node.name.isEmpty) {
          anchor.node.name = 'ar_face_anchor_${anchor.identifier}';
        }
      }
      widget.scene.add(anchor.node);
      if (kDebugMode) {
        _debugTraceSceneAnchor(anchor, 'added');
      }
      _safeDelegateCall(() {
        widget.delegate?.didAddNode(widget, anchor);
      });
    } else {
      _safeDelegateCall(() {
        widget.delegate?.didUpdateNode(widget, anchor);
      });
    }
    try {
      widget.onFaceAnchorUpdated?.call(anchor);
    } catch (error, stackTrace) {
      _reportCallbackError('onFaceAnchorUpdated', error, stackTrace);
    }
    if (kDebugMode) {
      final DateTime now = DateTime.now();
      if (_lastDebugTraceAt == null ||
          now.difference(_lastDebugTraceAt!) >= const Duration(seconds: 1)) {
        _lastDebugTraceAt = now;
        _debugTraceSceneAnchor(anchor, 'update');
      }
    }
    _refreshStatistics();
  }

  WidgetComponent? _findFirstWidgetComponent(Node node) {
    final WidgetComponent? direct = node
        .getComponents<WidgetComponent>()
        .firstOrNull;
    if (direct != null) {
      return direct;
    }
    for (final Node child in node.children) {
      final WidgetComponent? nested = _findFirstWidgetComponent(child);
      if (nested != null) {
        return nested;
      }
    }
    return null;
  }

  void _debugTraceSceneAnchor(ArFaceAnchor anchor, String stage) {
    final WidgetComponent? widgetComponent = _findFirstWidgetComponent(
      anchor.node,
    );
    final Vector3 position = anchor.transform.getTranslation();
    debugPrint(
      'ArView[$stage] node=${anchor.node.name} '
      'widgets=${widgetComponent == null ? 0 : 1} '
      'meshes=${anchor.node.getComponents<MeshComponent>().length} '
      'hosted=${widget.scene.renderScene.widgetComponents.length} '
      'items=${widget.scene.renderScene.items.length} '
      'captures=${widgetComponent?.controller.captureCount ?? -1} '
      'texture=${widgetComponent?.controller.texture != null} '
      'position=${position.x.toStringAsFixed(3)},'
      '${position.y.toStringAsFixed(3)},${position.z.toStringAsFixed(3)} '
      'screen=${anchor.screenPosition.dx.toStringAsFixed(3)},'
      '${anchor.screenPosition.dy.toStringAsFixed(3)} '
      'pose=${anchor.headPose.yawDegrees.toStringAsFixed(1)},'
      '${anchor.headPose.pitchDegrees.toStringAsFixed(1)},'
      '${anchor.headPose.rollDegrees.toStringAsFixed(1)} '
      'viewport=${_viewportSize.width.toStringAsFixed(0)}x'
      '${_viewportSize.height.toStringAsFixed(0)}',
    );
    if (stage == 'added') {
      Timer(const Duration(seconds: 2), () {
        if (!_disposed && identical(_faceAnchor, anchor)) {
          _debugTraceSceneAnchor(anchor, 'after2s');
        }
      });
    }
  }

  int? _rotationDegrees(
    CameraController controller,
    CameraDescription description,
  ) {
    final int? deviceRotation =
        _deviceOrientationDegrees[controller.value.deviceOrientation];
    if (deviceRotation == null) {
      return null;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      if (description.lensDirection == CameraLensDirection.front) {
        return (description.sensorOrientation + deviceRotation) % 360;
      }
      return (description.sensorOrientation - deviceRotation + 360) % 360;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return deviceRotation;
    }
    return 0;
  }

  FaceMeshFrame? _cameraImageToFaceMesh(CameraImage image) {
    final List<Plane> planes = image.planes;
    if (planes.isEmpty) {
      return null;
    }
    final ImageFormatGroup format = image.format.group;
    if (format == ImageFormatGroup.bgra8888) {
      final Plane plane = planes.first;
      return FaceMeshImage(
        pixels: plane.bytes,
        width: image.width,
        height: image.height,
        bytesPerRow: plane.bytesPerRow,
        pixelFormat: FaceMeshPixelFormat.bgra,
      );
    }
    if (format == ImageFormatGroup.nv21 || format == ImageFormatGroup.yuv420) {
      if (planes.length == 1) {
        return FaceMeshNv21Image.tryFromSinglePlane(
          bytes: planes.first.bytes,
          width: image.width,
          height: image.height,
          bytesPerRow: planes.first.bytesPerRow,
        );
      }
      if (planes.length == 2) {
        return FaceMeshNv21Image.tryFromYAndInterleavedVuPlanes(
          width: image.width,
          height: image.height,
          yPlane: _plane(planes[0]),
          vuPlane: _plane(planes[1]),
        );
      }
      return FaceMeshNv21Image.tryFromYuv420Planes(
        width: image.width,
        height: image.height,
        yPlane: _plane(planes[0]),
        uPlane: _plane(planes[1]),
        vPlane: _plane(planes[2]),
      );
    }
    return null;
  }

  FaceMeshImagePlane _plane(Plane plane) {
    return FaceMeshImagePlane(
      bytes: plane.bytes,
      bytesPerRow: plane.bytesPerRow,
      bytesPerPixel: plane.bytesPerPixel,
    );
  }

  void _markFaceLost() {
    if (_faceAnchor != null && _faceLostTimer == null) {
      _faceLostTimer = Timer(widget.anchorLostGracePeriod, () {
        _faceLostTimer = null;
        if (_active && !_disposed) {
          _removeFaceAnchor();
        }
      });
    }
    _refreshStatistics();
  }

  void _removeFaceAnchor({Scene? scene, bool notify = true}) {
    final ArFaceAnchor? anchor = _faceAnchor;
    if (anchor == null) {
      return;
    }
    _faceAnchor = null;
    (scene ?? widget.scene).remove(anchor.node);
    if (notify) {
      _safeDelegateCall(() {
        widget.delegate?.didRemoveNode(widget, anchor);
      });
      _refreshStatistics();
    }
  }

  void _recordInferenceFrame() {
    final DateTime now = DateTime.now();
    final DateTime? started = _fpsWindowStartedAt;
    if (started == null) {
      _fpsWindowStartedAt = now;
      _fpsFrames = 1;
      return;
    }
    _fpsFrames++;
    final double elapsed = now.difference(started).inMicroseconds / 1000000.0;
    if (elapsed >= 0.5) {
      _fps = _fpsFrames / elapsed;
      _fpsFrames = 0;
      _fpsWindowStartedAt = now;
      _refreshStatistics();
    }
  }

  void _refreshStatistics() {
    if (mounted && widget.showsStatistics) {
      _setState(() {});
    }
  }

  void _safeDelegateCall(VoidCallback callback) {
    try {
      callback();
    } catch (error, stackTrace) {
      _reportError(
        ArViewException(
          ArViewErrorCode.faceTrackingFailed,
          'An ArViewDelegate callback failed: $error',
          cause: error,
          stackTrace: stackTrace,
        ),
        stackTrace,
      );
    }
  }

  void _reportError(ArViewException error, StackTrace stackTrace) {
    _setState(() {
      _error = error;
      _initializing = false;
    });
    try {
      widget.onError?.call(error, stackTrace);
    } catch (callbackError, callbackStackTrace) {
      _reportCallbackError('onError', callbackError, callbackStackTrace);
    }
  }

  void _reportCallbackError(
    String callback,
    Object error,
    StackTrace stackTrace,
  ) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'flutter_ar',
        context: ErrorDescription('while calling ArView.$callback'),
      ),
    );
  }

  Future<void> _stopCamera() async {
    final CameraMacOSController? macOSController = _macOSCameraController;
    _macOSCameraController = null;
    final bool removedMacOSPreview = _macOSCameraRequested;
    _macOSCameraRequested = false;
    if (macOSController != null) {
      try {
        await macOSController.stopImageStream();
      } catch (_) {
        // The native camera may already have stopped its image stream.
      }
      try {
        await macOSController.destroy();
      } catch (_) {
        // The native camera may already have been disposed.
      }
    }
    if (removedMacOSPreview && mounted && !_disposed) {
      _setState(() {});
      await WidgetsBinding.instance.endOfFrame;
    }

    final CameraController? controller = _cameraController;
    _cameraController = null;
    if (controller == null) {
      return;
    }
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {
      // Disposal still has to run if streaming already stopped.
    }
    try {
      await controller.dispose();
    } catch (_) {
      // The embedder may already have disposed the camera.
    }
  }

  Future<void> _closePipeline(FaceMeshIsolatePipeline? pipeline) async {
    if (pipeline == null || pipeline.isClosed) {
      return;
    }
    try {
      await pipeline.close();
    } catch (_) {
      // A worker that already failed may have torn itself down.
    }
  }

  /// Retries camera startup after a denied permission or initialization error.
  Future<void> retry() async {
    _reportedTrackingError = false;
    final FaceMeshIsolatePipeline? pipeline = _pipeline;
    final Future<FaceMeshIsolatePipeline>? pendingPipeline = _pipelineFuture;
    _pipeline = null;
    _pipelineFuture = null;
    await _closePipeline(pipeline);
    if (pendingPipeline != null) {
      unawaited(
        pendingPipeline.then<void>(
          (FaceMeshIsolatePipeline pending) => _closePipeline(pending),
          onError: (Object _) {},
        ),
      );
    }
    await _start();
  }

  /// Opens the system settings page for this application.
  Future<void> openSettings() async {
    await openAppSettings();
  }

  void _setState(VoidCallback callback) {
    if (mounted && !_disposed) {
      setState(callback);
    }
  }

  /// The camera used to render this view.
  ///
  /// Its transform matches the camera preview: the camera is at the origin,
  /// looks toward +Z, and uses [ArView.cameraVerticalFovDegrees].
  PerspectiveCamera get pointOfView => PerspectiveCamera(
    fovRadiansY: widget.cameraVerticalFovDegrees * math.pi / 180.0,
    position: Vector3.zero(),
    target: Vector3(0.0, 0.0, 1.0),
    up: Vector3(0.0, 1.0, 0.0),
    fovNear: 0.02,
    fovFar: 20.0,
  );

  @override
  void dispose() {
    widget.controller?._detach(this);
    _disposed = true;
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    _faceLostTimer?.cancel();
    _faceLostTimer = null;
    _removeFaceAnchor(notify: false);
    final FaceMeshIsolatePipeline? pipeline = _pipeline;
    final Future<FaceMeshIsolatePipeline>? pendingPipeline = _pipelineFuture;
    _pipeline = null;
    _pipelineFuture = null;
    _closeBlendshapesProcessor();
    unawaited(_closePipeline(pipeline));
    if (pendingPipeline != null) {
      pendingPipeline.then<void>(
        (FaceMeshIsolatePipeline pending) => unawaited(_closePipeline(pending)),
        onError: (Object _) {},
      );
    }
    unawaited(_stopCamera());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        _viewportSize = constraints.biggest;
        final CameraController? controller = _cameraController;
        return ColoredBox(
          color: const Color(0xFF000000),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (widget.showCameraPreview &&
                  controller != null &&
                  controller.value.isInitialized)
                _CameraPreviewLayer(controller: controller),
              if (widget.showCameraPreview && _isMacOS && _macOSCameraRequested)
                _buildMacOSCameraPreview(context),
              Positioned.fill(
                child: IgnorePointer(
                  child: SceneView(
                    widget.scene,
                    maxFrameRate: widget.preferredFramesPerSecond.toDouble(),
                    camera: pointOfView,
                    loadingBuilder: (BuildContext context, double progress) =>
                        const SizedBox.shrink(),
                  ),
                ),
              ),
              if (_initializing && _error == null) _buildLoading(context),
              if (_error != null) _buildError(context, _error!),
              if (widget.showsStatistics) _buildStatistics(context),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMacOSCameraPreview(BuildContext context) {
    return ClipRect(
      child: CameraMacOSView(
        key: ValueKey<int>(_macOSCameraSession),
        fit: BoxFit.cover,
        cameraMode: CameraMacOSMode.photo,
        enableAudio: false,
        resolution: _macOSResolution(widget.cameraResolution),
        isVideoMirrored: true,
        onCameraInizialized: (CameraMacOSController controller) {
          if (!_active || _disposed || !_macOSCameraRequested) {
            unawaited(controller.destroy());
            return;
          }
          _macOSCameraController = controller;
          unawaited(_startMacOSImageStream(controller));
        },
        onCameraLoading: (Object? error) {
          _handleMacOSCameraInitError(error);
          return const SizedBox.expand();
        },
        onCameraDestroyed: () => const SizedBox.expand(),
      ),
    );
  }

  PictureResolution _macOSResolution(ResolutionPreset preset) {
    switch (preset) {
      case ResolutionPreset.low:
        return PictureResolution.low;
      case ResolutionPreset.medium:
        return PictureResolution.medium;
      case ResolutionPreset.high:
        return PictureResolution.high;
      case ResolutionPreset.veryHigh:
        return PictureResolution.veryHigh;
      case ResolutionPreset.ultraHigh:
        return PictureResolution.ultraHigh;
      case ResolutionPreset.max:
        return PictureResolution.max;
    }
  }

  Widget _buildLoading(BuildContext context) {
    return Center(
      child:
          widget.loadingBuilder?.call(context, 0.0) ??
          const _StatusPanel(
            title: 'Starting AR camera',
            message: 'Requesting camera access and loading face tracking…',
          ),
    );
  }

  Widget _buildError(BuildContext context, ArViewException error) {
    void retry() {
      unawaited(this.retry());
    }

    Future<void> settings() => openSettings();
    final Widget? custom = widget.errorBuilder?.call(
      context,
      error,
      retry,
      settings,
    );
    if (custom != null) {
      return custom;
    }
    return ColoredBox(
      color: const Color(0xE6000000),
      child: Center(
        child: _StatusPanel(
          title: 'AR camera unavailable',
          message: error.message,
          actions: <Widget>[
            _ArTextButton(label: 'Retry', onPressed: retry),
            if (error.canOpenSettings)
              _ArTextButton(
                label: 'Open Settings',
                onPressed: () {
                  unawaited(openSettings());
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatistics(BuildContext context) {
    final bool tracking = _faceAnchor != null;
    return SafeArea(
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0x99000000),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                child: Text(
                  '${tracking ? 'Face tracked' : 'Searching'}'
                  ' · ${_fps > 0 ? _fps.toStringAsFixed(1) : '--'} fps',
                  style: const TextStyle(
                    color: Color(0xFFFFFFFF),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CameraPreviewLayer extends StatelessWidget {
  const _CameraPreviewLayer({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CameraValue>(
      valueListenable: controller,
      builder: (BuildContext context, CameraValue value, Widget? child) {
        final Size? previewSize = value.previewSize;
        if (!value.isInitialized || previewSize == null) {
          return const SizedBox.shrink();
        }
        final Size layoutSize = arCameraPreviewLayoutSize(
          previewSize,
          value.deviceOrientation,
        );
        return ClipRect(
          child: SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox.fromSize(
                size: layoutSize,
                child: CameraPreview(controller),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.title,
    required this.message,
    this.actions = const <Widget>[],
  });

  final String title;
  final String message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xCC111111),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFFFFFFF),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xCCFFFFFF),
                  fontSize: 14,
                  height: 1.35,
                ),
              ),
              if (actions.isNotEmpty) const SizedBox(height: 16),
              if (actions.isNotEmpty)
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 8,
                  children: actions,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArTextButton extends StatelessWidget {
  const _ArTextButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0x33FFFFFF),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFFFFFFFF),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
