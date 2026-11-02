# 发布流程

本文面向维护者，说明 `flutter_ar_plus` 的版本发布步骤。

## 版本策略

项目遵循语义化版本：

- 主版本：不兼容的公开 API 变更。
- 次版本：向后兼容的新增能力或弃用。
- 修订版本：向后兼容的缺陷修复和文档修正。

所有破坏性变更必须：

1. 提升次版本号。
2. 在 `CHANGELOG.md` 中明确列出。
3. 更新 `doc/migration-guide.md`。
4. 在示例与公开文档中移除旧写法。

## 发布前检查

1. 确认工作区干净，目标变更已合并。
2. 更新 `pubspec.yaml`、平台 podspec 与 Android Gradle 中的版本号。
3. 更新 `CHANGELOG.md`，写明新增、变更、修复和迁移说明。
4. 检查 README、`doc/` 和示例是否与实现一致。
5. 检查公开 API 文档注释是否完整。
6. 运行格式检查：

   ```sh
   dart format --output=none --set-exit-if-changed lib test example/lib example/test
   ```

7. 运行静态分析：

   ```sh
   flutter analyze
   ```

8. 运行完整测试：

   ```sh
   ./tool/test.sh
   ```

9. 至少在一个真实 Android 或 iOS 设备上运行示例。
10. 在 macOS 上运行静态图片验证和实时相机验证。
11. 执行发布预检：

    ```sh
    flutter pub publish --dry-run
    ```

## 发布步骤

1. 创建发布提交，例如 `chore: release 1.0.0`。
2. 创建带注解标签：

   ```sh
   git tag -a v1.0.0 -m "flutter_ar_plus 1.0.0"
   ```

3. 推送提交与标签。
4. 发布到 pub.dev：

   ```sh
   flutter pub publish
   ```

5. 在 GitHub Releases 中补充中文发行说明。

## 破坏性变更检查

发布包含破坏性变更的新主版本前确认：

- [ ] 旧 API 已从公开入口移除，而不是继续保留未记录别名。
- [ ] 迁移指南包含旧名称、新名称和示例。
- [ ] CHANGELOG 说明影响范围。
- [ ] 示例、README、API 文档和测试不再使用旧 API。
- [ ] 版本约束与文档中的安装命令一致。

## 回滚原则

- pub.dev 已发布版本不可删除后重新使用同一版本号。
- 若发现严重问题，发布新的修订版本并说明问题与修复。
- 若需要撤回版本，优先发布弃用说明或修复版本，并联系 pub.dev 管理员处理安全风险。

## 发布后检查

- 确认 pub.dev 页面显示正确的 README、CHANGELOG 和许可证。
- 检查示例依赖是否能解析新版本。
- 验证文档链接和徽章。
- 关注 Issue 与安全报告中与本次发布相关的问题。
