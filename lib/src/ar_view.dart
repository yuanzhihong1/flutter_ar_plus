import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:camera_macos/camera_macos.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:flutter/widgets.dart' hide Matrix4;
import 'package:flutter_scene/scene.dart' hide CameraController;
import 'package:mediapipe_face_mesh/mediapipe_face_mesh.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Quaternion, Vector3;

import 'ar_face_pose.dart';
import 'ar_view_layout.dart';

/// 构建相机或人脸追踪管线启动期间显示的内容。
typedef ArViewLoadingBuilder = Widget Function(
  BuildContext context,
  double progress,
);

/// 接收 [ArView] 运行期间未包装异常的处理器。
typedef ArViewErrorCallback = void Function(
  Object error,
  StackTrace stackTrace,
);

/// 构建相机访问或人脸追踪失败时显示的错误界面。
typedef ArViewErrorBuilder = Widget Function(
  BuildContext context,
  ArViewException error,
  VoidCallback retry,
  Future<void> Function() openSettings,
);

/// [ArView] 无法启动或继续追踪的原因。
enum ArViewErrorCode {
  /// 相机权限请求被拒绝。
  cameraPermissionDenied,

  /// 用户需要在系统设置中手动开启相机权限。
  cameraPermissionPermanentlyDenied,

  /// 相机访问受到设备策略或家长控制限制。
  cameraPermissionRestricted,

  /// 平台没有提供可用的相机。
  cameraUnavailable,

  /// 相机初始化或图像流启动失败。
  cameraInitializationFailed,

  /// MediaPipe 人脸追踪管线失败。
  faceTrackingFailed,

  /// 无法加载 glTF/GLB 模型。
  modelLoadFailed,

  /// 当前平台不提供所需的相机或 FFI 支持。
  unsupportedPlatform,
}

/// 由 [ArView] 对外报告的异常。
class ArViewException implements Exception {
  /// 创建 AR 视图异常。
  const ArViewException(this.code, this.message, {this.cause, this.stackTrace});

  /// 可供程序判断的失败类别。
  final ArViewErrorCode code;

  /// 面向用户的错误说明。
  final String message;

  /// 原始异常（如果存在）。
  final Object? cause;

  /// 原始堆栈信息（如果存在）。
  final StackTrace? stackTrace;

  /// 当前错误是否适合引导用户打开系统应用设置。
  bool get canOpenSettings =>
      code == ArViewErrorCode.cameraPermissionDenied ||
      code == ArViewErrorCode.cameraPermissionPermanentlyDenied ||
      code == ArViewErrorCode.cameraPermissionRestricted;

  @override
  String toString() => 'ArViewException($code): $message';
}

/// 接收 [ArView] 节点与人脸锚点生命周期回调的委托。
///
/// 视图负责人脸追踪和锚点更新，委托负责创建并管理放置在锚点上的场景节点。
/// 一个视图只能使用一个委托；需要在运行时切换节点时，可通过
/// [ArView.controller] 操作场景。
abstract class ArViewDelegate {
  /// 创建 AR 视图委托。
  const ArViewDelegate();

  /// 为首次获取的人脸锚点返回要渲染的节点。
  ///
  /// 返回的节点会自动挂载到 [ArView.scene]。可以向节点添加网格、模型、
  /// 粒子或 [WidgetComponent]。返回 `null` 时仅保留一个空的追踪节点。
  Node? nodeForFaceAnchor(ArView view, ArFaceAnchor anchor) => null;

  /// 在 [anchor] 对应的节点挂载到场景后调用。
  void didAddNode(ArView view, ArFaceAnchor anchor) {}

  /// 人脸变换或关键点更新时调用。
  ///
  /// 此时节点位置已经更新，可用于驱动动画或渲染器特效。
  void didUpdateNode(ArView view, ArFaceAnchor anchor) {}

  /// 在人脸锚点及其节点被移除后调用。
  void didRemoveNode(ArView view, ArFaceAnchor anchor) {}
}

