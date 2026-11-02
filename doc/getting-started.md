# 快速开始

本文介绍如何从空 Flutter 应用接入 `flutter_ar_plus`。示例只使用公开 API。

## 1. 检查环境

```sh
flutter --version
flutter devices
```

要求：

- Flutter 3.47.0 或更高版本。
- Dart 3.13.7 或更高版本。
- Android、iOS 或 macOS 目标设备。
- 建议使用真机验证相机、权限、GPU 和实时推理。

## 2. 添加依赖

在应用的 `pubspec.yaml` 中配置：

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_ar_plus: ^1.0.0
  camera: ^0.12.2
  flutter_scene: ^0.24.3
  mediapipe_face_mesh: ^3.2.2
  vector_math: ^2.4.4
```

执行：

```sh
flutter pub get
```

统一使用公开入口：

```dart
import 'package:flutter_ar_plus/flutter_ar_plus.dart';
```

不要导入 `package:flutter_ar_plus/src/...`。内部文件不属于稳定 API，可能在修订版本中调整。

## 3. 配置平台

### Android

在 `android/app/src/main/AndroidManifest.xml` 中声明相机权限：

```xml
<uses-permission android:name="android.permission.CAMERA" />
```

在同一个文件的 `<application>` 节点中启用 Flutter GPU：

```xml
<meta-data
    android:name="io.flutter.embedding.android.EnableFlutterGPU"
    android:value="true" />
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
import 'package:flutter_ar_plus/flutter_ar_plus.dart';
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
    // ArView 不拥有 Scene，应用必须自行释放。
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

`ArView` 会自动请求相机权限、初始化相机、启动 MediaPipe 管线，并显示相机与场景。

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

首次检测到人脸时，`ArView` 会调用 `nodeForFaceAnchor`，将返回的节点添加到场景，并在后续帧更新
锚点变换。人脸持续丢失超过 `anchorLostGracePeriod` 后，锚点及其节点会被移除。

如果需要在运行时修改内容，可以保存节点引用并实现生命周期回调：

```dart
class AnimatedFaceDelegate extends ArViewDelegate {
  Node? content;

  @override
  Node? nodeForFaceAnchor(ArView view, ArFaceAnchor anchor) {
    content = Node(name: 'animated-content');
    return content;
  }

  @override
  void didUpdateNode(ArView view, ArFaceAnchor anchor) {
    content?.rotation = anchor.rotation;
  }

  @override
  void didRemoveNode(ArView view, ArFaceAnchor anchor) {
    content = null;
  }
}
```

不要在每帧回调中执行同步 I/O、纹理上传或复杂对象分配。

## 6. 选择锚点原点

默认锚点是脸部中心：

```dart
ArView(
  scene: scene,
  delegate: const FaceAnchorNodeDelegate(),
  anchorOrigin: ArFaceAnchorOrigin.faceCenter,
);
```

需要把内容直接放在鼻尖时，可切换为鼻尖原点：

```dart
ArView(
  scene: scene,
  delegate: const NoseDecorationDelegate(),
  anchorOrigin: ArFaceAnchorOrigin.noseTip,
);
```

两种原点都使用相同的头部旋转。内容尺寸可参考 `anchor.faceWidthMeters`：

```dart
@override
Node? nodeForFaceAnchor(ArView view, ArFaceAnchor anchor) {
  final node = createDecoration();
  node.scale = Vector3.all(anchor.faceWidthMeters / 0.14);
  return node;
}
```

脸宽和距离均为估算值。极端角度、遮挡和远距离场景下出现波动属于预期行为。

## 7. 使用控制器

```dart
final Scene scene = Scene();
final ArViewController controller = ArViewController(scene: scene);

controller.addNode(
  Node(name: 'debug-marker'),
  position: Vector3(0, 0, 1),
);

ArView(
  scene: scene,
  controller: controller,
);
```

控制器在视图挂载前可以执行节点与局部变换操作。屏幕空间查询要求视图已挂载：

```dart
if (controller.isAttached) {
  final anchor = controller.currentFaceAnchor;
  if (anchor != null) {
    final screenPoint = controller.projectPoint(anchor.position);
    debugPrint('人脸屏幕坐标：$screenPoint');
  }
}
```

`camera`、`viewportSize`、`projectPoint`、`unprojectPoint`、`hitTest` 和 `hitTestAll` 在控制器
未挂载时会抛出 `StateError`。

## 8. 控制表情系数

表情系数默认启用，可通过 `anchor.blendshapes` 读取 MediaPipe 的当前表情数据：

```dart
import 'package:mediapipe_face_mesh/mediapipe_face_mesh.dart'
    show FaceBlendshape;

@override
void didUpdateNode(ArView view, ArFaceAnchor anchor) {
  final jawOpen =
      anchor.blendshapes?[FaceBlendshape.jawOpen] ?? 0.0;
  // 使用系数驱动动画或渲染状态。
}
```

不需要表情数据时显式关闭，以减少每帧推理开销：

```dart
ArView(
  scene: scene,
  enableFaceBlendshapes: false,
);
```

具体关键名、系数数量和取值范围由当前 `mediapipe_face_mesh` 版本提供。

## 9. 自定义加载与错误界面

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
    debugPrint('flutter_ar_plus 错误：$error');
  },
);
```

- `errorBuilder` 负责权限、相机和追踪错误的主界面。
- `onError` 接收运行错误，包括相机、追踪和委托回调产生的错误。
- 如果 `onError` 自身抛错，库会通过 `FlutterError.reportError` 报告，避免递归回调。
- 按 `ArViewErrorCode` 分支处理业务逻辑，不要依赖 `message` 的完整文本。

## 10. 验证集成

先运行静态图片模式，排除相机与权限问题：

```sh
cd example
flutter run -d macos --dart-define=FACE_IMAGE_TEST=true
```

再运行实时相机模式：

```sh
flutter run -d macos
```

完整测试：

```sh
./tool/test.sh
```

如果画面或追踪异常，请继续阅读 [故障排查](troubleshooting.md) 与
[平台与能力限制](limitations.md)。
