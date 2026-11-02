# 更新日志

本文件记录 `flutter_ar` 的重要变更。版本号遵循语义化版本规范。

## 0.2.0 - 2026-11-02

### 破坏性 API 调整

- 移除 `ARView` 与 `ARViewController` 兼容别名，统一使用 `ArView` 和 `ArViewController`。
- 移除 `isFaceTrackingEnabled` 参数，统一使用 `faceTrackingEnabled`。
- 移除 `ArViewController.pointOfView`，统一使用 `camera`。
- 将 `faceAnchorOrigin` 重命名为 `anchorOrigin`，与 `ArFacePoseMapper.anchorOrigin` 保持一致。
- 将 `showsStatistics` 重命名为 `showTrackingIndicator`，准确描述其只显示追踪提示的行为。
- 新增 `ArFaceAnchor.position`，提供 AR 相机空间中的当前位置副本。
- 新增 `ArViewErrorCallback` 公开 typedef，明确 `onError` 的签名。
- 运行时修改 `anchorOrigin` 会重建当前人脸锚点，避免锚点原点与节点位置不一致。

### 文档与项目质量

- 重写 README，补充安装、平台配置、所有权、兼容范围、性能和示例入口。
- 完善中文 API 参考、架构说明、故障排查和发布流程。
- 新增性能指南、平台与能力限制、0.1.x → 0.2.0 迁移指南。
- 明确 `lib/src/`、原生通道名称和平台插件内部实现不属于公开兼容范围。
- 示例应用改用 Flutter SDK 自带 Cupertino 组件，移除 `cupertino_ui` 与 `cupertino_icons`
  依赖。

### 兼容性

- 旧类型、参数和 getter 已被直接移除，不提供兼容层。
- 升级步骤见 `doc/migration-guide.md`。

## 0.1.0 - 2026-10-30

### API 规范化

- 默认人脸锚点改为 `ArFaceAnchorOrigin.faceCenter`。
- 默认帧率改为 60 FPS，相机分辨率改为 `high`，并默认启用表情系数。
- 确立 `ArView` 与 `ArViewController` 为标准 Dart 风格 API。
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
  `anchorOrigin: ArFaceAnchorOrigin.noseTip`，或将内容从脸部中心偏移到目标区域。
- 默认分辨率、帧率与表情系数已调整，性能敏感场景可按需覆盖。

## 0.0.1

- 新增基于 Flutter Scene 的 `ArView` API，支持场景、委托、帧率和状态提示控制。
- 使用 MediaPipe Face Mesh 追踪单张人脸，并公开鼻尖锚点、网格、关键点、头部姿态和生命周期
  回调。
- 新增相机权限处理、应用生命周期恢复、加载/错误界面，以及 Android、iOS、macOS 的鼻尖小猪
  示例。
- 新增 macOS 相机支持和静态图片验证流程。
- 使面部内容跟随头部旋转，并遵循 Flutter Scene 的局部 `+Z` 朝前约定。
- 新增 `ArFaceAnchorOrigin.faceCenter`，支持脸部中心锚点。
- 新增可选的人脸表情系数：`enableFaceBlendshapes` 与 `ArFaceAnchor.blendshapes`。
- 新增启用 Flutter GPU 的测试脚本。
- 随包提供 iOS 隐私清单。
- 修复 iOS 竖屏相机预览拉伸问题。
