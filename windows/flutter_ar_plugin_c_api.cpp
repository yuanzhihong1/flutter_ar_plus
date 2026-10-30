#include "include/flutter_ar/flutter_ar_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "flutter_ar_plugin.h"

void FlutterArPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  flutter_ar::FlutterArPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
