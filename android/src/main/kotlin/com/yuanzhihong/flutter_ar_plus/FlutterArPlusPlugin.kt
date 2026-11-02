package com.yuanzhihong.flutter_ar_plus

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/** flutter_ar_plus 插件入口。 */
class FlutterArPlusPlugin :
    FlutterPlugin,
    MethodCallHandler {
    // 用于 Flutter 与 Android 原生层通信的方法通道。
    //
    // 该引用负责在插件附着到 Flutter Engine 时注册通道，
    // 并在插件从 Activity 分离时注销通道。
    private var channel: MethodChannel? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, CHANNEL_NAME).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result
    ) {
        when (call.method) {
            "getPlatformVersion" ->
                result.success("Android ${android.os.Build.VERSION.RELEASE}")
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    private companion object {
        const val CHANNEL_NAME = "flutter_ar_plus"
    }
}