/// 为 [ArView] 提供命令式控制能力的控制器。
///
/// 控制器直接操作由应用持有的 [Scene]，因此可以在视图挂载前预先添加节点。
/// 只有 [projectPoint]、[hitTest] 等屏幕空间查询需要视图已挂载。
///
/// 所有位置均使用 AR 相机空间：相机位于原点，+X 向右，+Y 向上，
/// +Z 指向远离相机的方向。对于挂载在其他节点下的节点，[setPosition]
/// 修改的是相对父节点的位置。
///
/// ```dart
/// final scene = Scene();
/// final arController = ArViewController(scene: scene);
///
/// arController.addNode(
///   Node(name: 'cube')..addComponent(
///     MeshComponent(Mesh(CuboidGeometry(Vector3.all(0.2)), material)),
///   ),
///   position: Vector3(0, 0, 1),
/// );
///
/// ArView(scene: scene, controller: arController);
/// ```
class ArViewController {
  /// 创建由 [scene] 提供场景支持的控制器。
  ///
  /// 必须将同一个场景传给 [ArView.scene]。场景由应用持有，控制器和视图
  /// 都不会主动释放它。
  ArViewController({required this.scene});

  /// 此控制器操作的场景。
  final Scene scene;

  _ArViewState? _view;
  int _nextGeneratedName = 1;

  /// 控制器当前是否已挂载到 [ArView]。
  bool get isAttached => _view?.mounted ?? false;

  /// 当前是否检测到人脸。
  ///
  /// 视图未挂载或尚未检测到人脸时返回 `false`。
  bool get isTracking => currentFaceAnchor != null;

  /// 当前追踪到的人脸锚点。
  ///
  /// 视图未挂载或未检测到人脸时返回 `null`。
  ArFaceAnchor? get currentFaceAnchor {
    final _ArViewState? view = _view;
    return view != null && view.mounted ? view._faceAnchor : null;
  }

  /// 已挂载视图当前使用的逻辑尺寸。
  ///
  /// 视图尚未挂载时调用会抛出 [StateError]。
  Size get viewportSize {
    final _ArViewState view = _requireView();
    return view._viewportSize;
  }

  /// 用于渲染 AR 场景的透视相机。
  ///
  /// 视图尚未挂载时调用会抛出 [StateError]。
  PerspectiveCamera get camera => _requireView().camera;

  /// 重新启动相机与人脸追踪。
  ///
  /// 适用于权限恢复或初始化失败后的重试场景。
  Future<void> retry() => _requireView()._retry();

  /// 打开当前应用对应的系统设置页面。
  Future<void> openSettings() => _requireView()._openSettings();

  /// 将 [node] 添加到 [scene] 根节点，并应用可选的局部变换。
  ///
  /// 如果 [node] 已属于当前场景，此方法只更新其位置，不会重复添加。
  /// 属于其他场景的节点会被拒绝。
  ///
  /// 建议传入明确的相机空间 [position]。常见可见位置是
  /// `Vector3(0, 0, 1)`，即相机前方一米处。
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

  /// 加载运行时 glTF 二进制文件（`.glb`）并添加到相机前方。
  ///
  /// [position] 默认为 `Vector3(0, 0, 1)`，即模型位于相机前方一米处。
  /// 若模型使用了不同的单位尺寸，可通过 [scale] 调整。
  ///
  /// 资源无法解析时抛出带 [ArViewErrorCode.modelLoadFailed] 的
  /// [ArViewException]。
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
        '无法加载模型“$assetPath”：$error',
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

  /// 从场景中移除 [node]；节点已经脱离时不做任何操作。
  void removeNode(Node node) {
    if (node.parent != null) {
      node.detach();
    }
  }

  /// 在场景图中查找第一个名称为 [name] 的节点。
  Node? nodeNamed(String name) => scene.root.getChildByName(name);

  /// 设置 [node] 相对父节点的位置。
  void setPosition(Node node, Vector3 position) {
    node.position = position.clone();
  }

  /// 按相对父节点的 [offset] 移动 [node]。
  void moveNode(Node node, Vector3 offset) {
    node.position = node.position + offset;
  }

