# 安全策略

## 支持版本

| 版本 | 安全更新 |
| --- | --- |
| 1.0.x | 支持 |
| < 1.0.0 | 不支持 |

## 报告安全问题

请勿通过公开 Issue 报告可能影响用户隐私、相机权限、任意代码执行或依赖供应链安全的问题。

优先使用仓库的 GitHub 私密安全报告功能：

<https://github.com/yuanzhihong/flutter_ar_plus/security/advisories/new>

报告中请包含：

- 受影响版本和平台。
- 问题描述与潜在影响。
- 最小复现条件或概念验证。
- 相关日志、堆栈和配置。
- 是否已经公开披露。
- 建议的修复方向（如有）。

维护者会尽快确认收到报告，评估影响，并在修复完成前避免公开敏感细节。

## 相机与隐私

`flutter_ar_plus` 会访问相机图像并将其送入本地 MediaPipe 推理流程。项目本身不包含上传相机
图像的逻辑。应用开发者应：

- 明确说明相机用途，并只在获得授权后访问相机。
- 避免在日志、崩溃报告或分析事件中记录原始图像。
- 对保存或传输的图像遵循适用的隐私法规。
- 在示例、Issue 和 Pull Request 中对人脸图像进行脱敏。

## 依赖安全

项目依赖 Flutter、`camera`、`mediapipe_face_mesh`、`flutter_scene` 和
`permission_handler` 等第三方包。应用开发者应定期检查依赖更新和安全公告，并在发布前运行：

```sh
flutter pub outdated
flutter pub deps
```
