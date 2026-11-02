#
# Podspec 语法请参阅 http://guides.cocoapods.org/syntax/podspec.html。
# 发布前运行 `pod lib lint flutter_ar_plus.podspec` 进行校验。
#
Pod::Spec.new do |s|
  s.name             = 'flutter_ar_plus'
  s.version          = '1.0.0'
  s.summary          = 'Flutter 实时人脸 AR 叠加库。'
  s.description      = <<-DESC
基于 camera、MediaPipe Face Mesh、Flutter Scene 和 vector_math
构建的 Flutter 实时人脸 AR 叠加库。
                       DESC
  s.homepage         = 'https://github.com/yuanzhihong1/flutter_ar_plus'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'flutter_ar_plus contributors' => 'https://github.com/yuanzhihong1/flutter_ar_plus/issues' }
  s.source           = { :path => '.' }
  s.source_files = 'flutter_ar_plus/Sources/flutter_ar_plus/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'

  # Flutter.framework 不包含 i386 架构。
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  s.resource_bundles = {
    'flutter_ar_plus_privacy' => ['flutter_ar_plus/Sources/flutter_ar_plus/PrivacyInfo.xcprivacy']
  }
end
