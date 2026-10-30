# flutter_ar 示例

该示例展示如何在 Flutter 应用中使用 `flutter_ar`：

- 实时相机预览。
- MediaPipe 人脸追踪。
- 从 ARKit 脸部中心锚点偏移，将程序化三维猪头附着在鼻尖。
- 通过 `ArViewController` 添加、移动和删除场景节点。
- 使用静态图片验证人脸姿态映射。

## 运行环境

- Flutter 3.47.0 或更高版本。
- Android、iOS 或 macOS 设备。
- 相机权限已配置，且宿主应用已启用 Flutter GPU。

各平台配置方法见仓库根目录的 [README](../README.md) 和
[安装指南](../doc/getting-started.md)。

## 实时相机示例

```sh
flutter pub get
flutter run -d macos
```

也可以先通过 `flutter devices` 查看设备 ID，再将 `macos` 替换为目标设备。

## 静态图片验证

静态图片模式不需要相机，会直接运行真实的 MediaPipe 模型和 Flutter Scene 姿态映射：

```sh
flutter run -d macos --dart-define=FACE_IMAGE_TEST=true
```

控制台会输出图片尺寸、关键点数量、头部姿态、脸宽、媒体管线姿态平移和最终相机空间锚点位置。

## 测试

```sh
flutter test --enable-flutter-gpu --enable-impeller
```

或在仓库根目录运行：

```sh
./tool/test.sh
```
