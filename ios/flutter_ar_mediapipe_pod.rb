# frozen_string_literal: true

require 'fileutils'
require 'json'

# Rewrites the mediapipe_face_mesh CocoaPod declaration so its bundled
# TensorFlowLiteC.xcframework is exposed to CocoaPods under a unique name.
#
# Some apps also depend on tflite_flutter, which installs its own
# TensorFlowLiteC.xcframework. CocoaPods rejects the two identical framework
# names before Xcode starts compiling. The runtime itself must stay bundled
# with mediapipe_face_mesh because its models use MediaPipe custom TFLite ops.
module FlutterArMediaPipePod
  module_function

  def install!(podfile_directory)
    source = find_mediapipe_source(podfile_directory)
    return unless source

    patched_path = prepare_pod(source, podfile_directory)
    patch_podfile_dsl(patched_path)
  end

  def find_mediapipe_source(podfile_directory)
    dependencies_file = File.expand_path('../.flutter-plugins-dependencies', podfile_directory)
    return unless File.exist?(dependencies_file)

    dependencies = JSON.parse(File.read(dependencies_file))
    plugin = dependencies.fetch('plugins', {}).fetch('ios', []).find do |entry|
      entry['name'] == 'mediapipe_face_mesh'
    end
    plugin && File.expand_path(plugin.fetch('path'))
  end

  def prepare_pod(source, podfile_directory)
    plugin_version = File.basename(source)
    build_root = File.expand_path(
      "Flutter/ephemeral/flutter_ar_pods/mediapipe_face_mesh-#{plugin_version}",
      podfile_directory,
    )
    FileUtils.mkdir_p(build_root)

    link_directory(File.join(source, 'ios', 'mediapipe_face_mesh'), File.join(build_root, 'mediapipe_face_mesh'))
    link_directory(File.join(source, 'src'), File.join(build_root, 'src'))
    link_file(File.join(source, 'LICENSE'), File.join(build_root, 'LICENSE'))
    link_directory(
      File.join(source, 'ios', 'mediapipe_face_mesh', 'Frameworks', 'TensorFlowLiteC.xcframework'),
      File.join(build_root, 'MediaPipeTensorFlowLiteC.xcframework'),
    )

    File.write(File.join(build_root, 'mediapipe_face_mesh.podspec'), <<~PODSPEC)
      Pod::Spec.new do |s|
        s.name             = 'mediapipe_face_mesh'
        s.version          = '3.2.2'
        s.summary          = 'MediaPipe Face Mesh for Flutter.'
        s.description      = 'Patched by flutter_ar to avoid a TFLite XCFramework name collision.'
        s.homepage         = 'https://github.com/cornpip/mediapipe_face_mesh.git'
        s.license          = { :file => 'LICENSE' }
        s.author           = { 'mediapipe_face_mesh contributors' => 'cornpip7777@gmail.com' }
        s.source           = { :path => '.' }
        s.source_files     = 'mediapipe_face_mesh/Sources/mediapipe_face_mesh/**/*', 'src/*.h'
        s.dependency 'Flutter'
        s.platform         = :ios, '13.0'
        s.pod_target_xcconfig = {
          'DEFINES_MODULE' => 'YES',
          'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
        }
        s.swift_version    = '5.0'
        s.frameworks       = 'CoreFoundation', 'Foundation'
        s.vendored_frameworks = 'MediaPipeTensorFlowLiteC.xcframework'
      end
    PODSPEC

    build_root
  end

  def link_directory(target, link)
    FileUtils.rm_f(link)
    File.symlink(target, link)
  end

  def link_file(target, link)
    link_directory(target, link)
  end

  def patch_podfile_dsl(patched_path)
    return if @podfile_dsl_patched

    Pod::Podfile::DSL.prepend(Module.new do
      define_method(:pod) do |name = nil, *requirements|
        if name == 'mediapipe_face_mesh' && requirements.any? { |item| item.is_a?(Hash) && item.key?(:path) }
          return super(name, path: patched_path)
        end

        super(name, *requirements)
      end
    end)
    @podfile_dsl_patched = true
  end
end
