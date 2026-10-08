import CoreLocation
import Foundation
import Observation
import TodoPluginKit

/// Location permission and a one-off "where am I", for picking places and watching them.
@MainActor
@Observable
final class Locator: NSObject, CLLocationManagerDelegate {
    static let shared = Locator()

    private(set) var status: CLAuthorizationStatus
    /// Told to reschedule when permission changes, so place reminders start or stop.
    @ObservationIgnored weak var host: (any TodoHost)?
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var waiters: [CheckedContinuation<CLLocation?, Never>] = []

    var allowed: Bool { status == .authorizedWhenInUse || status == .authorizedAlways }

    private override init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    /// Place reminders need to know where you are, while the app is in use.
    func requestPermission() {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
    }

    func currentLocation() async -> CLLocation? {
        let s = manager.authorizationStatus
        guard s == .authorizedWhenInUse || s == .authorizedAlways || s == .notDetermined else { return nil }
        return await withCheckedContinuation { c in
            waiters.append(c)
            manager.requestLocation()
        }
    }

    private func finish(_ location: CLLocation?) {
        let waiting = waiters
        waiters = []
        waiting.forEach { $0.resume(returning: location) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        Task { @MainActor in
            status = s
            host?.rescheduleReminders()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        Task { @MainActor in finish(last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in finish(nil) }
    }
}
