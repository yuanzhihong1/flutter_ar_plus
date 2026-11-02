# flutter_ar_plus 文档

本目录包含 `flutter_ar_plus` 的中文使用、设计和维护文档。

## 新用户

1. [快速开始](getting-started.md)：安装、平台配置和最小可运行示例。
2. [平台与能力限制](limitations.md)：确认目标平台和功能边界。
3. [API 参考](api-reference.md)：公开类型、参数、回调和坐标约定。

## 深入使用

- [架构说明](architecture.md)：相机帧、MediaPipe、姿态映射和 Flutter Scene 的数据流。
- [性能指南](performance.md)：帧率、分辨率、场景复杂度和降级策略。
- [故障排查](troubleshooting.md)：权限、GPU、相机、追踪和渲染问题。
- [迁移指南](migration-guide.md)：版本升级与破坏性 API 变更。

## 维护者

- [发布流程](release-process.md)：版本、检查项和发布步骤。
- [贡献指南](../CONTRIBUTING.md)：开发环境、代码规范与 Pull Request 流程。
- [安全策略](../SECURITY.md)：漏洞报告方式和支持版本。
- [行为准则](../CODE_OF_CONDUCT.md)：社区交流规范。
- [支持说明](../SUPPORT.md)：问题反馈与响应方式。

## 文档维护原则

1. 面向使用者的公开文档统一使用中文。
2. API 名称、类型名和平台专有名词保留原始英文拼写。
3. 代码示例必须可直接复制，并与当前公开 API 保持一致。
4. 文档不把其他平台或框架当作行为基准，只描述本库自身约定。
5. 行为变化必须同步更新 README、API 文档和 `CHANGELOG.md`。
6. 破坏性变更必须补充迁移指南。
7. 性能或平台结论应说明测试条件，不承诺固定帧率或所有设备一致的表现。
