import SwiftUI
import MapKit
import UserNotifications
import Combine
import WebKit // Required for the Radar WebView

// MARK: - 1. WebView Helper
struct RadarWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.backgroundColor = .black
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        let request = URLRequest(url: url)
        uiView.load(request)
    }
}

// MARK: - 2. Radar Modal View
struct RadarView: View {
    @Environment(\.dismiss) var dismiss
    let radarURL: URL

    var body: some View {
        NavigationView {
            RadarWebView(url: radarURL)
                .edgesIgnoringSafeArea(.bottom)
                .navigationTitle("Weather Radar")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.title3)
                        }
                    }
                }
        }
    }
}

// MARK: - 3. Data Models (NWS API)
struct NWSPointsResponse: Codable {
    let properties: PointsProperties
}
struct PointsProperties: Codable {
    let forecast: String
    let relativeLocation: RelativeLocation
    let forecastHourly: String
}
struct RelativeLocation: Codable {
    let properties: LocationProperties
}
struct LocationProperties: Codable {
    let city: String
    let state: String
}

struct NWSForecastResponse: Codable {
    let properties: ForecastProperties
}
struct ForecastProperties: Codable {
    let periods: [Period]
}

struct NWSForecastHourlyResponse: Codable {
    let properties: ForecastPropertiesHourly
}
struct ForecastPropertiesHourly: Codable {
    let periods: [HourlyPeriod]
}

struct Period: Codable, Identifiable {
    let id = UUID()
    let name: String
    let startTime: String
    let temperature: Int
    let shortForecast: String
    let detailedForecast: String
    let isDaytime: Bool
    let probabilityOfPrecipitation: PrecipChance?
    
    enum CodingKeys: String, CodingKey {
        case name, startTime, temperature, shortForecast, detailedForecast, isDaytime, probabilityOfPrecipitation
    }
    
    var formattedDateString: String {
        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: startTime) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "M/d"
            return "(\(displayFormatter.string(from: date)))"
        }
        return ""
    }
}

struct HourlyPeriod: Codable, Identifiable {
    let id = UUID()
    let startTime: String
    let temperature: Int
    let shortForecast: String
    let windSpeed: String
    let windDirection: String
    let probabilityOfPrecipitation: PrecipChance?
    
    enum CodingKeys: String, CodingKey {
        case startTime, temperature, shortForecast, windSpeed, windDirection, probabilityOfPrecipitation
    }
    
    var formattedTimeString: String {
        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: startTime) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "h a"
            return displayFormatter.string(from: date)
        }
        return "N/A"
    }
}

struct PrecipChance: Codable {
    let value: Int?
}

// MARK: - 4. View Model
class WeatherViewModel: NSObject, ObservableObject {
    @Published var periods: [Period] = []
    @Published var hourlyPeriods: [HourlyPeriod] = []
    @Published var locationName: String = "Locating..."
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    @Published var currentLat: Double
    @Published var currentLon: Double
    @Published var alertFrost: Bool
    @Published var alertPrecip: Bool
    
    private let userAgent = "(farmerforecastapp.com, contact@farmerforecast.com)"
    
    override init() {
        let savedLat = UserDefaults.standard.double(forKey: "savedLat")
        let savedLon = UserDefaults.standard.double(forKey: "savedLon")
        
        if savedLat == 0.0 {
            self.currentLat = 44.088
            self.currentLon = -121.035
        } else {
            self.currentLat = savedLat
            self.currentLon = savedLon
        }
        
        self.alertFrost = UserDefaults.standard.bool(forKey: "alertFrost")
        self.alertPrecip = UserDefaults.standard.bool(forKey: "alertPrecip")
        
        super.init()
        loadData()
    }
    
    func loadData() {
        fetchWeather(lat: currentLat, lon: currentLon)
    }
    
    func updateLocation(lat: Double, lon: Double) {
        let roundedLat = (lat * 10000).rounded() / 10000
        let roundedLon = (lon * 10000).rounded() / 10000
        self.currentLat = roundedLat
        self.currentLon = roundedLon
        UserDefaults.standard.set(roundedLat, forKey: "savedLat")
        UserDefaults.standard.set(roundedLon, forKey: "savedLon")
        fetchWeather(lat: roundedLat, lon: roundedLon)
    }
    
    func updateSettings(frost: Bool, precip: Bool) {
        self.alertFrost = frost
        self.alertPrecip = precip
        UserDefaults.standard.set(frost, forKey: "alertFrost")
        UserDefaults.standard.set(precip, forKey: "alertPrecip")
        checkAlerts()
    }

