# 贡献指南

感谢你参与 `flutter_ar_plus`。提交代码前，请阅读并遵循以下约定。

## 开发环境

- Flutter 3.47.0 或更高版本。
- Dart 3.13.7 或更高版本。
- Android、iOS 或 macOS 开发环境。
- 建议使用支持 Flutter GPU 的 macOS 环境运行完整测试。

初始化：

```sh
flutter pub get
cd example
flutter pub get
cd ..
```

## 开发流程

1. 先搜索现有 Issue，避免重复工作。
2. 对较大的 API 调整或行为变化，先创建 Issue 说明方案。
3. 从最新 `main` 创建分支，建议使用 `codex/`、`feat/`、`fix/` 或 `docs/` 前缀。
4. 保持提交范围聚焦，避免在同一提交中混合无关重构。
5. 提交 Pull Request 前完成格式、分析和测试。

## 代码规范

- 所有手写注释和公开文档使用中文。
- 代码标识符、平台 API、依赖包名和协议名保留英文原名称。
- 公开 API 必须包含 Dart 文档注释。
- 类型、参数、getter 和回调命名遵循 Dart 与 Flutter 生态惯例。
- 不使用其他平台或框架的名称作为公开 API 的设计理由。
- 不保留没有明确迁移周期的兼容别名。
- 新增公开类型应从 `lib/flutter_ar_plus.dart` 显式导出。
- 避免在公开 API 中暴露无必要的实现细节或依赖类型。
- 新增第三方依赖前说明必要性，并评估许可证、平台支持和维护状态。
- 保持相机、MediaPipe 和场景资源的所有权边界清晰。

## API 设计约定

- 优先使用描述行为而非视觉风格的名称。
- 只用于调试或占位的参数必须准确命名，不能暗示不存在的统计能力。
- 回调必须明确同步或异步、调用时机和错误传播方式。
- 破坏性变更提升次版本号，并同步更新迁移指南。
- 公开 API 示例必须使用 `package:flutter_ar_plus/flutter_ar_plus.dart`。

## 格式与分析

```sh
dart format lib test example/lib example/test
flutter analyze
```

Pull Request 不允许存在格式差异或分析器告警。

## 测试

完整测试：

```sh
./tool/test.sh
```

仅运行库测试：

```sh
flutter test --enable-flutter-gpu --enable-impeller
```

新增行为应补充对应测试。涉及渲染或 Flutter Scene 的测试应能在 GPU 启用时运行。

## 文档

行为或 API 变化时，请同步更新：

- `README.md`
- `doc/api-reference.md`（涉及公开 API 时）
- `CHANGELOG.md`
- `doc/migration-guide.md`（涉及破坏性变更时）
- 相关专题文档与示例说明

文档不得把其他平台或框架描述为本库的行为基准。性能结论应注明测试条件，不承诺所有设备
都能达到固定帧率。

文档统一使用中文；代码块中的变量名和 API 名称保持英文。

## Pull Request 检查项

- [ ] 变更范围清晰，已关联相关 Issue。
- [ ] 新 API 有中文文档注释和测试。
- [ ] 未引入不必要的公开 API。
- [ ] `dart format`、`flutter analyze` 和 `./tool/test.sh` 全部通过。
- [ ] 已更新 README、API 文档和 CHANGELOG。
- [ ] 未提交生成文件、本地路径、密钥或隐私数据。

## 提交信息

建议使用 Conventional Commits 风格：

```text
feat: 新增人脸锚点屏幕投影测试
fix: 修复竖屏预览宽高比
docs: 完善中文 API 文档
refactor: 拆分公开 API 与内部实现
```

## 许可证

提交贡献即表示你同意将贡献内容按本项目的 MIT License 发布。
