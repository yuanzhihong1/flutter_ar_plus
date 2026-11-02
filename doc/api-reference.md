# API 参考

本文描述 `flutter_ar_plus` 当前公开的稳定入口。所有库内类型均从以下入口导入：

```dart
import 'package:flutter_ar_plus/flutter_ar_plus.dart';
```

`ArView` 的参数和返回值会引用 `camera`、`flutter_scene`、`mediapipe_face_mesh` 与
`vector_math` 中的类型。应用直接使用这些类型时，应把它们声明为直接依赖。

## 坐标约定

### AR 相机空间

`ArView` 使用右手坐标系和米制单位：

| 轴或属性 | 约定 |
| --- | --- |
| 原点 | 相机位置 |
| `+X` | 画面右方 |
| `+Y` | 画面上方 |
| `+Z` | 远离相机 |
| 距离单位 | 米 |

`ArFaceAnchor.transform`、`ArFacePose.transform` 和 `ArFacePose.position` 均使用该空间。

### 内容局部空间

人脸节点使用 Flutter Scene 的标准局部坐标。内容正面应沿局部 `+Z` 朝向目标方向。头部偏航、
俯仰和翻滚会作为节点旋转同步到内容上。

`ArFaceAnchor.screenPosition` 是另一个坐标系：以视口左上角为原点，宽高归一化到 `0..1`。

## `ArView`

相机预览、人脸追踪与场景渲染的主组件。

### 构造参数

| 参数 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `scene` | `Scene` | 必填 | 应用持有的场景，`ArView` 不会释放 |
| `controller` | `ArViewController?` | `null` | 命令式场景控制器 |
| `delegate` | `ArViewDelegate?` | `null` | 创建并管理人脸节点 |
| `onFaceAnchorUpdated` | `ValueChanged<ArFaceAnchor>?` | `null` | 每次锚点更新后调用 |
| `cameraLensDirection` | `CameraLensDirection` | `front` | 首选相机方向 |
| `cameraResolution` | `ResolutionPreset` | `high` | 请求的相机分辨率 |
| `cameraVerticalFovDegrees` | `double` | `63` | 透视相机垂直视场角 |
| `preferredFramesPerSecond` | `int` | `60` | 首选处理与渲染帧率 |
| `anchorLostGracePeriod` | `Duration` | `350ms` | 人脸丢失后保留锚点的宽限期 |
| `faceTrackingEnabled` | `bool` | `true` | 是否运行人脸推理 |
| `enableFaceBlendshapes` | `bool` | `true` | 是否计算表情系数 |
| `anchorOrigin` | `ArFaceAnchorOrigin` | `faceCenter` | 锚点使用脸部中心或鼻尖 |
| `showCameraPreview` | `bool` | `true` | 是否显示相机画面 |
| `showTrackingIndicator` | `bool` | `false` | 未检测到人脸时是否显示小型指示器 |
| `loadingBuilder` | `ArViewLoadingBuilder?` | `null` | 自定义加载界面 |
| `errorBuilder` | `ArViewErrorBuilder?` | `null` | 自定义错误界面 |
| `onError` | `ArViewErrorCallback?` | `null` | 接收运行错误 |

`cameraVerticalFovDegrees` 必须位于 `(0, 180)`。`preferredFramesPerSecond` 必须大于 `0`。

`showTrackingIndicator` 只控制处理状态的视觉提示，不显示帧率、人脸数量或其他性能统计。

### 生命周期

1. `ArView` 挂载并请求相机权限。
2. 初始化相机、创建 MediaPipe 管线并开始处理图像帧。
3. 检测到人脸后创建 `ArFaceAnchor`。
4. 调用 `delegate.nodeForFaceAnchor` 获取要挂载的节点。
5. 将节点添加到 `scene`，然后调用 `delegate.didAddNode`。
6. 后续每帧更新锚点，并调用 `delegate.didUpdateNode` 与 `onFaceAnchorUpdated`。
7. 人脸持续丢失超过 `anchorLostGracePeriod` 后移除节点并调用 `delegate.didRemoveNode`。

应用进入后台时，视图会停止相机并移除当前锚点；恢复到前台后自动重新启动。视图销毁时也会
关闭自身创建的相机控制器、MediaPipe 管线和表情处理器。

### 回调类型

```dart
typedef ArViewLoadingBuilder = Widget Function(
  BuildContext context,
  double progress,
);

typedef ArViewErrorCallback = void Function(
  Object error,
  StackTrace stackTrace,
);

typedef ArViewErrorBuilder = Widget Function(
  BuildContext context,
  ArViewException error,
  VoidCallback retry,
  Future<void> Function() openSettings,
);
```