  /// 设置 [node] 的局部旋转。
  void setRotation(Node node, Quaternion rotation) {
    node.rotation = rotation.clone();
  }

  /// 设置 [node] 的局部缩放。
  void setScale(Node node, Vector3 scale) {
    node.scale = scale.clone();
  }

  /// 替换 [node] 的局部变换。
  void setTransform(Node node, Matrix4 transform) {
    node.localTransform = transform.clone();
  }

  /// 设置 [node] 的世界坐标位置，并正确处理父节点变换。
  void setWorldPosition(Node node, Vector3 position) {
    final Matrix4 transform = node.globalTransform.clone()
      ..setTranslation(position);
    node.globalTransform = transform;
  }

  /// 替换 [node] 的世界空间变换。
  void setWorldTransform(Node node, Matrix4 transform) {
    node.globalTransform = transform.clone();
  }

  /// 返回 [node] 在 AR 相机空间中的世界坐标位置。
  Vector3 getWorldPosition(Node node) => node.globalTransform.getTranslation();

  /// 将世界空间点投影为逻辑视口坐标。
  ///
  /// 点位于相机平面或其后方时返回 `null`。
  Offset? projectPoint(Vector3 point) {
    final _ArViewState view = _requireView();
    if (view._viewportSize.isEmpty) {
      return null;
    }
    return view.camera.worldToScreen(point, view._viewportSize);
  }

  /// 将逻辑视口点转换为距离相机 [distance] 米的世界空间点。
  ///
  /// 此方法假设目标点在给定深度平面上，不执行真实深度检测。
  /// 视图尚未挂载时抛出 [StateError]。
  Vector3 unprojectPoint(Offset point, {double distance = 1.0}) {
    if (!distance.isFinite || distance <= 0) {
      throw ArgumentError.value(distance, 'distance', 'distance 必须大于 0。');
    }
    final _ArViewState view = _requireView();
    return view.camera.screenPointToRay(point, view._viewportSize).at(distance);
  }

  /// 返回 [point] 下方最近的已渲染表面；没有命中时返回 `null`。
  ///
  /// 此方法对场景执行网格射线检测，不包含相机画面或环境深度信息。
  SceneRaycastHit? hitTest(Offset point) {
    final _ArViewState view = _requireView();
    if (view._viewportSize.isEmpty) {
      return null;
    }
    return scene.raycast(
      view.camera.screenPointToRay(point, view._viewportSize),
    );
  }

  /// 返回 [point] 下方的所有已渲染表面，按由近到远排序。
  List<SceneRaycastHit> hitTestAll(Offset point) {
    final _ArViewState view = _requireView();
    if (view._viewportSize.isEmpty) {
      return const <SceneRaycastHit>[];
    }
    return scene.raycastAll(
      view.camera.screenPointToRay(point, view._viewportSize),
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
      throw ArgumentError.value(node, 'node', '该节点已属于另一个场景。');
    }
  }

  _ArViewState _requireView() {
    final _ArViewState? view = _view;
    if (view == null || !view.mounted) {
      throw StateError(
        'ArViewController 尚未附加到 ArView。'
        '请将其传给 ArView.controller，并等待视图完成挂载。',
      );
    }
    return view;
  }

  void _attach(_ArViewState view) {
    final _ArViewState? attached = _view;
    if (attached != null && !identical(attached, view)) {
      throw StateError('ArViewController 已附加到另一个 ArView。');
    }
    if (!identical(scene, view.widget.scene)) {
      throw StateError('ArViewController.scene 必须与传给 ArView 的 Scene 相同。');
    }
    _view = view;
  }

  void _detach(_ArViewState view) {
    if (identical(_view, view)) {
      _view = null;
    }
  }
}

/// 由 Flutter Scene [Node] 承载的已追踪人脸锚点。
///
/// 变换使用 AR 相机空间，单位为米：+X 向右，+Y 向上，+Z 远离相机。
/// 节点会跟随估计的头部姿态，并根据 [origin] 放置在鼻尖或脸部中心。
/// 子内容应遵循 Flutter Scene 局部 +Z 朝前的约定，使其正面始终朝向
/// 被追踪者注视的方向。
class ArFaceAnchor {
  ArFaceAnchor._(this.identifier, this._node, this.origin);

