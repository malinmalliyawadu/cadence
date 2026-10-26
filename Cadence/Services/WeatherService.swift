import Foundation
import TrainingEngine

/// Daily forecasts from Open-Meteo. No API key, no account, works in the simulator.
/// Swap for WeatherKit by conforming another type to `ForecastProviding`.
protocol ForecastProviding: Sendable {
    func forecast(latitude: Double, longitude: Double, days: Int) async throws -> [DayForecast]
}

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
