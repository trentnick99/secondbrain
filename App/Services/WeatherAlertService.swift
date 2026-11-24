import CoreLocation
import Foundation
import Observation
import UserNotifications
import SecondBrainCore

/// Severe weather alerts from the National Weather Service for the store's location. Off until the
/// person turns it on and sets a location; only the rounded coordinates are sent to weather.gov.
/// Not a replacement for Wireless Emergency Alerts or the store's emergency plan.
@MainActor
@Observable
final class WeatherAlertService {
    static let shared = WeatherAlertService()

    private(set) var alerts: [WeatherAlert] = []
    private(set) var lastChecked: Date?
    private(set) var lastError: String?

    /// Warnings and severe alerts that haven't ended.
    var current: [WeatherAlert] { WeatherAlerts.current(alerts, now: Date()) }

    static var location: CLLocationCoordinate2D? {
        let defaults = AppGroup.defaults
        guard defaults.object(forKey: SettingsKey.storeLatitude) != nil,
              defaults.object(forKey: SettingsKey.storeLongitude) != nil else { return nil }
        return CLLocationCoordinate2D(latitude: defaults.double(forKey: SettingsKey.storeLatitude),
                                      longitude: defaults.double(forKey: SettingsKey.storeLongitude))
    }

    static var isEnabled: Bool {
        AppGroup.defaults.bool(forKey: SettingsKey.weatherAlertsEnabled) && location != nil
    }

    static func setLocation(_ coordinate: CLLocationCoordinate2D, name: String) {
        let defaults = AppGroup.defaults
        defaults.set(coordinate.latitude, forKey: SettingsKey.storeLatitude)
        defaults.set(coordinate.longitude, forKey: SettingsKey.storeLongitude)
        defaults.set(name, forKey: SettingsKey.storeLocationName)
        shared.lastChecked = nil
    }

    static func clearLocation() {
        let defaults = AppGroup.defaults
        [SettingsKey.storeLatitude, SettingsKey.storeLongitude, SettingsKey.storeLocationName, SettingsKey.weatherCache]
            .forEach { defaults.removeObject(forKey: $0) }
        shared.alerts = []
        shared.lastChecked = nil
    }

    private init() {
        if PersistenceController.isUITesting {
            if ProcessInfo.processInfo.arguments.contains("-sampleWeather") { alerts = [Self.sample] }
            return
        }
        if let data = AppGroup.defaults.data(forKey: SettingsKey.weatherCache),
           let cached = try? JSONDecoder().decode([WeatherAlert].self, from: data) {
            alerts = cached
        }
    }

    /// Checks weather.gov at most every 10 minutes unless forced. Offline, it keeps what it had.
    func refresh(force: Bool = false) async {
        guard !PersistenceController.isUITesting else { return }
        guard Self.isEnabled, let location = Self.location,
              let url = WeatherAlerts.url(latitude: location.latitude, longitude: location.longitude) else {
            alerts = []
            return
        }
        if !force, let lastChecked, Date().timeIntervalSince(lastChecked) < 600 { return }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(WeatherAlerts.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/geo+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                lastError = "Weather alerts are unavailable right now."
                return
            }
            alerts = try WeatherAlerts.parse(data)
            lastChecked = Date()
            lastError = nil
            if let encoded = try? JSONEncoder().encode(alerts) {
                AppGroup.defaults.set(encoded, forKey: SettingsKey.weatherCache)
            }
        } catch {
            lastError = "Couldn't check weather alerts. You may be offline."
        }
    }

    /// Background check: notifies once per new warning or severe alert, from an hour before the shift to its end.
    func checkAndNotify(now: Date = Date()) async {
        await refresh(force: true)
        guard let window = AppSettings.shiftWindow(on: now),
              now >= window.start.addingTimeInterval(-3600), now <= window.end else { return }
        let defaults = AppGroup.defaults
        var notified = (defaults.string(forKey: SettingsKey.weatherNotified) ?? "").split(separator: "\n").map(String.init)
        for alert in current where !notified.contains(alert.id) {
            let content = UNMutableNotificationContent()
            content.title = WeatherAlerts.title(alert, now: now, calendar: .current)
            content.body = (alert.areaDescription.isEmpty ? "" : alert.areaDescription + ". ")
                + "Follow your store's emergency plan and the manager on duty."
            content.sound = .default
            let request = UNNotificationRequest(identifier: "weather-\(alert.id)", content: content, trigger: nil)
            try? await UNUserNotificationCenter.current().add(request)
            notified.append(alert.id)
        }
        defaults.set(notified.suffix(50).joined(separator: "\n"), forKey: SettingsKey.weatherNotified)
    }

    /// Fictional alert for screenshots and UI tests.
    static let sample = WeatherAlert(
        id: "sample-tornado", event: "Tornado Warning", headline: "Tornado Warning (sample)",
        severity: "Extreme", areaDescription: "Sample County",
        instruction: "This is a fictional sample alert. In a real warning, follow your store's emergency plan and move people to the designated shelter areas.",
        sender: "National Weather Service (sample)", onset: Date(), ends: Date().addingTimeInterval(45 * 60))
}

/// Finds the phone's location once, for setting the store location. Nothing is tracked.
@MainActor
final class LocationFetcher: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?

    func current() async -> CLLocationCoordinate2D? {
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            switch manager.authorizationStatus {
            case .notDetermined: manager.requestWhenInUseAuthorization()
            case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
            default: finish(nil)
            }
        }
    }

    private func finish(_ coordinate: CLLocationCoordinate2D?) {
        continuation?.resume(returning: coordinate)
        continuation = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard self.continuation != nil else { return }
            switch status {
            case .authorizedWhenInUse, .authorizedAlways: self.manager.requestLocation()
            case .denied, .restricted: self.finish(nil)
            default: break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coordinate = locations.last?.coordinate
        Task { @MainActor in self.finish(coordinate) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }
}

enum ZIPLocator {
    /// The approximate center of a US ZIP code, using Apple's geocoder.
    static func coordinate(for zip: String) async -> CLLocationCoordinate2D? {
        let placemarks = try? await CLGeocoder().geocodeAddressString("\(zip), United States")
        return placemarks?.first?.location?.coordinate
    }
}