  /// 人脸持续被追踪期间保持稳定的标识符。
  final int identifier;

  /// 此锚点使用的坐标系原点。
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

  /// 挂载在此锚点上的场景节点。
  Node get node => _node;

  /// 当前锚点的 AR 相机空间变换。
  Matrix4 get transform => _transform.clone();

  /// 当前锚点旋转。
  Quaternion get rotation => _rotation.clone();

  /// 当前锚点在 AR 相机空间中的位置，单位为米。
  Vector3 get position => _transform.getTranslation();

  /// 锚点在归一化显示坐标中的位置，原点位于左上角。
  Offset get screenPosition => _screenPosition;

  /// 估计的相机距离，单位为米。
  double get distanceMeters => _distanceMeters;

  /// 估计的实际脸宽，单位为米。
  double get faceWidthMeters => _faceWidthMeters;

  /// 当前 MediaPipe 人脸网格。
  FaceMeshResult get mesh => _mesh!;

  /// 当前头部旋转估计。
  FaceMeshHeadPose get headPose => _headPose!;

  /// 当前帧的 MediaPipe 面部表情系数。
  ///
  /// 仅在启用 [ArView.enableFaceBlendshapes] 时非空。关键名和数量由
  /// MediaPipe Face Landmarker 提供，可用于驱动表情动画。
  FaceBlendshapes? get blendshapes => _blendshapes;

  /// 当前帧的全部 478 个人脸关键点。
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

/// 基于相机的人脸 AR 视图。
///
/// [ArView] 负责相机预览、MediaPipe 人脸追踪，以及将人脸关键点映射到
/// Flutter Scene 透视相机。[scene] 由应用持有。检测到人脸时，视图会创建
/// 一个持久的 [ArFaceAnchor.node] 并在每次推理后更新其变换。默认锚点位于
/// 脸部中心；需要鼻尖锚点时可显式将 [anchorOrigin] 设为
/// [ArFaceAnchorOrigin.noseTip]。
///
/// 人脸追踪在独立工作 isolate 中运行。创建相机控制器前，视图会通过
/// `permission_handler` 请求相机权限。
class ArView extends StatefulWidget {
  /// 创建人脸 AR 视图。
  const ArView({
    super.key,
    required this.scene,
    this.controller,
    this.delegate,
    this.onFaceAnchorUpdated,
    this.cameraLensDirection = CameraLensDirection.front,
    this.cameraResolution = ResolutionPreset.high,
    this.cameraVerticalFovDegrees = 63,
    this.preferredFramesPerSecond = 60,
    this.anchorLostGracePeriod = const Duration(milliseconds: 350),
    this.faceTrackingEnabled = true,
    this.enableFaceBlendshapes = true,
    this.anchorOrigin = ArFaceAnchorOrigin.faceCenter,
    this.showCameraPreview = true,
    this.showTrackingIndicator = false,
    this.loadingBuilder,
    this.errorBuilder,
    this.onError,
  }) : assert(
         cameraVerticalFovDegrees > 0 && cameraVerticalFovDegrees < 180,
         'cameraVerticalFovDegrees 必须大于 0 且小于 180。',
       ),
       assert(preferredFramesPerSecond > 0, 'preferredFramesPerSecond 必须大于 0。');

  /// 由应用持有、叠加在相机画面上的 Flutter Scene 场景。
  final Scene scene;

  /// 用于添加、移除和移动场景节点的命令式控制器。
  ///
  /// 控制器必须使用同一个 [scene]。在视图挂载前，也可用它执行节点和变换
  /// 相关操作。
  final ArViewController? controller;

  /// 接收节点与人脸锚点生命周期回调的委托。
  final ArViewDelegate? delegate;

  /// 每次人脸追踪更新后调用。
  final ValueChanged<ArFaceAnchor>? onFaceAnchorUpdated;

