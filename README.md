# flutter_ar

Camera-driven face AR for Flutter, built with:

- [`camera`](https://pub.dev/packages/camera) for Android/iOS previews and frames
- [`camera_macos`](https://pub.dev/packages/camera_macos) for the macOS preview and BGRA frames
- [`mediapipe_face_mesh`](https://pub.dev/packages/mediapipe_face_mesh) for 478-point face tracking
- [`flutter_scene`](https://pub.dev/packages/flutter_scene) for the 3D overlay
- [`vector_math`](https://pub.dev/packages/vector_math) for anchor transforms
- [`permission_handler`](https://pub.dev/packages/permission_handler) for camera permission and Settings recovery

`ArView` follows the useful shape of Swift's `ARSCNView`:

| ARSCNView | ArView |
| --- | --- |
| `scene` | `ArView(scene: scene)` |
| `delegate` | `ArView(delegate: ...)` |
| `ARSCNViewDelegate.nodeFor anchor` | `ArViewDelegate.nodeForFaceAnchor` |
| `didAdd/didUpdate/didRemove node` | `ArViewDelegate.didAddNode/didUpdateNode/didRemoveNode` |
| `preferredFramesPerSecond` | `ArView(preferredFramesPerSecond: 30)` |
| `showsStatistics` | `ArView(showsStatistics: true)` |

The view owns the camera and tracking session. The `Scene` remains application-owned. While a face is visible, `ArView` maintains one `ArFaceAnchor` and keeps its `Node` positioned at the nose in a perspective camera space aligned to the preview. The anchor also inherits MediaPipe's full head rotation, so content added to the node stays attached to the face instead of always facing the camera.

Face-anchor content follows Flutter Scene's local axis convention: `+Z` is
forward, `+Y` is up, and `+X` is the content's right side. A model authored to
face `+Z` therefore keeps the same yaw, pitch, and roll as the tracked person.

## Usage

```dart
import 'package:camera/camera.dart';
import 'package:flutter_ar/flutter_ar.dart';
import 'package:flutter_scene/scene.dart';

class NosePigDelegate extends ArViewDelegate {
  const NosePigDelegate();

  @override
  Node? nodeForFaceAnchor(ArView view, ArFaceAnchor anchor) {
    return Node(name: 'pig-at-nose')
      ..addComponent(
        WidgetComponent(
          child: const Text(
            '🐷',
            textDirection: TextDirection.ltr,
            style: TextStyle(fontSize: 118),
          ),
          size: const Size(180, 180),
          worldHeight: 0.08,
          input: WidgetInput.manual,
        ),
      );
  }
}

class FaceArPage extends StatefulWidget {
  const FaceArPage({super.key});

  @override
  State<FaceArPage> createState() => _FaceArPageState();
}

class _FaceArPageState extends State<FaceArPage> {
  final Scene scene = Scene();

  @override
  void dispose() {
    scene.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ArView(
      scene: scene,
      delegate: const NosePigDelegate(),
      cameraLensDirection: CameraLensDirection.front,
      cameraResolution: ResolutionPreset.medium,
      preferredFramesPerSecond: 30,
      showsStatistics: true,
    );
  }
}
```

The complete example is in [`example/lib/main.dart`](example/lib/main.dart).

## Static image verification

The example includes a still-image harness that runs the real MediaPipe detector,
mesh model, native geometry solver, and Flutter Scene pose mapping without a
camera. It draws the 478-point mesh, the projected nose target, and the 3D nose
effect together so coordinate and orientation regressions are visible.

```sh
cd example
flutter run -d macos --dart-define=FACE_IMAGE_TEST=true
```

The test logs image size, landmark count, head pose, metric measurements,
MediaPipe pose translation, and the final camera-space anchor position.

## Face anchor

`ArFaceAnchor` exposes:

- `node`: the persistent Flutter Scene node for this tracked face
- `transform`: meters in camera space (`+X` right, `+Y` up, `+Z` away)
- `screenPosition`: normalized nose point in the displayed camera image
- `distanceMeters` and `faceWidthMeters`
- `mesh`, `landmarks`, and `headPose`

Add a `Mesh`, glTF model, `WidgetComponent`, particles, or other scene content to the node returned by `nodeForFaceAnchor`. The anchor keeps that node attached while the face remains tracked and removes it after `anchorLostGracePeriod`.

Use `ArFacePoseMapper` when you need to map a `FaceMeshResult` into the same
metric camera space without an `ArView`, for example in an image or model
preview.

## Permission handling

On Android and iOS, `ArView` calls `Permission.camera.request()` before creating
the camera controller. On macOS, the native camera view owns the system camera
prompt. Failures are mapped to `ArViewException`:

- `cameraPermissionDenied`
- `cameraPermissionPermanentlyDenied`
- `cameraPermissionRestricted`

Use `errorBuilder` to provide a custom permission UI. The default UI offers Retry and Open Settings actions. `openSettings()` is also passed to custom error builders.

The app still needs the platform declarations:

### iOS `Info.plist`

```xml
<key>NSCameraUsageDescription</key>
<string>This app uses the camera for face AR effects.</string>
```

### Android `AndroidManifest.xml`

```xml
<uses-permission android:name="android.permission.CAMERA" />
```

### macOS `Info.plist` and entitlements

```xml
<key>NSCameraUsageDescription</key>
<string>This app uses the camera for face AR effects.</string>
```

Add the camera entitlement to both macOS entitlement files:

```xml
<key>com.apple.security.device.camera</key>
<true/>
```

`flutter_scene` also needs Flutter GPU enabled by the host app:

### Android `AndroidManifest.xml`

```xml
<application>
  <meta-data
      android:name="io.flutter.embedding.android.EnableFlutterGPU"
      android:value="true" />
</application>
```

### iOS `Info.plist`

```xml
<key>FLTEnableFlutterGPU</key>
<true/>
```

### macOS `Info.plist`

```xml
<key>FLTEnableFlutterGPU</key>
<true/>
```

## Platform support

`ArView` supports Android, iOS, and macOS. The example targets Android 24+,
iOS 15+, and macOS 12+. Face tracking requires native MediaPipe FFI support;
web is intentionally not wired up yet.
