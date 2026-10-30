# 更新日志

本文件记录 `flutter_ar` 的重要变更。版本号遵循语义化版本规范。

## 0.1.0 - 2026-10-30

### API 规范化

- 默认人脸锚点改为 `ArFaceAnchorOrigin.faceCenter`，与 ARKit 脸部中心坐标一致。
- 默认帧率改为 60 FPS，相机分辨率改为 `high`，并默认启用表情系数。
- 将 `ArView` 与 `ArViewController` 确立为标准 Dart 风格 API。
- 将 `ARView`、`ARViewController` 标记为弃用兼容别名。
- 将 `isFaceTrackingEnabled` 重命名为 `faceTrackingEnabled`，旧参数暂时保留。
- 将 `ArViewController.pointOfView` 重命名为 `camera`，旧 getter 暂时保留。
- 为 `ArViewController` 新增 `isTracking`、`currentFaceAnchor`、`retry()` 和
  `openSettings()`。
- 增加 `unprojectPoint` 的距离参数校验。

### 项目结构

- 将实现文件迁移到 `lib/src/`，公开 API 统一从 `package:flutter_ar/flutter_ar.dart`
  导出。
- 移除公开入口中的示例平台方法通道 API，避免将生成代码误认为稳定接口。
- 清理未声明支持的 Linux、Windows、Web 目录、IDE 配置和本地生成文件。
- 启用严格类型检查、公开 API 文档检查和更完整的 lint 规则。

### 文档与注释

- 将库内手写注释、错误文案、示例界面和测试描述统一为中文。
- 重写中文 README、示例说明、贡献指南、安全策略和发布流程。
- 新增安装指南、API 参考、架构说明与故障排查文档。
- 补充 GitHub CI、Issue 和 Pull Request 模板。

### 兼容性

- 默认锚点从鼻尖改为脸部中心。依赖鼻尖默认值的内容应显式传入
  `faceAnchorOrigin: ArFaceAnchorOrigin.noseTip`，或将内容从脸部中心偏移到目标区域。
- 默认分辨率、帧率与表情系数已调整，性能敏感场景可按需覆盖。
- 旧 API 名称至少保留至下一个次版本；迁移期间会产生弃用警告。

## 0.0.1

- 新增受 `ARSCNView` 启发的 `ArView` API，支持场景、委托、帧率和统计信息控制。
- 使用 MediaPipe Face Mesh 追踪单张人脸，并公开鼻尖锚点、网格、关键点、头部姿态和生命周期回调。
- 新增相机权限处理、应用生命周期恢复、加载/错误界面，以及 Android、iOS、macOS 的鼻尖小猪示例。
- 新增 macOS 相机支持和静态图片验证流程。
- 使面部内容跟随头部旋转，并遵循 Flutter Scene 的局部 `+Z` 朝前约定。
- 新增 `ArFaceAnchorOrigin.faceCenter`，便于迁移 ARKit 脸部中心坐标内容。
- 新增可选的人脸表情系数：`enableFaceBlendshapes` 与 `ArFaceAnchor.blendshapes`。
- 新增启用 Flutter GPU 的测试脚本。
- 随包提供 iOS 隐私清单。
- 修复 iOS 竖屏相机预览拉伸问题。
