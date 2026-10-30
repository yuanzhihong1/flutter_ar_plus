#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_ar.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_ar'
  s.version          = '0.0.1'
  s.summary          = 'Camera-driven face AR for Flutter.'
  s.description      = <<-DESC
Camera-driven face AR built with camera, MediaPipe Face Mesh, Flutter Scene,
and vector_math.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'flutter_ar/Sources/flutter_ar/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  s.resource_bundles = {
    'flutter_ar_privacy' => ['flutter_ar/Sources/flutter_ar/PrivacyInfo.xcprivacy']
  }
end
