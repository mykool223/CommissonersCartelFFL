import Foundation
import Observation
import OSLog
import UIKit
import UserNotifications
import CartelCore

/// Owns the device's relationship with APNs: asking permission, collecting the
/// token, handing it to Supabase, and reacting when a notification is tapped.
///
/// Registration is deliberately tied to *being signed in*, not to launch. A
/// device token is stored against a user id, so registering before sign-in has
/// nowhere to put it.
@Observable
@MainActor
final class PushRegistrar: NSObject {
    /// Where a tapped notification should take the reader. Read by RootView.
    private(set) var pendingDestination: String?

    /// Mirrors the system setting, so Settings can explain *why* the toggles
    /// are doing nothing when permission was denied.
    private(set) var authorization: UNAuthorizationStatus = .notDetermined

    private var deviceToken: String?
    private var push: (any PushRepository)?
    private let log = Logger(subsystem: "com.commissionerscartel.app", category: "push")

    /// UNUserNotificationCenter holds its delegate weakly, so this must be
    /// owned here or taps stop routing after the first deallocation.
    ///
    /// Ignored by @Observable: it is plumbing, and the macro cannot synthesise
    /// tracking for a lazy property.
    @ObservationIgnored
    private lazy var notificationDelegate = PushNotificationDelegate { [weak self] destination in
        Task { @MainActor in self?.pendingDestination = destination }
    }

    /// Called once the app knows who the member is.
    func configure(push: any PushRepository) {
        self.push = push
        // A token that arrived before sign-in completed is still good.
        if let deviceToken {
            Task { await store(token: deviceToken) }
        }
    }

    func refreshAuthorizationStatus() async {
        authorization = await UNUserNotificationCenter.current().notificationSettings()
            .authorizationStatus
    }

    /// Asks for permission if it has not been asked before, then registers.
    ///
    /// Returns whether notifications are usable. A member who said no keeps
    /// saying no until they change it in the system Settings app — iOS only
    /// ever shows the prompt once.
    @discardableResult
    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = notificationDelegate

        let granted: Bool
        do {
            granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            log.error("Notification authorization failed: \(error.localizedDescription)")
            return false
        }

        await refreshAuthorizationStatus()
        if granted {
            UIApplication.shared.registerForRemoteNotifications()
        }
        return granted
    }

    /// Registers again without prompting, for members who already said yes.
    func registerIfAlreadyAuthorized() async {
        await refreshAuthorizationStatus()
        guard authorization == .authorized || authorization == .provisional else { return }
        UNUserNotificationCenter.current().delegate = notificationDelegate
        UIApplication.shared.registerForRemoteNotifications()
    }

    // MARK: - Token plumbing

    func didRegister(deviceToken data: Data) {
        let token = data.map { String(format: "%02x", $0) }.joined()
        self.deviceToken = token
        Task { await store(token: token) }
    }

    func didFailToRegister(error: any Error) {
        // Expected on the simulator before iOS 16 and whenever the device has
        // no network. Not worth surfacing to the member.
        log.error("APNs registration failed: \(error.localizedDescription)")
    }

    /// Drops this device server-side, so it stops receiving.
    func unregister() async {
        guard let push, let deviceToken else { return }
        do {
            try await push.unregisterDevice(token: deviceToken)
        } catch {
            log.error("Could not unregister device: \(error.localizedDescription)")
        }
    }

    private func store(token: String) async {
        guard let push else { return }
        do {
            try await push.registerDevice(token: token, environment: .current)
            log.notice("Registered for push (\(PushEnvironment.current.rawValue))")
        } catch CartelError.notAuthorized {
            // Signed out. configure() will retry once a session exists.
        } catch {
            log.error("Could not register device token: \(error.localizedDescription)")
        }
    }

    func clearPendingDestination() {
        pendingDestination = nil
    }
}

/// The delegate is a separate object because `UNUserNotificationCenterDelegate`
/// is called from a nonisolated context, and Swift 6 will not let a
/// `@MainActor` type adopt it — the notification objects themselves are not
/// Sendable, so they cannot cross onto the main actor.
///
/// Only the destination string, which is Sendable, makes the trip.
private final class PushNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    private let onTap: @Sendable (String?) -> Void

    init(onTap: @escaping @Sendable (String?) -> Void) {
        self.onTap = onTap
    }

    /// Show the banner even while the app is open — otherwise a member reading
    /// News never learns that someone replied in the league thread.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        onTap(response.notification.request.content.userInfo["destination"] as? String)
    }
}

/// UIKit still owns remote-notification registration; there is no SwiftUI
/// equivalent, so the app keeps a delegate purely to forward these two calls.
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Set by the App struct as soon as the scene exists.
    @MainActor static var registrar: PushRegistrar?

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        MainActor.assumeIsolated {
            AppDelegate.registrar?.didRegister(deviceToken: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: any Error
    ) {
        MainActor.assumeIsolated {
            AppDelegate.registrar?.didFailToRegister(error: error)
        }
    }
}
