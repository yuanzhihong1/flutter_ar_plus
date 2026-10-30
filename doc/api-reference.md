# API 参考

本文描述 `flutter_ar` 的稳定公开 API。所有类型均从以下入口导出：

```dart
import 'package:flutter_ar/flutter_ar.dart';
```

## 坐标约定

`ArView` 使用米制 AR 相机空间：

- 相机位于原点。
- `+X` 向右。
- `+Y` 向上。
- `+Z` 远离相机。
- 所有位置和距离使用米。

人脸内容使用 Flutter Scene 的局部 `+Z` 朝前约定。模型作者的正面应沿局部 `+Z` 方向，这样内容
正面会与真实人脸朝向一致。

## `ArView`

相机人脸 AR 的主组件。

### 构造参数

| 参数 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `scene` | `Scene` | 必填 | 应用持有的场景，视图不会释放它 |
| `controller` | `ArViewController?` | `null` | 命令式节点控制器 |
| `delegate` | `ArViewDelegate?` | `null` | 人脸节点生命周期委托 |
| `onFaceAnchorUpdated` | `ValueChanged<ArFaceAnchor>?` | `null` | 每帧锚点更新回调 |
| `cameraLensDirection` | `CameraLensDirection` | `front` | 首选相机方向 |
| `cameraResolution` | `ResolutionPreset` | `high` | 请求的相机分辨率 |
| `cameraVerticalFovDegrees` | `double` | `63` | 透视相机垂直视场角 |
| `preferredFramesPerSecond` | `int` | `60` | 首选追踪与渲染帧率 |
| `anchorLostGracePeriod` | `Duration` | `350ms` | 人脸丢失后保留锚点的宽限期 |
| `faceTrackingEnabled` | `bool` | `true` | 是否运行人脸推理 |
| `enableFaceBlendshapes` | `bool` | `true` | 是否计算表情系数 |
| `faceAnchorOrigin` | `ArFaceAnchorOrigin` | `faceCenter` | 锚点坐标系原点，与 ARKit 一致 |
| `showCameraPreview` | `bool` | `true` | 是否显示相机画面 |
| `showsStatistics` | `bool` | `false` | 是否显示追踪与帧率徽标 |
| `loadingBuilder` | `ArViewLoadingBuilder?` | `null` | 自定义加载界面 |
| `errorBuilder` | `ArViewErrorBuilder?` | `null` | 自定义错误界面 |
| `onError` | `Function(Object, StackTrace)?` | `null` | 错误回调 |

`cameraVerticalFovDegrees` 必须位于 `(0, 180)` 之间，`preferredFramesPerSecond` 必须大于 0。

### 生命周期

1. 视图挂载并请求相机权限。
2. 初始化相机并启动 MediaPipe 人脸管线。
3. 检测到人脸后创建 `ArFaceAnchor`。
4. 调用 `ArViewDelegate.nodeForFaceAnchor` 获取锚点节点。
5. 将节点添加到场景并调用 `didAddNode`。
6. 每帧更新锚点并调用 `didUpdateNode`。
7. 人脸丢失超过宽限期后移除节点并调用 `didRemoveNode`。

应用进入后台时，视图会停止相机并移除当前锚点；恢复前台后自动重新启动。

## `ArViewDelegate`

节点生命周期委托。

```dart
abstract class ArViewDelegate {
  const ArViewDelegate();

  Node? nodeForFaceAnchor(ArView view, ArFaceAnchor anchor);

  void didAddNode(ArView view, ArFaceAnchor anchor);

  void didUpdateNode(ArView view, ArFaceAnchor anchor);

  void didRemoveNode(ArView view, ArFaceAnchor anchor);
}
```

- `nodeForFaceAnchor` 返回的节点会自动添加到 `scene`。返回 `null` 时保留空追踪节点。
- `didUpdateNode` 调用前，`anchor.node` 的变换已经更新。
- 委托回调抛出的异常会转换为 `ArViewException` 并通过错误回调报告。

## `ArFaceAnchor`

由 Flutter Scene `Node` 承载的已追踪人脸锚点。