  /// 优先使用的物理相机；找不到时回退到第一个可用相机。
  final CameraLensDirection cameraLensDirection;

  /// 请求的相机分辨率。
  ///
  /// 默认使用 [ResolutionPreset.high]。提高分辨率通常能改善小脸或远处
  /// 人脸的追踪质量，但也会增加相机、格式转换和推理开销。
  final ResolutionPreset cameraResolution;

  /// 追踪透视相机使用的垂直视场角。
  ///
  /// 已知相机真实垂直视场角时应显式设置。默认值 63° 与 MediaPipe
  /// 参考相机一致。
  final double cameraVerticalFovDegrees;

  /// 相机、人脸追踪和场景渲染的首选帧率。
  ///
  /// 相机帧会按此频率采样后送入 MediaPipe，Flutter Scene 也会限制到相同
  /// 帧率。移动设备上的实际帧率仍受相机、推理耗时和渲染负载限制。
  final int preferredFramesPerSecond;

  /// 人脸丢失后保留锚点的时间。
  final Duration anchorLostGracePeriod;

  /// 是否启用人脸推理。
  final bool faceTrackingEnabled;

  /// 是否计算 MediaPipe 面部表情系数。
  ///
  /// 该选项会增加每帧推理开销；不需要表情时建议显式关闭。最新系数可通过
  /// [ArFaceAnchor.blendshapes] 获取。默认开启，以提供开箱即用的表情数据。
  final bool enableFaceBlendshapes;

  /// [ArFaceAnchor.node] 和 [ArFaceAnchor.transform] 使用的锚点原点。
  ///
  /// 默认使用 [ArFaceAnchorOrigin.faceCenter]。需要直接定位鼻部挂件时，
  /// 可切换为 [ArFaceAnchorOrigin.noseTip]。
  final ArFaceAnchorOrigin anchorOrigin;

  /// 是否在场景后方显示实时相机画面。
  final bool showCameraPreview;

  /// 是否在人脸尚未追踪到时显示小型活动指示器。
  ///
  /// 该选项不会显示帧率、人脸数量或其他性能统计。
  final bool showTrackingIndicator;

  /// 可选的自定义加载界面。当前相机启动进度固定为 0。
  final ArViewLoadingBuilder? loadingBuilder;

  /// 可选的自定义错误界面。
  final ArViewErrorBuilder? errorBuilder;

  /// 报告相机和追踪错误。
  final ArViewErrorCallback? onError;

