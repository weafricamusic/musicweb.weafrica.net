import Flutter
import FirebaseCore
import FirebaseMessaging
import google_mobile_ads
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
  private weak var _pluginRegistry: FlutterPluginRegistry?
  private var _nativeFactoryRegistered = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if FirebaseApp.app() == nil,
       Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
      FirebaseApp.configure()
    }

    UNUserNotificationCenter.current().delegate = self
    application.registerForRemoteNotifications()

    if FirebaseApp.app() != nil {
      Messaging.messaging().delegate = self
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    if FirebaseApp.app() != nil {
      Messaging.messaging().apnsToken = deviceToken
    }

    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    NSLog("APNs registration failed: \(error.localizedDescription)")
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    guard let token = fcmToken, !token.isEmpty else { return }
    NSLog("FCM registration token refreshed: \(token)")
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    _pluginRegistry = engineBridge.pluginRegistry

    if !_nativeFactoryRegistered {
      FLTGoogleMobileAdsPlugin.registerNativeAdFactory(
        engineBridge.pluginRegistry,
        factoryId: "weafricaNative",
        nativeAdFactory: WeAfricaNativeAdFactory()
      )
      _nativeFactoryRegistered = true
    }

    let channel = FlutterMethodChannel(name: "weafrica/country", binaryMessenger: engineBridge.applicationRegistrar.messenger())
    channel.setMethodCallHandler { call, result in
      if call.method == "getCountryCode" {
        let code = Locale.current.regionCode
        result(code)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  override func applicationWillTerminate(_ application: UIApplication) {
    if let registry = _pluginRegistry, _nativeFactoryRegistered {
      FLTGoogleMobileAdsPlugin.unregisterNativeAdFactory(registry, factoryId: "weafricaNative")
      _nativeFactoryRegistered = false
    }
    super.applicationWillTerminate(application)
  }
}