`progress` 当前固定为 `0.0`，预留给后续增量初始化进度。`retry` 会重新启动相机与追踪，
`openSettings` 会打开当前应用的系统设置页面。

未提供 `errorBuilder` 时，库会显示包含错误文案、重试按钮和可选设置入口的内置错误界面。
若 `onError` 自身抛错，异常通过 `FlutterError.reportError` 报告，避免递归调用同一个错误回调。

## `ArViewDelegate`

人脸节点创建与生命周期委托。所有方法都有默认实现。

```dart
abstract class ArViewDelegate {
  const ArViewDelegate();

  Node? nodeForFaceAnchor(ArView view, ArFaceAnchor anchor) => null;

  void didAddNode(ArView view, ArFaceAnchor anchor) {}

  void didUpdateNode(ArView view, ArFaceAnchor anchor) {}

  void didRemoveNode(ArView view, ArFaceAnchor anchor) {}
}
```

| 方法 | 调用时机 | 说明 |
| --- | --- | --- |
| `nodeForFaceAnchor` | 新锚点首次出现 | 返回要挂载的节点；返回 `null` 时保留空追踪节点 |
| `didAddNode` | 节点加入场景后 | 可在此初始化只执行一次的状态 |
| `didUpdateNode` | 每帧锚点更新后 | 可驱动动画、材质或自定义组件 |
| `didRemoveNode` | 锚点被移除后 | 释放与本次追踪周期绑定的资源 |

委托抛出的异常会包装为 `ArViewException`，错误码为
`ArViewErrorCode.faceTrackingFailed`。

## `ArFaceAnchor`

一次连续人脸追踪周期内保持稳定的锚点对象。

| 成员 | 类型 | 说明 |
| --- | --- | --- |
| `identifier` | `int` | 连续追踪期间稳定的标识符 |
| `origin` | `ArFaceAnchorOrigin` | 当前锚点原点 |
| `node` | `Node` | 挂载在场景中的人脸节点 |
| `transform` | `Matrix4` | AR 相机空间中的完整变换 |
| `rotation` | `Quaternion` | AR 相机空间中的旋转 |
| `position` | `Vector3` | AR 相机空间中的锚点位置 |
| `screenPosition` | `Offset` | 左上角为原点的归一化屏幕位置 |
| `distanceMeters` | `double` | 估计的脸部中心相机距离 |
| `faceWidthMeters` | `double` | 估计的实际脸宽 |
| `mesh` | `FaceMeshResult` | 当前 MediaPipe 推断结果 |
| `headPose` | `FaceMeshHeadPose` | 当前头部姿态估计 |
| `landmarks` | `List<FaceMeshLandmark>` | 当前人脸关键点列表 |
| `blendshapes` | `FaceBlendshapes?` | 当前表情系数 |

`transform`、`rotation` 和 `position` 返回副本，修改返回值不会改变内部追踪状态。

`mesh`、`headPose` 和 `landmarks` 在锚点首次交给回调后可用。`blendshapes` 仅在启用
`enableFaceBlendshapes` 且当前帧计算成功时非空。表情关键名由依赖包中的
`FaceBlendshape` 枚举定义。

锚点对象只在对应追踪周期内有效。不要在 `didRemoveNode` 之后继续持有节点并假设其仍属于场景。

## `ArViewController`

为场景和屏幕空间查询提供命令式 API。

```dart
final controller = ArViewController(scene: scene);
```

传入的 `Scene` 必须与 `ArView.scene` 为同一个对象。控制器不会释放场景。

### 状态

| 成员 | 类型 | 说明 |
| --- | --- | --- |
| `scene` | `Scene` | 控制器操作的场景 |
| `isAttached` | `bool` | 是否已挂载到存活的 `ArView` |
| `isTracking` | `bool` | 当前是否有人脸锚点 |
| `currentFaceAnchor` | `ArFaceAnchor?` | 当前人脸锚点 |

`isTracking` 和 `currentFaceAnchor` 在未挂载时安全返回 `false` 与 `null`。

### 节点管理

| 方法 | 返回值 | 说明 |
| --- | --- | --- |
| `addNode` | `Node` | 添加节点并应用可选局部变换 |
| `addModel` | `Future<Node>` | 加载 `.glb` 资源并添加节点 |
| `removeNode` | `void` | 从场景或父节点中移除节点 |
| `nodeNamed` | `Node?` | 按名称查找第一个节点 |
| `setPosition` | `void` | 设置局部位置 |
| `moveNode` | `void` | 对局部位置增加偏移 |
| `setRotation` | `void` | 设置局部旋转 |
| `setScale` | `void` | 设置局部缩放 |
| `setTransform` | `void` | 替换局部变换 |
| `setWorldPosition` | `void` | 设置世界空间位置 |
| `setWorldTransform` | `void` | 替换世界空间变换 |
| `getWorldPosition` | `Vector3` | 获取世界空间位置 |