    private func fetchWeather(lat: Double, lon: Double) {
        isLoading = true
        errorMessage = nil
        let path = "points/\(lat),\(lon)"
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.weather.gov"
        components.path = "/\(path)"

        guard let url = components.url else { return }
        
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                if let error = error { self.fail(error.localizedDescription); return }
                guard let data = data else { return }
                do {
                    let points = try JSONDecoder().decode(NWSPointsResponse.self, from: data)
                    let props = points.properties
                    var newLocationName = "\(props.relativeLocation.properties.city), \(props.relativeLocation.properties.state)"
                    if newLocationName == "Pronghorn, OR" { newLocationName = "Alfalfa, OR" }
                    self.locationName = newLocationName
                    
                    self.fetchForecast(from: props.forecast)
                    self.fetchHourlyForecast(from: props.forecastHourly)
                } catch {
                    self.fail("Location unavailable here.")
                }
            }
        }.resume()
    }
    
    private func fetchForecast(from urlString: String) {
        guard let url = URL(string: urlString) else { return }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                self.isLoading = false
                guard let data = data else { return }
                do {
                    let forecast = try JSONDecoder().decode(NWSForecastResponse.self, from: data)
                    self.periods = forecast.properties.periods
                    self.checkAlerts()
                } catch { self.fail("Forecast unavailable.") }
            }
        }.resume()
    }
    
    private func fetchHourlyForecast(from urlString: String) {
        guard let url = URL(string: urlString) else { return }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                guard let data = data else { return }
                do {
                    let forecast = try JSONDecoder().decode(NWSForecastHourlyResponse.self, from: data)
                    self.hourlyPeriods = Array(forecast.properties.periods.prefix(12))
                } catch { print("Hourly fetch failed") }
            }
        }.resume()
    }
    
    private func fail(_ msg: String) {
        isLoading = false
        errorMessage = msg
    }
    
    private func checkAlerts() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        var alerts: [String] = []
        for period in periods.prefix(2) {
            if alertFrost && period.temperature <= 32 { alerts.append("❄️ Frost likely \(period.name.lowercased())") }
            if alertPrecip, let chance = period.probabilityOfPrecipitation?.value, chance > 20 { alerts.append("🌧️ Rain likely \(period.name.lowercased())") }
        }
        if !alerts.isEmpty { scheduleNotification(body: alerts.joined(separator: "\n")) }
    }
    
    private func scheduleNotification(body: String) {
        let content = UNMutableNotificationContent()
        content.title = "Weather Alert"
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func getAlertDetails() -> (frost: String, precip: String) {
        var frostTime = "No frost expected soon."
        var precipTime = "No precipitation expected soon."
        for period in periods { if period.temperature <= 32 { frostTime = "Next frost: \(period.name)."; break } }
        for period in periods { if let chance = period.probabilityOfPrecipitation?.value, chance > 20 { precipTime = "Next precip: \(period.name)."; break } }
        return (frostTime, precipTime)
    }

    func getHourlyForecastSummary() -> String {
        guard !hourlyPeriods.isEmpty else { return "Hourly data unavailable." }
        var summary = "--- Next 6 Hours ---\n"
        for period in hourlyPeriods.prefix(6) { summary += "• \(period.formattedTimeString): \(period.temperature)° | \(period.shortForecast)\n" }
        return summary
    }
}

// MARK: - 5. Settings View
struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: WeatherViewModel
    @Binding var isDarkMode: Bool

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Notifications")) {
                    Toggle("❄️ Frost Alerts", isOn: $viewModel.alertFrost)
                    Toggle("💧 Precipitation Alerts", isOn: $viewModel.alertPrecip)
                }
                .onChange(of: viewModel.alertFrost) { newValue in
                    viewModel.updateSettings(frost: newValue, precip: viewModel.alertPrecip)
                    if newValue { requestPermissions() }
                }
                .onChange(of: viewModel.alertPrecip) { newValue in
                    viewModel.updateSettings(frost: viewModel.alertFrost, precip: newValue)
                    if newValue { requestPermissions() }
                }

                Section(header: Text("Appearance")) {
                    Toggle("Dark Mode", isOn: $isDarkMode)
                }
            }
            .navigationTitle("Settings")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
    func requestPermissions() { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in } }
}

// MARK: - 6. Main Content View
struct ContentView: View {
    @StateObject private var viewModel = WeatherViewModel()
    @State private var showLocationPicker = false
    @State private var showSettings = false
    @State private var showRadar = false
    @State private var showForecastAlert = false
    
    @AppStorage("isDarkMode") private var isDarkMode = true
    
