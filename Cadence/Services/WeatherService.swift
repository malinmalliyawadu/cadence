import CoreLocation
import Foundation
import TrainingEngine
import WeatherKit

protocol ForecastProviding: Sendable {
    func forecast(latitude: Double, longitude: Double, days: Int) async throws -> [DayForecast]
}

enum Forecasts {
    /// Apple Weather in release builds. Debug builds fall back to Open-Meteo, because an ad hoc
    /// signed simulator build cannot authenticate with WeatherKit.
    static var standard: any ForecastProviding {
        #if DEBUG
        FallbackForecast(primary: AppleWeatherService(), fallback: OpenMeteoService())
        #else
        AppleWeatherService()
        #endif
    }
}

/// Daily forecasts from Apple Weather, ten days at most. Needs the WeatherKit capability and App
/// Service on the App ID. The attribution Apple asks for is `WeatherAttributionView`.
struct AppleWeatherService: ForecastProviding {
    func forecast(latitude: Double, longitude: Double, days: Int = 10) async throws -> [DayForecast] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now)
        let end = calendar.date(byAdding: .day, value: min(10, max(1, days)), to: start)!
        let daily = try await WeatherKit.WeatherService.shared.weather(
            for: CLLocation(latitude: latitude, longitude: longitude),
            including: .daily(startDate: start, endDate: end)
        )
        return daily.map { day in
            DayForecast(
                date: calendar.startOfDay(for: day.date),
                tempMaxC: day.highTemperature.converted(to: .celsius).value,
                tempMinC: day.lowTemperature.converted(to: .celsius).value,
                precipitationProbability: day.precipitationChance,
                precipitationMm: day.precipitationAmountByType.precipitation.converted(to: .millimeters).value,
                windKph: (day.highWindSpeed ?? day.wind.speed).converted(to: .kilometersPerHour).value,
                uvIndex: Double(day.uvIndex.value),
                weatherCode: Self.wmoCode(for: day.condition)
            )
        }
    }

    /// The engine reads conditions as WMO codes, the scheme Open-Meteo uses.
    static func wmoCode(for condition: WeatherKit.WeatherCondition) -> Int {
        switch condition {
        case .clear, .hot, .frigid: 0
        case .mostlyClear: 1
        case .partlyCloudy, .breezy, .windy, .blowingDust: 2
        case .mostlyCloudy, .cloudy: 3
        case .foggy, .haze, .smoky: 45
        case .drizzle: 53
        case .freezingDrizzle: 56
        case .rain, .sunShowers: 63
        case .heavyRain: 65
        case .freezingRain, .sleet, .wintryMix, .hail: 67
        case .snow, .flurries, .sunFlurries, .blowingSnow: 73
        case .heavySnow, .blizzard: 75
        case .thunderstorms, .isolatedThunderstorms, .scatteredThunderstorms, .strongStorms, .tropicalStorm, .hurricane: 95
        @unknown default: 2
        }
    }
}

#if DEBUG
struct FallbackForecast: ForecastProviding {
    let primary: any ForecastProviding
    let fallback: any ForecastProviding

    func forecast(latitude: Double, longitude: Double, days: Int) async throws -> [DayForecast] {
        do {
            return try await primary.forecast(latitude: latitude, longitude: longitude, days: days)
        } catch {
            print("Apple Weather failed, using Open-Meteo: \(error.localizedDescription)")
            return try await fallback.forecast(latitude: latitude, longitude: longitude, days: days)
        }
    }
}

/// Daily forecasts from Open-Meteo, for development only: the free API is non-commercial.
struct OpenMeteoService: ForecastProviding {
    var session: URLSession = .shared

    func forecast(latitude: Double, longitude: Double, days: Int = 10) async throws -> [DayForecast] {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", longitude)),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,precipitation_sum,wind_speed_10m_max,uv_index_max"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: String(min(16, max(1, days)))),
        ]
        let (data, response) = try await session.data(from: components.url!)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WeatherError.badResponse
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: payload.timezone) ?? .current
        formatter.locale = Locale(identifier: "en_US_POSIX")

        return payload.daily.time.indices.compactMap { i in
            guard let date = formatter.date(from: payload.daily.time[i]) else { return nil }
            return DayForecast(
                date: Calendar.current.startOfDay(for: date),
                tempMaxC: payload.daily.temperature2mMax[i] ?? 15,
                tempMinC: payload.daily.temperature2mMin[i] ?? 8,
                precipitationProbability: (payload.daily.precipitationProbabilityMax[i] ?? 0) / 100,
                precipitationMm: payload.daily.precipitationSum[i] ?? 0,
                windKph: payload.daily.windSpeed10mMax[i] ?? 0,
                uvIndex: payload.daily.uvIndexMax[i] ?? 0,
                weatherCode: payload.daily.weatherCode[i] ?? 1
            )
        }
    }

    enum WeatherError: Error { case badResponse }

    private struct Payload: Decodable {
        let timezone: String
        let daily: Daily
        struct Daily: Decodable {
            let time: [String]
            let weatherCode: [Int?]
            let temperature2mMax: [Double?]
            let temperature2mMin: [Double?]
            let precipitationProbabilityMax: [Double?]
            let precipitationSum: [Double?]
            let windSpeed10mMax: [Double?]
            let uvIndexMax: [Double?]
            enum CodingKeys: String, CodingKey {
                case time
                case weatherCode = "weather_code"
                case temperature2mMax = "temperature_2m_max"
                case temperature2mMin = "temperature_2m_min"
                case precipitationProbabilityMax = "precipitation_probability_max"
                case precipitationSum = "precipitation_sum"
                case windSpeed10mMax = "wind_speed_10m_max"
                case uvIndexMax = "uv_index_max"
            }
        }
    }
}
#endif