`addNode` 会拒绝已经属于其他场景的节点。对于未命名节点，它会生成 `ar_node_N` 形式的名称；
显式名称会先去除首尾空白。

`addModel` 的 `position` 默认是 `Vector3(0, 0, 1)`，即相机前方一米处。模型解析失败时抛出
带 `ArViewErrorCode.modelLoadFailed` 的 `ArViewException`。

### 视图相关能力

以下成员要求控制器已挂载到 `ArView`，否则抛出 `StateError`：

| 成员 | 说明 |
| --- | --- |
| `viewportSize` | 当前逻辑视口尺寸 |
| `camera` | 当前 Flutter Scene 透视相机 |
| `retry` | 重新启动相机和追踪 |
| `openSettings` | 打开系统应用设置 |
| `projectPoint` | 将世界点投影为逻辑屏幕坐标；相机后方返回 `null` |
| `unprojectPoint` | 将屏幕点转换为指定相机距离的世界点 |
| `hitTest` | 返回射线命中的最近表面 |
| `hitTestAll` | 返回射线命中的所有表面，按距离排序 |

`unprojectPoint` 的 `distance` 必须为有限正数。`hitTest` 只对 Flutter Scene 中的几何体执行
射线检测，不推断真实世界深度。

## `ArFacePoseMapper`

将单个 `FaceMeshResult` 映射到与 `ArView` 相同的米制相机空间。该类型不依赖相机或渲染器，
适合静态图片、离线处理和自定义渲染管线。

```dart
const mapper = ArFacePoseMapper(
  verticalFovDegrees: 63,
  anchorOrigin: ArFaceAnchorOrigin.faceCenter,
);

final pose = mapper.map(mesh, viewportSize: viewportSize);
if (pose != null) {
  node.localTransform = pose.transform;
}
```

| 参数 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `verticalFovDegrees` | `double` | `63` | 相机垂直视场角 |
| `anchorOrigin` | `ArFaceAnchorOrigin` | `faceCenter` | 输出锚点原点 |

`map` 在以下情况返回 `null`：

- 视口宽或高不大于 `0`。
- 图像宽或高不大于 `0`。
- 关键点数量不足。
- 人脸投影宽度过小或没有实际意义。

## `ArFacePose`

`ArFacePoseMapper.map` 的成功结果。

| 成员 | 类型 | 说明 |
| --- | --- | --- |
| `transform` | `Matrix4` | AR 相机空间完整变换 |
| `rotation` | `Quaternion` | 人脸旋转 |
| `position` | `Vector3` | 锚点位置 |
| `screenPosition` | `Offset` | 归一化屏幕位置 |
| `headPose` | `FaceMeshHeadPose` | MediaPipe 头部姿态 |
| `distanceMeters` | `double` | 估计的脸部中心距离 |
| `faceWidthMeters` | `double` | 估计脸宽 |

## `ArFaceAnchorOrigin`

| 值 | 说明 |
| --- | --- |
| `faceCenter` | 默认值；锚点位于估计的脸部中心 |
| `noseTip` | 锚点位于鼻尖表面，适合直接定位鼻部内容 |

切换 `ArView.anchorOrigin` 时，当前锚点会被移除，并在下一帧按新原点重新创建。

## `ArViewException`

相机、追踪或模型加载失败时报告的统一异常类型。

```dart
class ArViewException implements Exception {
  const ArViewException(
    this.code,
    this.message, {
    this.cause,
    this.stackTrace,
  });

  final ArViewErrorCode code;
  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  bool get canOpenSettings;

  @override
  String toString();
}
```

`canOpenSettings` 仅对权限相关错误返回 `true`。

| 错误码 | 说明 |
| --- | --- |
| `cameraPermissionDenied` | 相机权限被拒绝 |
| `cameraPermissionPermanentlyDenied` | 相机权限被永久拒绝 |
| `cameraPermissionRestricted` | 相机访问受设备策略限制 |
| `cameraUnavailable` | 没有可用相机 |
| `cameraInitializationFailed` | 相机初始化或图像流失败 |
| `faceTrackingFailed` | MediaPipe 管线或追踪回调失败 |
| `modelLoadFailed` | glTF/GLB 模型加载失败 |
| `unsupportedPlatform` | 当前平台不支持 |

## 兼容性说明

公开 API 会在 `CHANGELOG.md` 中记录变更。自 `1.0.0` 起，不兼容的公开 API 变更会提升主版本号，
迁移方式见 [迁移指南](migration-guide.md)。

库内 `lib/src/` 文件、原生通道名称和平台插件内部类不属于公开兼容范围。