  @override
  State<ArView> createState() => _ArViewState();
}

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
    if (oldWidget.faceTrackingEnabled && !widget.faceTrackingEnabled) {
      _removeFaceAnchor();
    }
    if (oldWidget.anchorOrigin != widget.anchorOrigin) {
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
        debugPrint('ArView：人脸表情系数已禁用：$error');
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
        '相机权限已被永久拒绝，请在系统设置中开启。',
      );
    }
    if (status.isRestricted) {
      throw const ArViewException(
        ArViewErrorCode.cameraPermissionRestricted,
        '当前设备限制了相机访问。',
      );
    }
    throw const ArViewException(
      ArViewErrorCode.cameraPermissionDenied,
      '相机访问被拒绝。',
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
          'ArView 当前支持 Android、iOS 和 macOS。',
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
                    '无法启动 MediaPipe 人脸追踪：$error',
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
          '当前设备没有可用相机。',
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
          '无法启动 MediaPipe 人脸追踪：$error',
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
                '无法启动相机：$error',
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
    if (!_active || !widget.faceTrackingEnabled) {
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
          '无法启动 macOS 相机图像流：$error',
          cause: error,
          stackTrace: stackTrace,
        ),
        stackTrace,
      );
    }
  }

  void _handleMacOSCameraFrame(CameraImageData? image) {
    if (image == null || !_active || !widget.faceTrackingEnabled) {
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
        // CameraMacOSView 会同时镜像预览画面与 BGRA 图像流。
        // 若再次让 MediaPipe 执行镜像，关键点会移动到预览画面的另一侧。
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
        'macOS 相机图像流已停止：$error',
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
      // camera_macos 当前以英文错误信息报告权限问题，此处保留英文关键字匹配。
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
          permissionDenied ? '相机访问被拒绝，请在系统设置中开启。' : '无法初始化 macOS 相机：$message',
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
          '人脸追踪已停止：$error',
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
      anchorOrigin: widget.anchorOrigin,
    ).map(mesh, viewportSize: _viewportSize);
    if (pose == null) {
      _markFaceLost();
      return;
    }

    final bool isNew = _faceAnchor == null;
    final ArFaceAnchor anchor = _faceAnchor ??= ArFaceAnchor._(
      _nextAnchorId++,
      Node(name: 'ar_face_anchor_${_nextAnchorId - 1}'),
      widget.anchorOrigin,
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
            'nodeForFaceAnchor 回调失败：$error',
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
    _refreshTrackingIndicator();
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
    _refreshTrackingIndicator();
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
      _refreshTrackingIndicator();
    }
  }

  void _refreshTrackingIndicator() {
    if (mounted && widget.showTrackingIndicator) {
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
          'ArViewDelegate 回调执行失败：$error',
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
        library: 'flutter_ar_plus',
        context: ErrorDescription('调用 ArView.$callback 时'),
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
        // 原生相机可能已经停止图像流。
      }
      try {
        await macOSController.destroy();
      } catch (_) {
        // 原生相机可能已经被释放。
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
      // 即使图像流已经停止，也必须继续释放控制器。
    }
    try {
      await controller.dispose();
    } catch (_) {
      // 嵌入层可能已经释放了相机。
    }
  }

  Future<void> _closePipeline(FaceMeshIsolatePipeline? pipeline) async {
    if (pipeline == null || pipeline.isClosed) {
      return;
    }
    try {
      await pipeline.close();
    } catch (_) {
      // 已失败的工作 isolate 可能已经自行清理。
    }
  }

  /// 在权限被拒绝或初始化失败后重试启动相机。
  Future<void> _retry() async {
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

  /// 打开当前应用对应的系统设置页面。
  Future<void> _openSettings() async {
    await openAppSettings();
  }

  void _setState(VoidCallback callback) {
    if (mounted && !_disposed) {
      setState(callback);
    }
  }

  /// 用于渲染此视图的透视相机。
  ///
  /// 其变换与相机预览一致：相机位于原点、朝向 +Z，并使用
  /// [ArView.cameraVerticalFovDegrees] 作为垂直视场角。
  PerspectiveCamera get camera => PerspectiveCamera(
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
                    camera: camera,
                    loadingBuilder: (BuildContext context, double progress) =>
                        const SizedBox.shrink(),
                  ),
                ),
              ),
              if (_initializing && _error == null) _buildLoading(context),
              if (_error != null) _buildError(context, _error!),
              if (widget.showTrackingIndicator)
                _buildTrackingIndicator(context),
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
          const SizedBox.square(
            dimension: 28,
            child: material.CircularProgressIndicator(strokeWidth: 2.5),
          ),
    );
  }

  Widget _buildError(BuildContext context, ArViewException error) {
    void retry() {
      unawaited(_retry());
    }

    Future<void> settings() => _openSettings();
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
      child: material.Material(
        type: material.MaterialType.transparency,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  error.message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFFFFFFF),
                    fontSize: 16,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  children: <Widget>[
                    material.TextButton(
                      onPressed: retry,
                      child: const Text('重试'),
                    ),
                    if (error.canOpenSettings)
                      material.TextButton(
                        onPressed: () {
                          unawaited(settings());
                        },
                        child: const Text('打开设置'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTrackingIndicator(BuildContext context) {
    if (_faceAnchor != null) {
      return const SizedBox.shrink();
    }
    return const SafeArea(
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: EdgeInsets.all(12),
          child: IgnorePointer(
            child: SizedBox.square(
              dimension: 16,
              child: material.CircularProgressIndicator(strokeWidth: 2),
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
