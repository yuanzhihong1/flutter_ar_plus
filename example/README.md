# flutter_ar 示例

该示例展示如何在 Flutter 应用中使用 `flutter_ar`：

- 实时相机预览与 MediaPipe 人脸追踪。
- 从脸部中心锚点偏移，将程序化三维猪头附着到鼻尖。
- 通过 `ArViewController` 添加、移动和删除场景节点。
- 使用静态图片验证人脸姿态映射。

## 运行环境

- Flutter 3.47.0 或更高版本。
- Android、iOS 或 macOS 设备。
- 相机权限已配置，且宿主应用已启用 Flutter GPU。

各平台配置方法见仓库根目录的 [README](../README.md) 和
[快速开始](../doc/getting-started.md)。

## 实时相机示例

```sh
flutter pub get
flutter run -d macos
```

也可以先通过 `flutter devices` 查看设备 ID，再将 `macos` 替换为目标设备。

示例中的三维猪头用于观察以下行为：

- 人脸节点是否跟随头部旋转。
- 脸部中心锚点与鼻尖偏移是否符合预期。
- 前后景深度和材质光照是否正常。
- 控制器添加、移动、删除节点是否即时生效。

## 静态图片验证

静态图片模式不需要相机，会直接运行真实的 MediaPipe 模型和 Flutter Scene 姿态映射：

```sh
flutter run -d macos --dart-define=FACE_IMAGE_TEST=true
```

控制台会输出图片尺寸、关键点数量、头部姿态、脸宽、媒体管线姿态平移和最终相机空间锚点位置。
该模式适合排查坐标系、朝向和投影问题。

## 测试

```sh
flutter test --enable-flutter-gpu --enable-impeller
```

或在仓库根目录运行：

```sh
./tool/test.sh
```

## 代码入口

- `lib/main.dart`：实时相机示例与控制器操作。
- `lib/nose_pig_node.dart`：程序化三维人脸装饰。
- `lib/face_image_test_page.dart`：静态图片推理与投影验证。
- `test/widget_test.dart`：示例节点结构与偏移测试。
