import Flutter
import UIKit
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GMSServices.provideAPIKey("AIzaSyAXsy2RejZOhEsDPBhEGO0tyvHH-W_vjsE")
    // Register all Flutter plugins (including flutter_local_notifications) at launch
    // so UNUserNotificationCenter.delegate is set before the app finishes launching.
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
