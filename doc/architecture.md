# 架构说明

`flutter_ar_plus` 的核心职责是把实时相机图像中的人脸姿态转换为 Flutter Scene 可以直接消费的
相机空间变换，并保持相机、推理、场景与生命周期之间的资源边界清晰。

## 数据流

```text
CameraImage / CameraImageData
  ↓
FaceMeshFrame 格式转换
  ↓
MediaPipe 工作 isolate
  ↓
FaceMeshResult
  ↓
ArFacePoseMapper
  ↓
ArFaceAnchor + Flutter Scene Node
```

`ArFacePoseMapper` 及以上部分属于 Dart 层。相机实现、Flutter GPU 和 MediaPipe 原生库由依赖包
提供。

## 模块职责

### `ArView`

`ArView` 是组件入口，负责：

- 请求相机权限并选择相机。
- 创建平台相机控制器。
- 订阅图像流并按目标帧率采样。
- 创建和管理 MediaPipe 工作 isolate。
- 将 `CameraImage` 转换为 MediaPipe 接受的像素格式。
- 维护当前 `ArFaceAnchor`。
- 处理应用前后台生命周期。
- 显示相机预览、Flutter Scene、加载层、错误层和追踪提示。

`ArView` 不拥有应用传入的 `Scene`，也不会释放它。

### `ArFacePoseMapper`

`ArFacePoseMapper` 是无副作用的纯计算组件：

1. 将 MediaPipe 归一化关键点映射到显示坐标。
2. 处理 `BoxFit.cover` 产生的裁剪偏移。
3. 使用米制几何结果估计距离和脸宽。
4. 将 MediaPipe 姿态矩阵转换为 Flutter Scene 内容旋转。
5. 根据锚点原点计算最终相机空间变换。

该映射器可用于静态图片测试和自定义渲染管线，不要求相机已启动。

### `ArFaceAnchor`

锚点封装当前帧的追踪结果，并持有 Flutter Scene 节点。一个锚点在连续追踪周期内保持稳定；
人脸丢失超过 `anchorLostGracePeriod` 后移除。

锚点公开的变换、旋转和位置均为快照值。内部状态只由 `ArView` 更新。

### `ArViewController`

控制器提供命令式场景操作。节点和变换方法可以在视图挂载前使用；涉及相机、视口和射线的
能力必须在视图挂载后使用。

控制器不持有场景所有权，也不创建渲染资源。

### `ArViewDelegate`

委托负责人脸内容创建和生命周期通知。视图负责追踪，委托负责节点结构，这一职责分离使应用
可以复用同一套追踪数据渲染不同内容。

## 线程与资源模型

- MediaPipe 推理运行在独立工作 isolate 中。
- 相机帧到达主 isolate 后转换为轻量帧对象，再送入管线。
- 同一时间只处理一帧；管线忙碌时丢弃新帧，避免任务积压。
- 相机控制器、MediaPipe 管线和表情处理器由 `ArView` 创建并释放。
- `Scene` 和其中由应用手动创建的长期节点由应用释放。
- 人脸节点由 `ArView` 添加到场景并在追踪结束时移除；节点内部的纹理或自定义资源应在
  `didRemoveNode` 中按应用策略释放。

## 坐标转换

MediaPipe 姿态矩阵使用行主序的规范人脸到相机变换，并包含统一缩放。库会提取归一化旋转，
再应用 Flutter Scene 所需的轴向映射：

- 相机空间 `+Z` 指向远离相机。
- 人脸内容局部 `+Z` 指向内容正面。
- 正面人脸静止时，内容正面朝向相机。
- 偏航方向与真实头部一致，俯仰不会发生镜像。

`ArFacePoseMapper` 使用估算的脸部中心距离。鼻尖锚点会沿人脸局部轴从鼻尖表面向后移动到
脸部中心，避免鼻部内容陷入模型。

## 相机与镜像

Android 和 iOS 的相机传感器方向、设备方向和前置相机镜像规则不同。`ArView` 会：

- 根据设备方向计算 MediaPipe 输入旋转。
- 在 Android 前置相机路径中应用与预览一致的镜像语义。
- 在 macOS 路径中避免重复镜像 BGRA 图像流。

如果应用自定义相机预览或额外处理输入帧，必须确保预览与推理使用相同的水平镜像语义。

## 错误边界

以下错误统一包装为 `ArViewException`：

- 权限拒绝或受限。
- 相机不可用或初始化失败。
- MediaPipe 管线启动或推理失败。
- 模型加载失败。
- 不支持的目标平台。
- 委托回调失败。

`errorBuilder` 负责构建主错误界面。`onError` 接收运行错误，适合日志、监控或业务层上报。
如果 `onError` 自身抛错，库通过 `FlutterError.reportError` 报告，避免递归回调。

## 扩展点

- 使用不同 `ArViewDelegate` 渲染模型、粒子、Widget 或自定义组件。
- 通过 `ArViewController` 在运行时增删和变换场景节点。
- 使用 `ArFacePoseMapper` 构建离线图片验证或自定义渲染管线。
- 通过 `enableFaceBlendshapes` 驱动表情动画。
- 通过 `anchorOrigin` 在脸部中心与鼻尖之间选择挂载原点。

## 测试策略

- `ar_face_pose_test.dart` 验证姿态旋转、异常输入和回退逻辑。
- `ar_view_controller_test.dart` 验证场景所有权、节点变换和公开默认值。
- `ar_view_exception_test.dart` 验证错误分类与设置入口。
- `ar_view_layout_test.dart` 验证相机预览布局。
- 示例应用包含真实图片推理与 Flutter Scene 渲染验证。

涉及 Flutter GPU 和 Flutter Scene 的测试应由 `tool/test.sh` 启用相应参数后运行。
