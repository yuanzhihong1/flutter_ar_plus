# 快速开始

本文介绍如何从零接入 `flutter_ar`。

## 1. 检查环境

```sh
flutter --version
flutter devices
```

要求：

- Flutter 3.47.0 或更高版本。
- Dart 3.13.7 或更高版本。
- Android、iOS 或 macOS 目标设备。
- 真机更适合验证相机、权限和人脸追踪。

## 2. 添加依赖

在 `pubspec.yaml` 中配置：

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_ar: ^0.1.0
  camera: ^0.12.2
  flutter_scene: ^0.24.3
  vector_math: ^2.4.4
```

执行：

```sh
flutter pub get
```

`flutter_ar` 的公开入口只有一个：

```dart
import 'package:flutter_ar/flutter_ar.dart';
```

不要直接导入 `package:flutter_ar/src/...`，这些文件不属于稳定 API。

## 3. 配置相机权限

### Android

在 `android/app/src/main/AndroidManifest.xml` 中添加：

```xml
<uses-permission android:name="android.permission.CAMERA" />
```

同时启用 Flutter GPU：

```xml
<application>
  <meta-data
      android:name="io.flutter.embedding.android.EnableFlutterGPU"
      android:value="true" />
</application>
```

### iOS

在 `ios/Runner/Info.plist` 中添加：

```xml
<key>NSCameraUsageDescription</key>
<string>本应用需要使用相机进行人脸 AR 效果展示。</string>
<key>FLTEnableFlutterGPU</key>
<true/>
```

### macOS

在 `macos/Runner/Info.plist` 中添加：

```xml
<key>NSCameraUsageDescription</key>
<string>本应用需要使用相机进行人脸 AR 效果展示。</string>
<key>FLTEnableFlutterGPU</key>
<true/>
```

在 Debug 与 Release entitlement 文件中添加：

```xml
<key>com.apple.security.device.camera</key>
<true/>
```

## 4. 创建场景与页面

```dart
import 'package:flutter/material.dart';
import 'package:flutter_ar/flutter_ar.dart';
import 'package:flutter_scene/scene.dart';

class FaceArPage extends StatefulWidget {
  const FaceArPage({super.key});

  @override
  State<FaceArPage> createState() => _FaceArPageState();
}

class _FaceArPageState extends State<FaceArPage> {
  final Scene scene = Scene();

  @override
  void dispose() {
    scene.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ArView(
      scene: scene,
      delegate: const FaceAnchorNodeDelegate(),
    );
  }
}
```

## 5. 添加人脸内容

```dart
class FaceAnchorNodeDelegate extends ArViewDelegate {
  const FaceAnchorNodeDelegate();

  @override
  Node? nodeForFaceAnchor(ArView view, ArFaceAnchor anchor) {
    return Node(name: 'face-content')
      ..addComponent(
        WidgetComponent(
          child: const Icon(Icons.star, size: 96),
          size: const Size(140, 140),
          worldHeight: 0.08,
          input: WidgetInput.manual,
        ),
      );
  }
}
```

当人脸首次被检测到时，`ArView` 会调用 `nodeForFaceAnchor`，把返回节点添加到场景，并在后续帧
更新节点变换。人脸持续丢失超过 `anchorLostGracePeriod` 后，锚点及其节点会被移除。

## 6. 默认参数与 ARKit

`ArView` 的默认值按 ARKit 人脸追踪的常见行为设置：

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `faceAnchorOrigin` | `faceCenter` | 与 ARKit 脸部中心锚点一致 |
| `preferredFramesPerSecond` | `60` | 与 ARSCNView 默认帧率一致 |
| `cameraResolution` | `ResolutionPreset.high` | 使用较高相机图像质量 |
| `enableFaceBlendshapes` | `true` | 提供 ARKit 风格表情系数 |
| `cameraLensDirection` | `front` | 人脸追踪默认使用前置相机 |
| `showCameraPreview` | `true` | 显示相机背景 |
| `showsStatistics` | `false` | 默认不显示调试统计 |

如果需要在脸部中心以外的位置放置内容，应使用相对脸部中心的偏移，或显式切换为鼻尖锚点：

```dart
ArView(
  scene: scene,
  faceAnchorOrigin: ArFaceAnchorOrigin.noseTip,
);
```

## 7. 使用控制器

```dart
final Scene scene = Scene();
final ArViewController controller = ArViewController(scene: scene);

// 场景挂载前也可以添加节点。
controller.addNode(
  Node(name: 'debug-marker'),
  position: Vector3(0, 0, 1),
);

ArView(
  scene: scene,
  controller: controller,
);
```

`currentFaceAnchor` 与 `isTracking` 在视图未挂载时会返回安全的空状态值。`camera`、
`viewportSize`、`projectPoint`、`unprojectPoint` 和 `hitTest` 等能力要求 `ArView` 已挂载。

静态检查代码前可以判断：

```dart
if (controller.isAttached) {
  final anchor = controller.currentFaceAnchor;
}
```

## 8. 自定义加载与错误界面

```dart
ArView(
  scene: scene,
  loadingBuilder: (context, progress) {
    return const Center(child: CircularProgressIndicator());
  },
  errorBuilder: (context, error, retry, openSettings) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(error.message),
          TextButton(onPressed: retry, child: const Text('重试')),
          if (error.canOpenSettings)
            TextButton(
              onPressed: openSettings,
              child: const Text('打开设置'),
            ),
        ],
      ),
    );
  },
  onError: (error, stackTrace) {
    debugPrint('AR 错误：$error');
  },
);
```

## 9. 控制表情系数

表情系数默认启用，以保持与 ARKit 人脸锚点一致。可通过 `anchor.blendshapes` 获取当前帧的
52 个 ARKit 风格系数。不需要表情时建议显式关闭，以减少每帧推理开销：

```dart
ArView(
  scene: scene,
  enableFaceBlendshapes: false,
);
```

## 10. 验证集成

启动示例：

```sh
cd example
flutter run -d macos
```

静态图片验证：

```sh
flutter run -d macos --dart-define=FACE_IMAGE_TEST=true
```

运行完整测试：

```sh
./tool/test.sh
```
