package com.yuanzhihong.flutter_ar

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/*
 * This demonstrates a simple unit test of the Kotlin portion of this plugin's implementation.
 *
 * Once you have built the plugin's example app, you can run these tests from the command
 * line by running `./gradlew testDebugUnitTest` in the `example/android/` directory, or
 * you can run them directly from IDEs that support JUnit such as Android Studio.
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
