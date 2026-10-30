# 贡献指南

感谢你参与 `flutter_ar`。提交代码前，请阅读并遵循以下约定。

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
- 代码标识符、平台 API、依赖包名和协议名保留英文原名。
- 公开 API 必须包含 Dart 文档注释。
- 新代码使用 `ArView`、`ArViewController` 等 Dart 风格名称。
- 不直接修改 `lib/src` 之外的内部实现导出边界。
- 新增公开类型应从 `lib/flutter_ar.dart` 显式导出。
- 避免在公开 API 中暴露无必要的实现细节或依赖类型。
- 保持相机、MediaPipe 和场景资源的所有权边界清晰。

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
- 示例代码和示例说明（涉及使用方式时）

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
