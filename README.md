# flutter_ar

[![pub package](https://img.shields.io/pub/v/flutter_ar.svg)](https://pub.dev/packages/flutter_ar)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-%E2%89%A53.47-02569B?logo=flutter)](https://flutter.dev)

`flutter_ar` 是一个面向 Flutter 的实时人脸 AR 叠加库。它组合相机预览、MediaPipe Face Mesh
和 Flutter Scene，将三维内容稳定地附着到人脸锚点上。

## 特性

- 使用 MediaPipe Face Mesh 追踪 478 个人脸关键点。
- 提供一个持续更新的人脸锚点，并同步头部姿态、距离和实际脸宽。
- 默认使用与 ARKit 一致的脸部中心锚点，也可切换为鼻尖锚点。
- 支持 Android、iOS 和 macOS 的实时相机预览与人脸追踪。
- 提供 `ArViewDelegate` 生命周期回调、命令式场景控制器和屏幕空间查询。
- 可选用 52 个 ARKit 风格面部表情系数。
- 内置相机权限处理、应用生命周期恢复、加载与错误界面。
- 支持 glTF/GLB 模型、程序化网格、Widget 组件和其他 Flutter Scene 内容。

## 平台支持

| 平台 | 实时相机 | 人脸追踪 | 说明 |
| --- | --- | --- | --- |
| Android | 支持 | 支持 | 建议 Android 7.0（API 24）及以上 |
| iOS | 支持 | 支持 | 建议 iOS 15 及以上 |
| macOS | 支持 | 支持 | 建议 macOS 12 及以上 |
| Linux / Windows / Web | 暂不支持 | 暂不支持 | 不作为稳定平台承诺 |

人脸追踪依赖 `mediapipe_face_mesh` 的原生 FFI 能力。使用前请确认目标平台已由依赖包提供支持。

## 环境要求

- Flutter 3.47.0 或更高版本。
- Dart 3.13.7 或更高版本。
- 启用人脸追踪的设备或模拟器。相机通常需要真机验证。

## 安装

在应用的 `pubspec.yaml` 中添加依赖：

```yaml
dependencies:
  flutter_ar: ^0.1.0
  camera: ^0.12.2
  flutter_scene: ^0.24.3
  vector_math: ^2.4.4
```

然后运行：

```sh
flutter pub get
```

## 快速开始

```dart
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ar/flutter_ar.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

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
      delegate: const NoseEffectDelegate(),
      cameraLensDirection: CameraLensDirection.front,
      showsStatistics: true,
    );
  }
}

class NoseEffectDelegate extends ArViewDelegate {
  const NoseEffectDelegate();

  @override
  Node? nodeForFaceAnchor(ArView view, ArFaceAnchor anchor) {
    return Node(name: 'nose-effect')
      // 默认锚点位于 ARKit 脸部中心，先偏移到鼻尖。
      ..position = Vector3(
        0,
        -anchor.faceWidthMeters * 0.16,
        anchor.faceWidthMeters * 0.5,
      )
      ..addComponent(
        WidgetComponent(
          child: const Text(
            '🐷',
            textDirection: TextDirection.ltr,
            style: TextStyle(fontSize: 118),
          ),
          size: const Size(180, 180),
          worldHeight: 0.08,
          input: WidgetInput.manual,
        ),
      );
  }
}
```

`Scene` 由应用持有并负责释放。`ArView` 只创建和更新人脸锚点，不会释放外部传入的场景。
默认帧率为 60，相机分辨率为 `high`，并启用 ARKit 风格表情系数。

## 平台配置

### Android

在 `android/app/src/main/AndroidManifest.xml` 中声明相机权限：

```xml
<uses-permission android:name="android.permission.CAMERA" />
```

`flutter_scene` 需要启用 Flutter GPU：

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

在 Debug 与 Release entitlement 文件中添加相机权限：

```xml
<key>com.apple.security.device.camera</key>
<true/>
```

## 坐标约定

`ArView` 使用 AR 相机空间：

- 相机位于原点。
- `+X` 指向右方。
- `+Y` 指向上方。
- `+Z` 指向远离相机的方向。
- 位置单位为米。

人脸内容遵循 Flutter Scene 的局部坐标约定：内容正面朝向局部 `+Z`。模型制作时应让正面沿 `+Z`
导出，这样头部偏航、俯仰和翻滚会自然地作用到内容上。

## 核心 API

### `ArView`

相机预览、追踪管线与场景渲染的入口组件。主要参数包括：

- `scene`：应用持有的 Flutter Scene 场景。
- `controller`：可选的命令式控制器。
- `delegate`：节点生命周期委托。
- `faceTrackingEnabled`：是否启用人脸推理。
- `enableFaceBlendshapes`：是否计算 52 个面部表情系数。
- `faceAnchorOrigin`：锚点使用脸部中心（默认）或鼻尖。
- `cameraVerticalFovDegrees`：透视相机垂直视场角。
- `loadingBuilder`、`errorBuilder`、`onError`：自定义状态与错误处理。

### `ArViewController`

提供节点管理、变换设置、投影、反投影和射线检测能力。需要屏幕空间查询时，应先让 `ArView`
完成挂载。

```dart
final controller = ArViewController(scene: scene);
final faceAnchor = controller.currentFaceAnchor;
final screenPoint = controller.projectPoint(Vector3(0, 0, 1));
```

### `ArFaceAnchor`

每次追踪更新后提供：

- `node`：附着在锚点上的 Flutter Scene 节点。
- `transform`、`rotation`、`position`：相机空间姿态。
- `screenPosition`：归一化锚点屏幕位置。
- `distanceMeters`、`faceWidthMeters`：米制距离与脸宽。
- `mesh`、`landmarks`、`headPose`：MediaPipe 原始追踪数据。
- `blendshapes`：启用表情系数后可用。

### `ArFacePoseMapper`

无需启动相机，即可将单个 `FaceMeshResult` 映射到相同的米制相机空间。适合静态图片验证、
离线处理或自定义渲染管线。

完整说明见 [API 参考](doc/api-reference.md)。

## 静态图片验证

示例应用包含真实 MediaPipe 检测器、网格模型、几何求解和 Flutter Scene 姿态映射的静态图片
验证流程，不需要相机：

```sh
cd example
flutter run -d macos --dart-define=FACE_IMAGE_TEST=true
```

验证界面会同时绘制人脸网格、脸部中心锚点投影和三维猪头，便于检查坐标系和朝向回归。

## 运行示例

```sh
cd example
flutter pub get
flutter run -d macos
```

或选择可用的 Android/iOS 设备：

```sh
flutter devices
flutter run -d <设备 ID>
```

## 测试

```sh
./tool/test.sh
```

脚本会启用 Flutter GPU 与 Impeller，并依次运行库测试和示例测试。也可以单独运行：

```sh
dart format --output=none --set-exit-if-changed lib test example/lib example/test
flutter analyze
flutter test --enable-flutter-gpu --enable-impeller
```

## 项目结构

```text
flutter_ar/
├── lib/
│   ├── flutter_ar.dart          # 唯一公开入口
│   └── src/                     # 公开类型与内部实现
├── doc/                         # 中文指南与 API 文档
├── example/                     # 可运行示例
├── test/                        # 单元与组件测试
├── tool/                        # 开发脚本
└── .github/                     # CI、Issue 与 PR 模板
```

## API 迁移

`0.1.0` 起使用 Dart 风格命名：

| 旧名称 | 新名称 | 状态 |
| --- | --- | --- |
| `ARView` | `ArView` | 旧名称已弃用，临时保留兼容别名 |
| `ARViewController` | `ArViewController` | 旧名称已弃用，临时保留兼容别名 |
| `isFaceTrackingEnabled` | `faceTrackingEnabled` | 旧参数已弃用，临时保留兼容 |
| `ArViewController.pointOfView` | `ArViewController.camera` | 旧 getter 已弃用 |

默认行为同步对齐 ARKit：

| 0.0.1 默认值 | 0.1.0 默认值 |
| --- | --- |
| `ArFaceAnchorOrigin.noseTip` | `ArFaceAnchorOrigin.faceCenter` |
| 30 FPS | 60 FPS |
| `ResolutionPreset.medium` | `ResolutionPreset.high` |
| 关闭 `enableFaceBlendshapes` | 开启 `enableFaceBlendshapes` |

新代码应始终导入 `package:flutter_ar/flutter_ar.dart`，不要依赖 `lib/src` 中的实现文件。

## 贡献与支持

- 开发流程见 [CONTRIBUTING.md](CONTRIBUTING.md)。
- 使用问题见 [SUPPORT.md](SUPPORT.md)。
- 安全问题见 [SECURITY.md](SECURITY.md)。
- 行为准则见 [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)。

## 许可证

本项目使用 [MIT License](LICENSE)。
