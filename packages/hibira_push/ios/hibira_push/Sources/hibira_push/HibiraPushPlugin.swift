import Flutter
import HibiraPush
import UIKit
import UserNotifications

/// Bridges `package:hibira_push` to the hibira-push-ios SDK.
public class HibiraPushPlugin: NSObject, FlutterPlugin, InterestsChangedDelegate {
    private let channel: FlutterMethodChannel
    private var push: PushNotifications?
    private var initialMessage: [String: Any?]?

    init(channel: FlutterMethodChannel) {
        self.channel = channel
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "io.hibira/push", binaryMessenger: registrar.messenger())
        let instance = HibiraPushPlugin(channel: channel)
        registrar.addMethodCallDelegate(instance, channel: channel)
        registrar.addApplicationDelegate(instance)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        if call.method == "start" {
            if let endpoint = args["endpoint"] as? String {
                PushNotifications.shared.setEndpoint(endpoint)
            }
            let push = PushNotifications(instanceId: args["instanceId"] as! String)
            push.delegate = self
            push.start()
            self.push = push
            // Registers again with APNs when the user already allowed
            // notifications; the token arrives in didRegisterForRemoteNotifications.
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
                    DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
                }
            }
            result(nil)
            return
        }
        if call.method == "requestPermission" {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                DispatchQueue.main.async {
                    if let error = error {
                        result(FlutterError(code: "permission-failed", message: error.localizedDescription, details: nil))
                        return
                    }
                    if granted { UIApplication.shared.registerForRemoteNotifications() }
                    result(granted)
                }
            }
            return
        }
        if call.method == "getInitialMessage" {
            result(initialMessage)
            initialMessage = nil
            return
        }
        guard let push = push else {
            result(FlutterError(code: "not-started", message: "call start() first", details: nil))
            return
        }
        do {
            switch call.method {
            case "addDeviceInterest":
                try push.addDeviceInterest(interest: args["interest"] as! String)
                result(nil)
            case "removeDeviceInterest":
                try push.removeDeviceInterest(interest: args["interest"] as! String)
                result(nil)
            case "setDeviceInterests":
                try push.setDeviceInterests(interests: args["interests"] as! [String])
                result(nil)
            case "clearDeviceInterests":
                try push.clearDeviceInterests()
                result(nil)
            case "getDeviceInterests":
                result(push.getDeviceInterests() ?? [])
            case "setUserId":
                push.setUserId(args["userId"] as! String, tokenProvider: DartTokenProvider(channel: channel)) { error in
                    DispatchQueue.main.async {
                        if let error = error {
                            result(FlutterError(code: "set-user-id-failed", message: error.localizedDescription, details: nil))
                        } else {
                            result(nil)
                        }
                    }
                }
            case "clearAllState":
                push.clearAllState { DispatchQueue.main.async { result(nil) } }
            case "stop":
                push.stop { DispatchQueue.main.async { result(nil) } }
                self.push = nil
            default:
                result(FlutterMethodNotImplemented)
            }
        } catch {
            result(FlutterError(code: "\(type(of: error))", message: error.localizedDescription, details: nil))
        }
    }

    public func interestsSetOnDeviceDidChange(interests: [String]) {
        DispatchQueue.main.async { self.channel.invokeMethod("onInterestsChanged", arguments: interests) }
    }

    // MARK: - UIApplicationDelegate

    public func application(_ application: UIApplication,
                            didFinishLaunchingWithOptions launchOptions: [AnyHashable: Any] = [:]) -> Bool {
        if let userInfo = launchOptions[UIApplication.LaunchOptionsKey.remoteNotification] as? [AnyHashable: Any] {
            initialMessage = Self.message(from: userInfo)
        }
        return true
    }

    public func application(_ application: UIApplication,
                            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushNotifications.shared.registerDeviceToken(deviceToken)
    }

    public func application(_ application: UIApplication,
                            didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                            fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) -> Bool {
        PushNotifications.shared.handleNotification(userInfo: userInfo)
        completionHandler(.noData)
        return true
    }

    // MARK: - UNUserNotificationCenterDelegate (forwarded by FlutterAppDelegate)

    public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                       willPresent notification: UNNotification,
                                       withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        guard Self.isHibira(userInfo) else { return }
        if PushNotifications.shared.handleNotification(userInfo: userInfo) == .ShouldProcess {
            channel.invokeMethod("onMessage", arguments: Self.message(from: userInfo))
        }
        // Like FCM on Android: no system banner in the foreground, the app decides.
        completionHandler([])
    }

    public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                       didReceive response: UNNotificationResponse,
                                       withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        guard Self.isHibira(userInfo) else { return }
        PushNotifications.shared.handleNotification(userInfo: userInfo)
        channel.invokeMethod("onMessageOpenedApp", arguments: Self.message(from: userInfo))
        completionHandler()
    }

    /// Notifications from Hibira Push carry a `data.pusher` block; leave the
    /// others to the plugins they belong to.
    private static func isHibira(_ userInfo: [AnyHashable: Any]) -> Bool {
        (userInfo["data"] as? [String: Any])?["pusher"] != nil
    }

    private static func message(from userInfo: [AnyHashable: Any]) -> [String: Any?] {
        var title: String?
        var body: String?
        let aps = userInfo["aps"] as? [String: Any]
        if let alert = aps?["alert"] as? [String: Any] {
            title = alert["title"] as? String
            body = alert["body"] as? String
        } else if let alert = aps?["alert"] as? String {
            body = alert
        }
        var data: [String: Any] = [:]
        for (key, value) in userInfo {
            guard let key = key as? String, key != "aps" else { continue }
            if key == "data", var inner = value as? [String: Any] {
                inner.removeValue(forKey: "pusher")
                data.merge(inner) { _, new in new }
            } else {
                data[key] = value
            }
        }
        return ["title": title, "body": body, "data": data]
    }
}

/// Asks the Dart HibiraPushTokenProvider for a token.
private final class DartTokenProvider: NSObject, TokenProvider {
    private let channel: FlutterMethodChannel

    init(channel: FlutterMethodChannel) {
        self.channel = channel
    }

    func fetchToken(userId: String, completionHandler completion: @escaping (String, Error?) -> Void) throws {
        DispatchQueue.main.async {
            self.channel.invokeMethod("fetchToken", arguments: ["userId": userId]) { value in
                if let token = value as? String {
                    completion(token, nil)
                } else {
                    let message = (value as? FlutterError)?.message ?? "token provider returned no token"
                    completion("", NSError(domain: "io.hibira.push.flutter", code: 1,
                                           userInfo: [NSLocalizedDescriptionKey: message]))
                }
            }
        }
    }
}