    private let radarURL = URL(string: "https://radar.weather.gov/?settings=v1_eyJhZ2VuZGEiOnsiaWQiOm51bGwsImNlbnRlciI6Wy0xMjEuMzksNDMuNDE0XSwibG9jYXRpb24iOm51bGwsInpvb20iOjcuMzE1OTAzMTk3OTYzMjkyfSwiYW5pbWF0aW5nIjpmYWxzZSwiYmFzZSI6InN0YW5kYXJkIiwiYXJ0Y2MiOmZhbHNlLCJjb3VudHkiOmZhbHNlLCJjd2EiOmZhbHNlLCJyZmMiOmZhbHNlLCJzdGF0ZSI6ZmFsc2UsIm1lbnUiOnRydWUsInNob3J0RnVzZWRPbmx5IjpmYWxzZSwib3BhY2l0eSI6eyJhbGVydHMiOjAuOCwibG9jYWwiOjAuNiwibG9jYWxTdGF0aW9ucyI6MC44LCJuYXRpb25hbCI6MC42fX0%3D")!

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header: Location and Weather Buttons (Matched Heights)
                HStack(spacing: 12) {
                    // Location Button
                    Button(action: { showLocationPicker = true }) {
                        HStack {
                            Image(systemName: "mappin.and.ellipse")
                            Text(viewModel.locationName)
                                .font(.headline)
                                .bold()
                                .lineLimit(1)
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(12)
                    }
                    
                    // Current Weather Button (Detailed Report Trigger)
                    if let current = viewModel.hourlyPeriods.first {
                        Button(action: { showForecastAlert = true }) {
                            HStack(spacing: 12) {
                                Image(systemName: getIcon(for: current.shortForecast))
                                    .font(.title2)
                                    .foregroundColor(getColor(temp: current.temperature))
                                
                                VStack(alignment: .trailing, spacing: 0) {
                                    Text("\(current.temperature)°")
                                        .font(.system(size: 28, weight: .light))
                                        .foregroundColor(getColor(temp: current.temperature))
                                    Text("\(current.windDirection) \(current.windSpeed)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.horizontal, 12)
                            .frame(maxHeight: .infinity)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(height: 60) // Fixed height to ensure both buttons are identical in size
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 8)

                // List of 12-hour forecasts
                if viewModel.isLoading {
                    Spacer(); ProgressView("Fetching Forecast..."); Spacer()
                } else if let err = viewModel.errorMessage {
                    Spacer(); Text("⚠️ \(err)").foregroundColor(.red)
                    Button("Retry") { viewModel.loadData() }.padding(); Spacer()
                } else {
                    List(viewModel.periods) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .center) {
                                Image(systemName: getIcon(for: item.shortForecast)).font(.largeTitle).frame(width: 50).foregroundColor(getColor(temp: item.temperature))
                                VStack(alignment: .leading) {
                                    Text("\(item.name) \(item.formattedDateString)").font(.headline)
                                    Text(item.shortForecast).font(.subheadline).foregroundColor(.secondary)
                                }
                                Spacer()
                                Text("\(item.temperature)°").font(.title).bold()
                            }
                            Text(item.detailedForecast).font(.caption).foregroundColor(.secondary).lineLimit(nil).padding(.top, 4)
                        }
                        .padding(.vertical, 8)
                    }
                    .listStyle(.plain)
                    .refreshable { viewModel.loadData() }
                }
            }
            
            // Bottom Buttons
            .overlay(alignment: .bottom) {
                HStack {
                    Button(action: { showRadar = true }) {
                        Image(systemName: "map.fill")
                            .font(.title2)
                            .padding()
                            .background(.thinMaterial)
                            .clipShape(Circle())
                            .shadow(radius: 4)
                    }
                    .padding(.leading)
                    
                    Spacer()
                    
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape.fill")
                            .font(.title2)
                            .padding()
                            .background(.thinMaterial)
                            .clipShape(Circle())
                            .shadow(radius: 4)
                    }
                    .padding(.trailing)
                }
                .padding(.bottom, 10)
            }
        }
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .sheet(isPresented: $showLocationPicker) {
            LocationPickerView(lat: viewModel.currentLat, lon: viewModel.currentLon) { lat, lon in
                viewModel.updateLocation(lat: lat, lon: lon)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(viewModel: viewModel, isDarkMode: $isDarkMode)
        }
        .fullScreenCover(isPresented: $showRadar) {
            RadarView(radarURL: radarURL)
        }
        .alert("Detailed Weather Report", isPresented: $showForecastAlert) {
            Button("OK") {}
        } message: {
            let details = viewModel.getAlertDetails()
            let hourlySummary = viewModel.getHourlyForecastSummary()
            let detailedForecast = viewModel.periods.first?.detailedForecast ?? ""
            return Text("\(details.frost)\n\(details.precip)\n\n--- Current Detailed Forecast ---\n\(detailedForecast)\n\n\(hourlySummary)")
        }
        .onAppear { viewModel.loadData() }
    }
    
    func getIcon(for forecast: String) -> String {
        let f = forecast.lowercased()
        if f.contains("sunny") || f.contains("clear") { return "sun.max.fill" }
        if f.contains("rain") { return "cloud.rain.fill" }
        if f.contains("snow") { return "snowflake" }
        if f.contains("cloud") { return "cloud.fill" }
        if f.contains("fog") { return "cloud.fog.fill" }
        return "thermometer"
    }
    
    func getColor(temp: Int) -> Color {
        if temp <= 32 { return .blue }
        if temp >= 80 { return .orange }
        return .primary
    }
}
