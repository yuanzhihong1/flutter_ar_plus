## 0.0.1

* Add an `ARSCNView`-style `ArView` API with scene/delegate, frame-rate, and
  statistics controls.
* Track one face with MediaPipe Face Mesh and expose the nose anchor transform,
  mesh, landmarks, head pose, and lifecycle callbacks.
* Add camera permission handling, lifecycle recovery, loading/error UI, and an
  Android/iOS/macOS nose-pig example using Flutter Scene.
* Add macOS camera support and a still-image Face Mesh + Flutter Scene
  verification harness.
* Align face-attached content with the tracked head rotation in camera space,
  including Flutter Scene's local +Z-forward convention.
