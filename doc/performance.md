# 性能指南

实时人脸 AR 同时消耗相机、CPU、GPU 和内存带宽。实际性能取决于设备、分辨率、MediaPipe
模型、场景复杂度和应用主 isolate 的工作量。本文提供调优方向，不承诺固定帧率。

## 初始配置

首次接入建议从较低负载开始：

```dart
ArView(
  scene: scene,
  cameraResolution: ResolutionPreset.medium,
  preferredFramesPerSecond: 30,
  enableFaceBlendshapes: false,
);
```

确认追踪和渲染正确后，再逐步提高分辨率、帧率或启用表情系数。

## 主要开销

| 来源 | 影响因素 | 常见优化 |
| --- | --- | --- |
| 相机采集 | 分辨率、帧率、格式转换 | 降低 `cameraResolution` 或目标帧率 |
| MediaPipe 推理 | 模型、图像尺寸、CPU 能力 | 关闭不需要的表情系数，降低输入帧率 |
| Flutter Scene | 网格、材质、纹理、后处理 | 简化场景，减少透明与高开销着色 |
| Widget 合成 | 每帧捕获、尺寸、输入模式 | 只对必要内容使用 `WidgetComponent` |
| Dart 回调 | 每帧分配、同步 I/O、对象创建 | 预处理资源，避免在回调内做重工作 |

## 帧率

`preferredFramesPerSecond` 同时影响相机帧采样和 Flutter Scene 的最大帧率。移动设备上的实际
结果不会超过设备能力，也不会超过应用其他渲染负载允许的帧率。

建议按场景选择：

- 30 FPS：通常适合移动设备、复杂场景和功耗敏感应用。
- 60 FPS：适合高性能设备、简单场景和需要更顺滑交互的效果。
- 15–20 FPS：可用于静态贴纸、低功耗或长时间运行场景，但头部运动可能显得跳跃。

降低渲染帧率不能消除一次性资源加载或每帧主 isolate 工作。应同时优化回调与场景复杂度。

## 分辨率

`ResolutionPreset.high` 能提供更多脸部细节，但相机采集、格式转换和推理成本都会增加。长距离
或小脸追踪可能受益于更高分辨率；近景、简单贴纸和低端设备通常从 `medium` 开始更合适。

不要仅根据相机标称分辨率判断性能。设备内部的缩放、像素格式和硬件路径同样重要。

## 表情系数

`enableFaceBlendshapes` 默认开启。表达式处理器增加一次额外推理，并且会在主 isolate 接收
结果后同步更新锚点。

如果应用只显示三维贴纸或静态模型，建议关闭：

```dart
ArView(
  scene: scene,
  enableFaceBlendshapes: false,
);
```

如果必须使用表情，优先在业务层合并或抽样消费系数，不要在每帧创建大量临时对象。

## 场景内容

- 优先使用共享材质和共享几何体。
- 控制纹理尺寸，避免同时加载多份大图。
- 减少透明材质、过绘和全屏后处理。
- 对不可见节点及时从场景移除。
- 避免每帧重建 `WidgetComponent` 或重新加载模型。
- 在低端设备上减少骨骼、粒子和高细分网格。

## 回调

`didUpdateNode` 和 `onFaceAnchorUpdated` 每帧可能被调用。推荐只做必要的状态更新：

```dart
@override
void didUpdateNode(ArView view, ArFaceAnchor anchor) {
  final target = contentNode;
  if (target == null) {
    return;
  }
  target.rotation = anchor.rotation;
}
```

以下操作不适合放在每帧回调中：

- 文件或网络 I/O。
- 模型、纹理或着色器加载。
- 大量日志输出。
- 重建整棵场景图。
- 依靠同步计算遍历大型数据结构。

## 测量方法

使用 Flutter DevTools 检查：

- UI 与 Raster 线程帧耗时。
- 主 isolate 是否因格式转换或回调阻塞。
- 场景构建、纹理上传和 Widget 捕获是否产生尖峰。
- 帧丢弃是否集中在追踪更新或模型加载阶段。

同时观察设备温度、电量消耗和长时间运行后的稳定性。短时间高帧率不代表持续性能良好。

## 降级策略

建议提供至少两档配置，并在运行时允许切换：

```dart
const bool lowPower = true;

ArView(
  scene: scene,
  cameraResolution:
      lowPower ? ResolutionPreset.low : ResolutionPreset.high,
  preferredFramesPerSecond: lowPower ? 20 : 60,
  enableFaceBlendshapes: !lowPower,
);
```

降级时应优先降低推理与 Widget 捕获成本，再调整场景细节。只降低渲染帧率而不降低推理成本，
通常无法解决持续发热问题。
