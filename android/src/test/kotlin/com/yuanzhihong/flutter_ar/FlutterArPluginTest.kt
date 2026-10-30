package com.yuanzhihong.flutter_ar

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/*
 * 本文件演示插件 Kotlin 实现的简单单元测试。
 *
 * 构建示例应用后，可以在 `example/android/` 目录运行 `./gradlew testDebugUnitTest`，
 * 也可以直接在支持 JUnit 的 IDE（例如 Android Studio）中运行。
 */

internal class FlutterArPluginTest {
    @Test
    fun onMethodCall_getPlatformVersion_returnsExpectedValue() {
        val plugin = FlutterArPlugin()

        val call = MethodCall("getPlatformVersion", null)
        val result = RecordingResult()
        plugin.onMethodCall(call, result)

        assertEquals("Android " + android.os.Build.VERSION.RELEASE, result.successValue)
    }

    @Test
    fun onMethodCall_unknownMethod_reportsNotImplemented() {
        val plugin = FlutterArPlugin()

        val call = MethodCall("unknownMethod", null)
        val result = RecordingResult()
        plugin.onMethodCall(call, result)

        assertTrue(result.notImplementedCalled)
    }

    private class RecordingResult : MethodChannel.Result {
        var successValue: Any? = null
        var notImplementedCalled = false

        override fun success(result: Any?) {
            successValue = result
        }

        override fun error(
            errorCode: String,
            errorMessage: String?,
            errorDetails: Any?
        ) = Unit

        override fun notImplemented() {
            notImplementedCalled = true
        }
    }
}
