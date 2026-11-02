# flutter_ar_plus

[![pub package](https://img.shields.io/pub/v/flutter_ar_plus.svg)](https://pub.dev/packages/flutter_ar_plus)
[![Flutter CI](https://github.com/yuanzhihong1/flutter_ar_plus/actions/workflows/ci.yml/badge.svg)](https://github.com/yuanzhihong1/flutter_ar_plus/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-%E2%89%A53.47-02569B?logo=flutter)](https://flutter.dev)

`flutter_ar_plus` 是一个面向 Flutter 的实时人脸 AR 叠加库。它将相机预览、MediaPipe Face Mesh
与 Flutter Scene 组合起来，为三维模型、程序化网格和 Widget 提供持续更新的人脸锚点。

项目已发布 `1.0.0` 正式版，公开 API 已按 Dart 与 Flutter 的常见约定整理，并从 `1.0.0` 起进入
1.x 兼容周期。版本语义、兼容策略和破坏性变更记录见 [更新日志](CHANGELOG.md) 与
[迁移指南](doc/migration-guide.md)。

## 特性

- 使用 MediaPipe Face Mesh 进行单张人脸追踪。
- 提供稳定的 `ArFaceAnchor`，同步位置、旋转、脸宽、相机距离和屏幕坐标。
- 支持脸部中心与鼻尖两种锚点原点。
- 把 Flutter Scene `Node` 直接挂载到人脸，支持 glTF/GLB、网格和 `WidgetComponent`。
- 提供 `ArViewDelegate` 生命周期回调和 `ArViewController` 命令式场景控制。
- 提供投影、反投影、射线检测、模型加载和错误处理能力。
- 可选计算 MediaPipe 面部表情系数，用于驱动表情动画。
- 内置权限请求、应用生命周期恢复、加载与错误状态。
- 支持 Android、iOS 和 macOS。

## 平台支持

| 平台 | 相机预览 | 人脸追踪 | 最低建议版本 |
| --- | --- | --- | --- |
| Android | 支持 | 支持 | Android 7.0（API 24） |
| iOS | 支持 | 支持 | iOS 15.0 |
| macOS | 支持 | 支持 | macOS 12.0 |
| Linux / Windows / Web | 不支持 | 不支持 | 不作为稳定平台 |

相机、权限和原生推理更适合在真机验证。模拟器通常无法提供完整的实时相机与 GPU 环境。

## 环境要求

- Flutter 3.47.0 或更高版本。
- Dart 3.13.7 或更高版本。
- 支持目标平台的原生构建环境。
- Android 或 iOS 真机，或配置好相机权限的 macOS 设备。

## 安装

在应用的 `pubspec.yaml` 中添加依赖：

```yaml
dependencies:
  flutter_ar_plus: ^1.0.0
  camera: ^0.12.2
  flutter_scene: ^0.24.3
  mediapipe_face_mesh: ^3.2.2
  vector_math: ^2.4.4
```

然后运行：

```sh
flutter pub get
```

库的稳定公开 API 只从以下入口导出：

```dart
import 'package:flutter_ar_plus/flutter_ar_plus.dart';
```

请不要直接导入 `package:flutter_ar_plus/src/...`，这些文件不属于兼容性承诺范围。

## 快速开始

```dart
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ar_plus/flutter_ar_plus.dart';
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
      showTrackingIndicator: true,
    );
  }
}

class NoseEffectDelegate extends ArViewDelegate {
  const NoseEffectDelegate();

  @override
  Node? nodeForFaceAnchor(ArView view, ArFaceAnchor anchor) {
    return Node(name: 'nose-effect')
      // 默认锚点位于脸部中心，沿局部坐标系偏移到鼻尖附近。
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

`Scene` 由应用创建并释放。`ArView` 只负责创建和更新人脸锚点，不会释放外部传入的场景。

如果只需要直接附着在鼻尖上的内容，可以设置：

```dart
ArView(
  scene: scene,
  anchorOrigin: ArFaceAnchorOrigin.noseTip,
);
```

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

完整步骤见 [快速开始](doc/getting-started.md)。

## 核心概念

### 坐标空间

`ArView` 使用米制相机空间：

- 相机位于原点。
- `+X` 指向右方。
- `+Y` 指向上方。
- `+Z` 指向远离相机的方向。
- 位置和距离单位为米。

人脸内容使用 Flutter Scene 的局部 `+Z` 朝前约定。模型正面应沿局部 `+Z` 导出，这样头部偏航、
俯仰和翻滚会自然作用到内容上。

### 锚点生命周期

1. 相机和 MediaPipe 管线完成初始化。
2. 检测到人脸后创建 `ArFaceAnchor`。
3. `ArViewDelegate.nodeForFaceAnchor` 返回要挂载的场景节点。
4. 后续推理持续更新锚点变换和追踪数据。
5. 人脸丢失超过 `anchorLostGracePeriod` 后移除锚点和节点。
6. 应用进入后台时停止相机；恢复前台后自动重新启动。

### 所有权

| 对象 | 创建方 | 释放方 |
| --- | --- | --- |
| `Scene` | 应用 | 应用 |
| `ArViewController` | 应用 | 无需显式释放 |
| `ArFaceAnchor` | `ArView` | `ArView` |
| 相机控制器与 MediaPipe 管线 | `ArView` | `ArView` |

### 命令式控制

```dart
final controller = ArViewController(scene: scene);

controller.addNode(
  Node(name: 'marker')..addComponent(
    MeshComponent(Mesh(CuboidGeometry(Vector3.all(0.1)), material)),
  ),
  position: Vector3(0, 0, 1),
);

ArView(scene: scene, controller: controller);
```

节点和局部变换操作可以在视图挂载前使用。`camera`、`viewportSize`、`projectPoint`、
`unprojectPoint`、`hitTest` 和 `hitTestAll` 要求控制器已挂载，否则会抛出 `StateError`。

## 主要公开 API

| 类型 | 用途 |
| --- | --- |
| `ArView` | 相机预览、人脸追踪与 Flutter Scene 渲染入口 |
| `ArViewDelegate` | 创建人脸节点并接收锚点生命周期回调 |
| `ArFaceAnchor` | 当前人脸姿态、网格、关键点和表情数据 |
| `ArViewController` | 场景节点管理和屏幕空间查询 |
| `ArFacePoseMapper` | 将单个 `FaceMeshResult` 转换为米制相机空间姿态 |
| `ArFacePose` | 离线映射结果 |
| `ArViewException` | 统一的相机、追踪和模型错误类型 |
| `ArViewErrorCode` | 可供程序处理的错误分类 |

完整参数、默认值和异常约定见 [API 参考](doc/api-reference.md)。

## 性能建议

- 优先从 30 FPS 和 `ResolutionPreset.medium` 开始验证，再按设备能力提高。
- 不需要表情数据时关闭 `enableFaceBlendshapes`。
- 避免在每帧回调中创建节点、加载纹理或执行同步 I/O。
- 控制透明材质、后处理和网格复杂度。
- 在低端设备上降低 `preferredFramesPerSecond`，不要只依赖渲染帧率限制。

更多建议见 [性能指南](doc/performance.md)。

## 示例与静态图片验证

运行实时相机示例：

```sh
cd example
flutter pub get
flutter run -d macos
```

或查看可用设备后运行：

```sh
flutter devices
flutter run -d <设备 ID>
```

示例还包含无需相机的静态图片验证流程：

```sh
cd example
flutter run -d macos --dart-define=FACE_IMAGE_TEST=true
```

该模式会运行真实的 MediaPipe 模型和 Flutter Scene 姿态映射，便于排查坐标系、朝向和投影问题。

## 测试

```sh
./tool/test.sh
```

脚本会启用 Flutter GPU 与 Impeller，并运行库测试和示例测试。也可以单独执行：

```sh
dart format --output=none --set-exit-if-changed lib test example/lib example/test
flutter analyze
flutter test --enable-flutter-gpu --enable-impeller
```

## 文档

- [文档导航](doc/README.md)
- [快速开始](doc/getting-started.md)
- [API 参考](doc/api-reference.md)
- [架构说明](doc/architecture.md)
- [性能指南](doc/performance.md)
- [平台与能力限制](doc/limitations.md)
- [故障排查](doc/troubleshooting.md)
- [迁移指南](doc/migration-guide.md)
- [发布流程](doc/release-process.md)

## 版本与兼容性

项目遵循语义化版本。自 `1.0.0` 起，不兼容的公开 API 变更会提升主版本号，并在
`CHANGELOG.md` 和迁移指南中给出替代写法。

公开兼容范围包括：

- `package:flutter_ar_plus/flutter_ar_plus.dart` 导出的类型和成员。
- README 与 `doc/` 中明确描述的行为。
- 错误码、回调时序和资源所有权约定。

不包含：

- `lib/src/` 中的未导出实现。
- 原生插件内部实现和通道名称。
- 第三方依赖自身的 API。

## 贡献

欢迎提交缺陷报告、文档修正和实现贡献。开始前请阅读：

- [贡献指南](CONTRIBUTING.md)
- [支持说明](SUPPORT.md)
- [安全策略](SECURITY.md)
- [行为准则](CODE_OF_CONDUCT.md)

## 许可证

本项目使用 [MIT License](LICENSE)。
