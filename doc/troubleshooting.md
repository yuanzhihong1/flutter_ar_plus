# 故障排查

## 相机黑屏或无法启动

依次检查：

1. Android 是否声明 `android.permission.CAMERA`。
2. iOS 是否配置 `NSCameraUsageDescription`。
3. macOS 是否同时配置 `NSCameraUsageDescription` 和
   `com.apple.security.device.camera` entitlement。
4. 应用是否处于前台。
5. 设备是否被其他应用占用相机。
6. 是否在模拟器或没有相机的设备上运行。

`ArView` 会将权限问题映射为 `cameraPermissionDenied`、
`cameraPermissionPermanentlyDenied` 或 `cameraPermissionRestricted`。自定义
`errorBuilder` 时，可使用 `error.canOpenSettings` 决定是否显示设置入口。

## 场景不显示或测试被跳过

`flutter_scene` 需要 Flutter GPU。确认宿主应用包含：

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

检查：

- 画面中是否有完整、清晰且光照充足的人脸。
- 是否使用前置相机或正确设置了 `cameraLensDirection`。
- `faceTrackingEnabled` 是否为 `true`。
- 是否等待 MediaPipe 模型初始化完成。
- 是否运行在受支持平台和真实设备架构。
- 是否有大范围遮挡、快速运动或极端角度。

可以设置 `showTrackingIndicator: true` 显示处理提示。它不会输出帧率或人脸数量；需要性能数据
时请使用 Flutter DevTools。静态图片验证流程可排除相机与权限问题：

```sh
cd example
flutter run -d macos --dart-define=FACE_IMAGE_TEST=true
```

## 人脸内容朝向错误

内容应沿 Flutter Scene 的局部 `+Z` 正面制作。检查模型导入设置和根节点旋转，确保正面没有沿
错误轴导出。

默认锚点位于脸部中心。需要直接定位鼻部挂件时，可切换到鼻尖锚点：

```dart
ArView(
  scene: scene,
  anchorOrigin: ArFaceAnchorOrigin.noseTip,
);
```

如果内容随头部运动方向相反，请先确认没有在节点上再次应用相机或设备旋转。

## 人脸内容大小不合适

`ArFaceAnchor.faceWidthMeters` 提供估计脸宽。可以根据该值缩放内容，而不是写死尺寸：

```dart
@override
Node? nodeForFaceAnchor(ArView view, ArFaceAnchor anchor) {
  final node = createMyModel();
  node.scale = Vector3.all(anchor.faceWidthMeters / 0.14);
  return node;
}
```

脸宽和距离均为估算值，极端角度或遮挡下可能波动。

## 帧率低或设备发热

优先尝试：

- 将 `preferredFramesPerSecond` 从 60 降到 30 或 20。
- 将 `cameraResolution` 从 `high` 降到 `medium` 或 `low`。
- 不需要表情时关闭 `enableFaceBlendshapes`。
- 减少场景中的网格、透明材质、Widget 捕获和后处理。
- 避免在 `didUpdateNode` 或 `onFaceAnchorUpdated` 中执行昂贵同步操作。

详见 [性能指南](performance.md)。

## 控制器抛出 `StateError`

`ArViewController` 的屏幕空间能力需要先挂载到 `ArView`。使用前判断：

```dart
if (!controller.isAttached) {
  return;
}
final anchor = controller.currentFaceAnchor;
```

`viewportSize`、`camera`、`projectPoint`、`unprojectPoint`、`hitTest` 和 `hitTestAll` 都依赖
已挂载视图。

如果错误信息提示场景不一致，请确认 `ArViewController.scene` 与 `ArView.scene` 是同一个对象。

## 前置相机人脸位置左右颠倒

库会根据相机方向和前置相机镜像规则处理 MediaPipe 输入。如果自定义相机预览或额外处理图像，
请确认没有重复镜像。预览和送入 MediaPipe 的图像必须使用相同的水平镜像语义。

## 相机权限恢复后仍不可用

某些平台在权限变化后需要重新创建相机会话。可以调用控制器重试：

```dart
await controller.retry();
```

如果系统权限状态已经变化，也可先调用：

```dart
await controller.openSettings();
```

## 模型加载失败

`ArViewController.addModel` 只加载 Flutter 资源中的 `.glb` 文件。检查：

- 文件是否已声明在 `pubspec.yaml` 的 `assets` 中。
- 路径与大小写是否完全一致。
- 模型是否包含不支持的扩展或纹理格式。
- 压缩纹理是否与目标平台兼容。

失败会抛出带 `ArViewErrorCode.modelLoadFailed` 的 `ArViewException`。

## 收集问题报告

提交 Issue 时请附上：

- Flutter、Dart 和目标平台版本。
- 设备型号与是否为真机。
- 复现步骤和最小示例。
- 完整错误信息与堆栈。
- 是否启用了 Flutter GPU、Impeller 或表情系数。
- 必要的脱敏截图或录屏。

请勿在公开 Issue 中上传包含个人隐私或安全敏感信息的相机画面。
