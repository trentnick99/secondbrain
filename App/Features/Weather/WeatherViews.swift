import SwiftUI
import SecondBrainCore

/// Home: the most serious current alert for the store. Tap for details.
struct WeatherAlertBanner: View {
    let alerts: [WeatherAlert]

    var body: some View {
        if let alert = alerts.first {
            NavigationLink {
                WeatherAlertDetailView(alert: alert)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(WeatherAlerts.title(alert, now: Date(), calendar: .current))
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(alerts.count > 1 ? "+\(alerts.count - 1) more · Tap for what to do" : "Tap for what to do")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.8))
                }
                .padding(14)
                .background(alert.severity == "Extreme" ? Theme.danger : Theme.warning,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("weatherAlertBanner")
        }
    }
}

struct WeatherAlertDetailView: View {
    let alert: WeatherAlert

    var body: some View {
        List {
            Section {
                Text(WeatherAlerts.title(alert, now: Date(), calendar: .current)).font(.title3.weight(.bold))
                if !alert.areaDescription.isEmpty {
                    Label(alert.areaDescription, systemImage: "mappin.and.ellipse").font(.subheadline)
                }
                Label(SafetyNotice.emergencyMessage, systemImage: "phone.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.danger)
            }
            if let instruction = alert.instruction {
                Section("What the National Weather Service says to do") { Text(instruction) }
            }
            Section {
                if let guide = CoachGuides.guide(id: "severe-weather") {
                    NavigationLink { GuideDetailView(guide: guide) } label: {
                        Label("Severe weather guide", systemImage: "shield.lefthalf.filled")
                    }
                }
                Link(destination: WeatherAlerts.moreInfoURL) { Label("Open weather.gov", systemImage: "safari") }
            } footer: {
                Text("Follow your store's emergency plan and the manager on duty. This isn't a replacement for Wireless Emergency Alerts.")
            }
            if let details = alert.details {
                Section("Details") { Text(details).font(.footnote) }
            }
            if let sender = alert.sender {
                Section {} footer: { Text("Issued by \(sender).") }
            }
        }
        .navigationTitle(alert.event)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Settings › Severe weather: turn alerts on and set the store's location.
struct WeatherSettingsView: View {
    @AppStorage(SettingsKey.weatherAlertsEnabled, store: AppGroup.defaults) private var enabled = false
    @AppStorage(SettingsKey.storeLocationName, store: AppGroup.defaults) private var locationName = ""
    @State private var zip = ""
    @State private var isLocating = false
    @State private var message: String?
    @State private var fetcher = LocationFetcher()
    private let service = WeatherAlertService.shared

    var body: some View {
        Form {
            Section {
                Toggle("Severe weather alerts", isOn: $enabled)
                    .accessibilityIdentifier("weatherAlertsToggle")
            } footer: {
                Text("Shows warnings and severe alerts for your store on Home, and notifies you during your shift. Only your store's approximate location is sent to the National Weather Service (weather.gov). This isn't a replacement for Wireless Emergency Alerts or your store's emergency plan.")
            }
            if enabled {
                Section {
                    LabeledContent("Store location", value: locationName.isEmpty ? "Not set" : locationName)
                    Button {
                        Task { await useCurrentLocation() }
                    } label: {
                        Label("Use my current location", systemImage: "location.fill")
                    }
                    .disabled(isLocating)
                    HStack {
                        TextField("Store ZIP code", text: $zip)
                            .keyboardType(.numberPad)
                            .textContentType(.postalCode)
                        Button("Set") { Task { await useZIP() } }
                            .disabled(zip.filter(\.isNumber).count != 5 || isLocating)
                    }
                    if isLocating { ProgressView() }
                    if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                    if !locationName.isEmpty {
                        Button("Remove store location", role: .destructive) {
                            WeatherAlertService.clearLocation()
                            locationName = ""
                        }
                    }
                } header: {
                    Text("Your store")
                } footer: {
                    Text("Use your current location while you're at the store, or enter its ZIP code.")
                }
                if !locationName.isEmpty {
                    Section {
                        if service.current.isEmpty {
                            Label(service.lastChecked == nil ? "Not checked yet" : "No warnings right now", systemImage: "checkmark.shield")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(service.current) { alert in
                                NavigationLink { WeatherAlertDetailView(alert: alert) } label: {
                                    Text(WeatherAlerts.title(alert, now: Date(), calendar: .current))
                                }
                            }
                        }
                        if let error = service.lastError { Text(error).font(.footnote).foregroundStyle(Theme.warning) }
                        Button("Check now") { Task { await service.refresh(force: true) } }
                    } header: {
                        Text("Current alerts")
                    }
                }
            }
        }
        .navigationTitle("Severe weather")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: enabled) { if enabled { await service.refresh() } }
    }

    private func useCurrentLocation() async {
        isLocating = true
        defer { isLocating = false }
        guard let coordinate = await fetcher.current() else {
            message = "Couldn't get your location. Check Location Services for Coach Spark in iOS Settings, or enter a ZIP code."
            return
        }
        WeatherAlertService.setLocation(coordinate, name: "Set from your location")
        locationName = "Set from your location"
        message = nil
        await service.refresh(force: true)
    }

    private func useZIP() async {
        let digits = String(zip.filter(\.isNumber).prefix(5))
        isLocating = true
        defer { isLocating = false }
        guard let coordinate = await ZIPLocator.coordinate(for: digits) else {
            message = "Couldn't find that ZIP code. Check it, or try again when you're online."
            return
        }
        WeatherAlertService.setLocation(coordinate, name: "ZIP \(digits)")
        locationName = "ZIP \(digits)"
        message = nil
        zip = ""
        await service.refresh(force: true)
    }
}
