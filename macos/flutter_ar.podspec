#
# Podspec 语法请参阅 http://guides.cocoapods.org/syntax/podspec.html。
# 发布前运行 `pod lib lint flutter_ar.podspec` 进行校验。
#
Pod::Spec.new do |s|
  s.name             = 'flutter_ar'
  s.version          = '0.1.0'
  s.summary          = 'Flutter 实时人脸 AR 叠加库。'
  s.description      = <<-DESC
基于 Camera、MediaPipe Face Mesh 与 Flutter Scene 的实时人脸 AR 叠加库。
                       DESC
  s.homepage         = 'https://github.com/yuanzhihong/flutter_ar'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'flutter_ar contributors' => 'https://github.com/yuanzhihong/flutter_ar/issues' }

  s.source           = { :path => '.' }
  s.source_files = 'flutter_ar/Sources/flutter_ar/**/*'

  # 插件已经包含隐私清单，发布时会随资源包一起提供。
  s.resource_bundles = {'flutter_ar_privacy' => ['flutter_ar/Sources/flutter_ar/PrivacyInfo.xcprivacy']}

  s.dependency 'FlutterMacOS'

  s.platform = :osx, '12.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
