/// 基于相机与 MediaPipe Face Mesh 的 Flutter 实时人脸 AR 库。
///
/// 对外使用时只需导入：
///
/// ```dart
/// import 'package:flutter_ar_plus/flutter_ar_plus.dart';
/// ```
///
/// 主要入口是 [ArView]，它负责相机预览、人脸追踪和 Flutter Scene
/// 场景叠加；[ArViewController] 提供命令式的节点与相机空间查询能力。
/// 实现细节位于 `lib/src`，不属于稳定公开 API。
library;

export 'src/ar_face_pose.dart';
export 'src/ar_view.dart';
