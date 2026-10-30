# 故障排查

## 相机黑屏或无法启动

检查以下配置：

1. Android 是否声明 `android.permission.CAMERA`。
2. iOS 是否包含 `NSCameraUsageDescription`。
3. macOS 是否同时配置 `NSCameraUsageDescription` 和
   `com.apple.security.device.camera` entitlement。
4. 应用是否处于前台。
5. 设备是否被其他应用占用相机。

`ArView` 会将权限问题映射为 `cameraPermissionDenied`、
`cameraPermissionPermanentlyDenied` 或 `cameraPermissionRestricted`。自定义
`errorBuilder` 时，可使用 `error.canOpenSettings` 决定是否显示设置入口。

## 场景显示异常或测试被跳过

`flutter_scene` 需要 Flutter GPU。请确认宿主应用包含：

Android：

```xml
<meta-data
    android:name="io.flutter.embedding.android.EnableFlutterGPU"
    android:value="true" />
```

iOS/macOS：

```xml
<key>FLTEnableFlutterGPU</key>
<true/>
```

运行测试时使用：

```sh
./tool/test.sh
```

该脚本会启用 Flutter GPU 与 Impeller。普通 `flutter test` 下，依赖渲染器的测试可能被跳过。

## 检测不到人脸

依次检查：

- 画面中是否有完整、清晰且光照充足的人脸。
- 是否使用前置相机或正确设置了 `cameraLensDirection`。
- `faceTrackingEnabled` 是否为 `true`。
- 是否在应用启动后等待 MediaPipe 模型初始化完成。
- 是否处于支持平台和真实设备架构。

可以打开 `showsStatistics: true` 查看追踪状态与帧率，也可以运行静态图片验证流程排除相机问题。

## 人脸内容朝向错误

内容应沿 Flutter Scene 的局部 `+Z` 正面制作。若移植 ARKit 模型，可能还需要调整模型原始轴向。
默认锚点与 ARKit 一致，位于脸部中心。需要直接定位鼻部挂件时，可切换到鼻尖锚点：

```dart
ArView(
  scene: scene,
  faceAnchorOrigin: ArFaceAnchorOrigin.noseTip,
);
```

## 人脸内容大小不合适

`ArFaceAnchor.faceWidthMeters` 提供估计脸宽。可以根据该值缩放内容，而不是写死尺寸：

```dart
Node? nodeForFaceAnchor(ArView view, ArFaceAnchor anchor) {
  final node = createMyModel();
  node.scale = Vector3.all(anchor.faceWidthMeters / 0.14);
  return node;
}
```

实际脸宽和距离均来自估算，极端角度或遮挡下可能出现波动。

## 帧率低或设备发热

可采取以下措施：

- 将 `preferredFramesPerSecond` 从默认的 60 降到 30、20 或 15。
- 将 `cameraResolution` 从默认的 `high` 降到 `medium` 或 `low`。
- 不需要表情时关闭默认启用的 `enableFaceBlendshapes`。
- 减少场景中的网格、透明材质和后处理。
- 避免在 `didUpdateNode` 或 `onFaceAnchorUpdated` 中执行昂贵同步操作。

## 控制器抛出 `StateError`

`ArViewController` 的屏幕空间能力需要先挂载到 `ArView`。使用前判断：

```dart
if (!controller.isAttached) {
  return;
}
final anchor = controller.currentFaceAnchor;
```

`viewportSize`、`camera`、`projectPoint`、`unprojectPoint`、`hitTest` 和 `hitTestAll`
都依赖已挂载视图。

## Android 前置相机人脸位置左右颠倒

库会根据相机方向和前置相机镜像规则处理 MediaPipe 输入。如果自定义了相机预览或额外镜像
图像，请确认没有重复镜像。预览和送入 MediaPipe 的图像必须使用相同的水平镜像语义。

## macOS 相机权限恢复后仍不可用

macOS 相机权限通常需要重启应用或重新创建相机视图。可以调用控制器重试：

```dart
await controller.retry();
```

若系统权限状态已经变化，也可先调用 `controller.openSettings()` 引导用户前往系统设置。

## 收集问题报告

提交 Issue 时请附上：

- Flutter、Dart 和目标系统版本。
- 设备型号与是否为真机。
- 复现步骤和最小示例。
- 完整错误信息与堆栈。
- 是否启用了 Flutter GPU、Impeller 或表情系数。
- 必要时提供脱敏后的截图或录屏。

请勿在公开 Issue 中上传包含个人隐私或安全敏感信息的相机画面。
