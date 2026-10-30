# 发布流程

本文面向维护者，说明 `flutter_ar` 的版本发布步骤。

## 版本策略

项目使用语义化版本：

- 主版本：不兼容的稳定 API 变更。
- 次版本：向后兼容的功能新增与弃用。
- 修订版本：向后兼容的缺陷修复和文档修正。

`0.x` 阶段仍可能发生少量不兼容调整，所有破坏性变更必须在 `CHANGELOG.md` 中明确说明。

## 发布前检查

1. 确认工作区干净，目标变更已合并。
2. 更新 `pubspec.yaml` 中的版本号。
3. 更新 `CHANGELOG.md`，写明新增、变更、修复和迁移说明。
4. 检查 README、API 文档和示例是否与实现一致。
5. 运行格式检查：

   ```sh
   dart format --output=none --set-exit-if-changed lib test example/lib example/test
   ```

6. 运行静态分析：

   ```sh
   flutter analyze
   ```

7. 运行完整测试：

   ```sh
   ./tool/test.sh
   ```

8. 至少在一个真实 Android 或 iOS 设备上运行示例。
9. 在 macOS 上运行静态图片验证和实时相机验证。
10. 执行发布预检：

    ```sh
    flutter pub publish --dry-run
    ```

## 发布步骤

1. 创建发布提交，例如 `chore: release 0.1.0`。
2. 创建带注解标签：

   ```sh
   git tag -a v0.1.0 -m "flutter_ar 0.1.0"
   ```

3. 推送提交与标签。
4. 发布到 pub.dev：

   ```sh
   flutter pub publish
   ```

5. 在 GitHub Releases 中补充中文发行说明。

## 回滚原则

- pub.dev 已发布版本不可删除后重新使用同一版本号。
- 若发现严重问题，发布新的修订版本并说明问题与修复。
- 若需要撤回版本，优先发布弃用说明或修复版本，并联系 pub.dev 管理员处理安全风险。

## 发布后检查

- 确认 pub.dev 页面显示正确的 README、CHANGELOG 和许可证。
- 检查示例依赖是否能解析新版本。
- 验证文档链接和徽章。
- 关注 Issue 与安全报告中与本次发布相关的问题。
