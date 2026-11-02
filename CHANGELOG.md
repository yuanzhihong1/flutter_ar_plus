# 更新日志

本文件记录 `flutter_ar_plus` 的重要变更。版本号遵循语义化版本规范。

## 1.0.0 - 2026-11-02

### 首个正式版本

- 发布 `flutter_ar_plus` 首个正式稳定版本，公开 API 进入 1.x 兼容周期。
- Dart 包、Android、iOS 和 macOS 平台元数据统一为 `1.0.0`。

### 核心能力

- 提供基于相机预览、MediaPipe Face Mesh 和 Flutter Scene 的实时人脸 AR 叠加能力。
- 提供 `ArView`、`ArViewController`、场景委托和命令式场景控制 API。
- 支持脸部中心与鼻尖锚点，公开位置、旋转、脸宽、相机距离、屏幕坐标、网格、关键点和
  头部姿态。
- 支持将 glTF/GLB 模型、程序化网格和 `WidgetComponent` 挂载到人脸锚点。
- 支持投影、反投影、射线检测、模型加载、相机权限和应用生命周期恢复。
- 支持可选的面部表情系数，以及加载、错误和追踪状态界面。
- 支持 Android、iOS 和 macOS。

### 兼容性

- 稳定公开 API 统一从 `package:flutter_ar_plus/flutter_ar_plus.dart` 导出。
- 自 `1.0.0` 起，不兼容的公开 API 变更会提升主版本号。
- `lib/src/`、原生通道名称和平台插件内部实现不属于公开兼容范围。

### 文档与质量

- 提供安装、平台配置、API 参考、架构、性能、限制、故障排查和迁移文档。
- 提供 Android、iOS 和 macOS 示例及自动化测试流程。
- 环境要求为 Flutter 3.47.0 或更高版本、Dart 3.13.7 或更高版本。
