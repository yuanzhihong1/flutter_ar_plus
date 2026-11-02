# 迁移指南

本页记录破坏性公开 API 变更和推荐迁移方式。

## 包名与导入路径

项目已统一更名为 `flutter_ar_plus`。升级后需要同步修改依赖名和导入路径：

```yaml
dependencies:
  flutter_ar_plus: ^1.0.0
```

```dart
import 'package:flutter_ar_plus/flutter_ar_plus.dart';
```

原生插件类、CocoaPods 名称和方法通道也使用 `flutter_ar_plus` 标识。更新依赖后请重新执行：

```sh
flutter clean
flutter pub get
```

iOS 与 macOS 应用还应重新执行 Pod 安装，确保旧插件缓存不会继续参与构建。

## 0.2.x → 1.0.0

`1.0.0` 是首个正式稳定版本，没有移除或重命名 `0.2.x` 的公开 API。升级时只需更新依赖约束：

```yaml
dependencies:
  flutter_ar_plus: ^1.0.0
```

然后重新执行 `flutter pub get`。仍在使用 `0.1.x` 的项目应先完成下一节的 API 迁移。

## 0.1.x → 0.2.0

`0.2.0` 以 Flutter 生态常用的命名和语义为准，移除了早期兼容别名，并清理了含义不准确的参数。
旧名称不再提供兼容层，升级后需要修改调用代码。

### 类型名称

| 0.1.x | 0.2.0 |
| --- | --- |
| `ARView` | `ArView` |
| `ARViewController` | `ArViewController` |

迁移示例：

```dart
// 旧写法
final view = ARView(scene: scene);
final controller = ARViewController(scene: scene);

// 新写法
final view = ArView(scene: scene);
final controller = ArViewController(scene: scene);
```

### 构造参数

| 0.1.x | 0.2.0 |
| --- | --- |
| `isFaceTrackingEnabled:` | `faceTrackingEnabled:` |
| `faceAnchorOrigin:` | `anchorOrigin:` |
| `showsStatistics:` | `showTrackingIndicator:` |

迁移示例：

```dart
// 旧写法
ArView(
  scene: scene,
  isFaceTrackingEnabled: true,
  faceAnchorOrigin: ArFaceAnchorOrigin.noseTip,
  showsStatistics: true,
);

// 新写法
ArView(
  scene: scene,
  faceTrackingEnabled: true,
  anchorOrigin: ArFaceAnchorOrigin.noseTip,
  showTrackingIndicator: true,
);
```

`showTrackingIndicator` 只控制追踪状态提示，不会显示帧率或其他统计信息。如果应用需要性能
数据，请接入 Flutter DevTools 或自行采样。

### 控制器属性

| 0.1.x | 0.2.0 |
| --- | --- |
| `controller.pointOfView` | `controller.camera` |

```dart
// 旧写法
final camera = controller.pointOfView;

// 新写法
final camera = controller.camera;
```

### 新增锚点位置

`ArFaceAnchor.position` 返回当前锚点在 AR 相机空间中的位置副本：

```dart
final Vector3 position = anchor.position;
```

### 行为变化

- 运行时修改 `ArView.anchorOrigin` 会移除当前锚点，并在下一帧按新原点重新创建。
- `ArFaceAnchor.origin` 始终与创建该锚点时使用的 `ArView.anchorOrigin` 一致。
- `ArView` 不再声明任何旧类型别名。
- 表情系数的文档不再承诺固定类别集合，具体定义以 `mediapipe_face_mesh` 的
  `FaceBlendshape` 为准。
- 示例应用改用 Flutter SDK 自带的 Cupertino 组件，移除了额外的 UI 依赖。

### 推荐升级步骤

1. 将 `pubspec.yaml` 中的版本约束更新到 `^0.2.0`。
2. 全局搜索并替换上表中的旧名称。
3. 将只使用追踪提示的 `showsStatistics` 改为 `showTrackingIndicator`。
4. 运行 `flutter analyze`，确认没有残留弃用 API。
5. 在目标真机回归相机、权限、场景内容和屏幕空间查询。
6. 运行 `./tool/test.sh`。

### 为什么不再保留别名

保留多套名称会让公开 API 长期含糊，增加文档、测试和 IDE 补全成本。相关清理已在 `0.x` 阶段完成。
自 `1.0.0` 起，不兼容的公开 API 变更会通过主版本号和本迁移指南说明。
