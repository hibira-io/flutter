package io.hibira.push.flutter

import android.Manifest
import android.app.Activity
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import com.google.firebase.messaging.RemoteMessage
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import io.hibira.push.PushCallback
import io.hibira.push.PushCallbackError
import io.hibira.push.PushNotificationReceivedListener
import io.hibira.push.PushNotifications
import io.hibira.push.SubscriptionsChangedListener
import io.hibira.push.auth.TokenProvider
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Bridges `package:hibira_push` to the hibira-push-android SDK. */
class HibiraPushPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    PluginRegistry.NewIntentListener,
    PluginRegistry.RequestPermissionsResultListener {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private val main = Handler(Looper.getMainLooper())
    private var binding: ActivityPluginBinding? = null
    private var activity: Activity? = null
    private var started = false
    private var initialMessage: Map<String, Any?>? = null
    private var permissionResult: MethodChannel.Result? = null

    override fun onAttachedToEngine(flutterBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterBinding.applicationContext
        channel = MethodChannel(flutterBinding.binaryMessenger, "io.hibira/push")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(flutterBinding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "start" && call.method != "requestPermission" &&
            call.method != "getInitialMessage" && !started
        ) {
            result.error("not-started", "call start() first", null)
            return
        }
        try {
            when (call.method) {
                "start" -> {
                    call.argument<String>("endpoint")?.let { PushNotifications.setEndpoint(context, it) }
                    PushNotifications.start(context, call.argument<String>("instanceId")!!)
                    PushNotifications.setOnDeviceInterestsChangedListener(object : SubscriptionsChangedListener {
                        override fun onSubscriptionsChanged(interests: Set<String>) {
                            main.post { channel.invokeMethod("onInterestsChanged", interests.toList()) }
                        }
                    })
                    started = true
                    listenForMessages()
                    result.success(null)
                }
                "requestPermission" -> requestPermission(result)
                "addDeviceInterest" -> {
                    PushNotifications.addDeviceInterest(call.argument<String>("interest")!!)
                    result.success(null)
                }
                "removeDeviceInterest" -> {
                    PushNotifications.removeDeviceInterest(call.argument<String>("interest")!!)
                    result.success(null)
                }
                "setDeviceInterests" -> {
                    PushNotifications.setDeviceInterests(call.argument<List<String>>("interests")!!.toSet())
                    result.success(null)
                }
                "clearDeviceInterests" -> {
                    PushNotifications.clearDeviceInterests()
                    result.success(null)
                }
                "getDeviceInterests" -> result.success(PushNotifications.getDeviceInterests().toList())
                "setUserId" -> setUserId(call.argument<String>("userId")!!, result)
                "clearAllState" -> {
                    PushNotifications.clearAllState()
                    result.success(null)
                }
                "stop" -> {
                    PushNotifications.stop()
                    started = false
                    result.success(null)
                }
                "getInitialMessage" -> {
                    result.success(initialMessage)
                    initialMessage = null
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error(e.javaClass.simpleName, e.message, null)
        }
    }

    private fun setUserId(userId: String, result: MethodChannel.Result) {
        PushNotifications.setUserId(userId, DartTokenProvider(), object : PushCallback<Void, PushCallbackError> {
            override fun onSuccess(vararg values: Void) {
                main.post { result.success(null) }
            }

            override fun onFailure(error: PushCallbackError) {
                main.post { result.error("set-user-id-failed", error.message, error.cause?.message) }
            }
        })
    }

    /** Asks the Dart HibiraPushTokenProvider for a token. The SDK calls it on a background thread. */
    private inner class DartTokenProvider : TokenProvider {
        override fun fetchToken(userId: String): String {
            check(Looper.myLooper() != Looper.getMainLooper()) { "fetchToken must not run on the main thread" }
            val latch = CountDownLatch(1)
            var token: String? = null
            var failure: String? = null
            main.post {
                channel.invokeMethod("fetchToken", mapOf("userId" to userId), object : MethodChannel.Result {
                    override fun success(value: Any?) {
                        token = value as? String
                        latch.countDown()
                    }

                    override fun error(code: String, message: String?, details: Any?) {
                        failure = message ?: code
                        latch.countDown()
                    }

                    override fun notImplemented() {
                        failure = "no Dart token provider"
                        latch.countDown()
                    }
                })
            }
            if (!latch.await(60, TimeUnit.SECONDS)) throw RuntimeException("token provider timed out")
            failure?.let { throw RuntimeException(it) }
            return token ?: throw RuntimeException("token provider returned no token")
        }
    }

    private fun requestPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 33 ||
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(notificationsEnabled())
            return
        }
        val activity = activity
        if (activity == null) {
            result.error("no-activity", "requestPermission needs a foreground activity", null)
            return
        }
        if (permissionResult != null) {
            result.error("in-progress", "a permission request is already running", null)
            return
        }
        permissionResult = result
        activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), PERMISSION_REQUEST)
    }

    private fun notificationsEnabled(): Boolean =
        context.getSystemService(NotificationManager::class.java).areNotificationsEnabled()

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        val result = permissionResult ?: return true
        permissionResult = null
        result.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
        return true
    }

    private fun listenForMessages() {
        val activity = activity ?: return
        if (!started) return
        PushNotifications.setOnMessageReceivedListenerForVisibleActivity(
            activity,
            object : PushNotificationReceivedListener {
                override fun onMessageReceived(remoteMessage: RemoteMessage) {
                    val message = mapOf(
                        "title" to remoteMessage.notification?.title,
                        "body" to remoteMessage.notification?.body,
                        "data" to remoteMessage.data.filterKeys { it != "pusher" },
                    )
                    main.post { channel.invokeMethod("onMessage", message) }
                }
            },
        )
    }

    /** A tapped notification opens the launcher activity with its data as intent extras. */
    private fun messageFrom(intent: Intent?): Map<String, Any?>? {
        val extras: Bundle = intent?.extras ?: return null
        if (!extras.containsKey("google.message_id") && !extras.containsKey("pusher")) return null
        val data = HashMap<String, Any?>()
        for (key in extras.keySet()) {
            if (key == "pusher" || key.startsWith("google.") || key.startsWith("gcm.") ||
                key == "from" || key == "collapse_key"
            ) {
                continue
            }
            @Suppress("DEPRECATION")
            data[key] = extras.get(key)?.toString()
        }
        return mapOf("title" to null, "body" to null, "data" to data)
    }

    override fun onNewIntent(intent: Intent): Boolean {
        val message = messageFrom(intent) ?: return false
        channel.invokeMethod("onMessageOpenedApp", message)
        return false
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        this.binding = binding
        activity = binding.activity
        binding.addOnNewIntentListener(this)
        binding.addRequestPermissionsResultListener(this)
        if (initialMessage == null) initialMessage = messageFrom(binding.activity.intent)
        listenForMessages()
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        this.binding = binding
        activity = binding.activity
        binding.addOnNewIntentListener(this)
        binding.addRequestPermissionsResultListener(this)
        listenForMessages()
    }

    override fun onDetachedFromActivity() {
        binding?.removeOnNewIntentListener(this)
        binding?.removeRequestPermissionsResultListener(this)
        binding = null
        activity = null
    }

    companion object {
        private const val PERMISSION_REQUEST = 0x4869
    }
}
