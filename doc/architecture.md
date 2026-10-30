# 架构说明

`flutter_ar` 的核心目标是把实时相机图像中的人脸姿态，转换为 Flutter Scene 可以直接消费的
相机空间变换。

## 数据流

```text
相机图像
  ↓
Platform / CameraImage
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

## 模块职责

### `ArView`

`ArView` 是组件入口，负责：

- 请求相机权限并选择相机。
- 初始化平台相机控制器。
- 订阅图像流并按目标帧率采样。
- 创建和管理 MediaPipe 工作 isolate。
- 把 `CameraImage` 转换为 MediaPipe 接受的像素格式。
- 维护当前 `ArFaceAnchor`。
- 处理应用前后台生命周期。
- 显示相机预览、场景、加载层、错误层和统计信息。

`ArView` 不持有场景所有权，也不会释放应用传入的 `Scene`。

### `ArFacePoseMapper`

`ArFacePoseMapper` 负责纯计算：

1. 将 MediaPipe 归一化关键点映射到显示坐标。
2. 处理 `BoxFit.cover` 造成的裁剪。
3. 使用米制人脸几何结果估计距离和脸宽。
4. 将 MediaPipe 姿态矩阵转换为 Flutter Scene 内容旋转。
5. 根据锚点原点计算最终相机空间变换。

该映射器不依赖相机或渲染器，可用于静态图片和离线验证。

### `ArFaceAnchor`

锚点封装一帧人脸追踪结果，并持有 Flutter Scene 节点。锚点在一个连续追踪周期内保持稳定，
人脸丢失超过 `anchorLostGracePeriod` 后销毁。

### `ArViewController`

控制器提供命令式场景操作。节点和变换方法可以在视图挂载前使用；涉及相机、视口和射线的
能力必须在视图挂载后使用。

### `ArViewDelegate`

委托负责人脸内容创建和生命周期通知。视图负责追踪，委托负责内容，这一职责分离使应用可以
复用同一套追踪数据渲染不同节点结构。

## 线程与资源模型

- MediaPipe 推理运行在独立工作 isolate 中。
- 相机帧到达主 isolate 后转换为轻量帧对象再送入管线。
- 同一时间只处理一帧，管线忙碌时会丢弃新帧，避免积压。
- 相机控制器、MediaPipe 管线和表情处理器由 `ArView` 创建并释放。
- `Scene` 由应用创建并释放。

## 坐标转换

MediaPipe 姿态矩阵使用行主序的规范人脸到相机变换，并包含统一缩放。库会提取归一化旋转，
再应用 Flutter Scene 所需的轴向映射：

- 相机空间 `+Z` 指向远离相机。
- 人脸内容局部 `+Z` 指向内容正面。
- 正面人脸静止时，内容正面朝向相机。
- 偏航方向与真实头部一致，俯仰不会发生镜像。

## 错误边界

以下错误统一包装为 `ArViewException`：

- 权限拒绝或受限。
- 相机不可用或初始化失败。
- MediaPipe 管线启动或推理失败。
- 模型加载失败。
- 不支持的目标平台。

自定义回调和界面构建器的异常不会吞掉，而会通过 Flutter 错误报告机制或 `onError` 报告。

## 扩展点

- 使用不同 `ArViewDelegate` 渲染模型、粒子、Widget 或自定义组件。
- 通过 `ArViewController` 在运行时增删场景节点。
- 使用 `ArFacePoseMapper` 构建离线图片验证或自定义渲染管线。
- 通过 `enableFaceBlendshapes` 驱动表情动画。
- 默认使用 ARKit 脸部中心坐标，并可通过 `faceAnchorOrigin` 切换到鼻尖坐标。
