#ifndef FLUTTER_PLUGIN_FLUTTER_AR_PLUGIN_H_
#define FLUTTER_PLUGIN_FLUTTER_AR_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace flutter_ar {

class FlutterArPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  FlutterArPlugin();

  virtual ~FlutterArPlugin();

  // Disallow copy and assign.
  FlutterArPlugin(const FlutterArPlugin&) = delete;
  FlutterArPlugin& operator=(const FlutterArPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace flutter_ar

#endif  // FLUTTER_PLUGIN_FLUTTER_AR_PLUGIN_H_