| 成员 | 类型 | 说明 |
| --- | --- | --- |
| `identifier` | `int` | 人脸持续追踪期间稳定的标识符 |
| `origin` | `ArFaceAnchorOrigin` | 当前使用的锚点原点 |
| `node` | `Node` | 挂在锚点上的场景节点 |
| `transform` | `Matrix4` | 相机空间锚点变换 |
| `rotation` | `Quaternion` | 相机空间旋转 |
| `screenPosition` | `Offset` | 左上角为原点的归一化锚点屏幕位置 |
| `distanceMeters` | `double` | 估计的相机距离 |
| `faceWidthMeters` | `double` | 估计的实际脸宽 |
| `mesh` | `FaceMeshResult` | MediaPipe 人脸网格 |
| `headPose` | `FaceMeshHeadPose` | MediaPipe 头部姿态 |
| `landmarks` | `List<FaceMeshLandmark>` | 478 个人脸关键点 |
| `blendshapes` | `FaceBlendshapes?` | 当前帧表情系数，默认启用 |

`transform` 和 `rotation` 返回克隆值，调用方修改返回值不会改变内部追踪状态。

## `ArViewController`

为场景和屏幕空间查询提供命令式 API。

```dart
final controller = ArViewController(scene: scene);
```

### 节点管理

| 方法 | 说明 |
| --- | --- |
| `addNode` | 添加节点并应用可选局部变换 |
| `addModel` | 加载 `.glb` 资源并添加到相机前方 |
| `removeNode` | 从场景中移除节点 |
| `nodeNamed` | 按名称查找节点 |
| `setPosition` / `moveNode` | 设置或增量修改局部位置 |
| `setRotation` / `setScale` | 设置局部旋转与缩放 |
| `setTransform` | 替换局部变换 |
| `setWorldPosition` / `setWorldTransform` | 设置世界空间位置或变换 |
| `getWorldPosition` | 获取相机空间中的世界坐标 |

### 视图相关能力

状态查询在视图未挂载时返回安全值：

| 成员 | 说明 |
| --- | --- |
| `isTracking` | 当前是否检测到人脸；未挂载时为 `false` |
| `currentFaceAnchor` | 当前人脸锚点；未挂载或未检测到时为 `null` |

以下成员要求控制器已挂载到 `ArView`，否则抛出 `StateError`：

| 成员 | 说明 |
| --- | --- |
| `viewportSize` | 当前逻辑视口尺寸 |
| `camera` | 当前 Flutter Scene 透视相机 |
| `retry` | 重新启动相机和追踪 |
| `openSettings` | 打开系统应用设置 |
| `projectPoint` | 世界点投影为屏幕坐标 |
| `unprojectPoint` | 屏幕点转换为指定距离的相机空间点 |
| `hitTest` | 返回最近命中表面 |
| `hitTestAll` | 返回所有命中表面 |

## `ArFacePoseMapper`

将单个 `FaceMeshResult` 映射为 `ArFacePose`。

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

`map` 在以下情况返回 `null`：

- 视口宽或高不大于 0。
- 图像宽或高不大于 0。
- 关键点数量不足。
- 人脸投影宽度过小。

`ArFacePose` 包含 `transform`、`rotation`、`position`、`screenPosition`、`headPose`、
`distanceMeters` 和 `faceWidthMeters`。默认使用 `faceCenter`，与 ARKit 人脸锚点原点一致。

## `ArViewException`

相机或人脸追踪失败时报告的统一异常类型。

```dart
class ArViewException implements Exception {
  final ArViewErrorCode code;
  final String message;
  final Object? cause;
  final StackTrace? stackTrace;
  bool get canOpenSettings;
}
```

### 错误码

| 错误码 | 说明 |
| --- | --- |
| `cameraPermissionDenied` | 相机权限被拒绝 |
| `cameraPermissionPermanentlyDenied` | 相机权限被永久拒绝 |
| `cameraPermissionRestricted` | 相机访问受设备策略限制 |
| `cameraUnavailable` | 没有可用相机 |
| `cameraInitializationFailed` | 相机初始化或图像流失败 |
| `faceTrackingFailed` | MediaPipe 人脸追踪失败 |
| `modelLoadFailed` | glTF/GLB 模型加载失败 |
| `unsupportedPlatform` | 当前平台不支持 |

`canOpenSettings` 仅对权限相关错误返回 `true`。

## 弃用 API

为兼容旧代码，以下名称暂时保留：

| 弃用名称 | 替代名称 |
| --- | --- |
| `ARView` | `ArView` |
| `ARViewController` | `ArViewController` |
| `ArView(isFaceTrackingEnabled: ...)` | `ArView(faceTrackingEnabled: ...)` |
| `ArViewController.pointOfView` | `ArViewController.camera` |

新项目不应使用弃用名称。旧名称至少保留至下一个次版本。
