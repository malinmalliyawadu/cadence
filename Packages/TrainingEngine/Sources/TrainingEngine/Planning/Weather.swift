import Foundation

/// A day's forecast reduced to what matters for choosing when to run.
public struct DayForecast: Codable, Sendable, Hashable, Identifiable {
    public var id: Date { date }
    public let date: Date
    public let tempMaxC: Double
    public let tempMinC: Double
    /// 0 ... 1
    public let precipitationProbability: Double
    public let precipitationMm: Double
    public let windKph: Double
    public let uvIndex: Double
    /// WMO weather interpretation code, as published by Open-Meteo and most national services.
    public let weatherCode: Int

    public init(date: Date, tempMaxC: Double, tempMinC: Double, precipitationProbability: Double, precipitationMm: Double, windKph: Double, uvIndex: Double, weatherCode: Int) {
        self.date = date
        self.tempMaxC = tempMaxC
        self.tempMinC = tempMinC
        self.precipitationProbability = min(1, max(0, precipitationProbability))
        self.precipitationMm = max(0, precipitationMm)
        self.windKph = max(0, windKph)
        self.uvIndex = max(0, uvIndex)
        self.weatherCode = weatherCode
    }

    /// 0 (do not run outside) to 1 (perfect). A weighted geometric mean of temperature,
    /// rain and wind: temperature carries the most weight because it is what the body
    /// notices most, but any one hostile component can veto the day on its own, which an
    /// additive score cannot do.
    public var runningScore: Double {
        let temp = temperatureScore
        let rain = max(0, 1 - precipitationProbability * 0.8 - min(precipitationMm, 10) / 10 * 0.3)
        let wind: Double = windKph <= 15 ? 1 : windKph >= 45 ? 0 : 1 - (windKph - 15) / 30
        let score = pow(temp, 0.45) * pow(rain, 0.40) * pow(wind, 0.15)
        return min(1, max(0, score))
    }

    private var temperatureScore: Double {
        // Ideal band 8 ... 17 C. Falls to zero at -5 C and 30 C.
        switch tempMaxC {
        case 8...17: return 1
        case ..<8: return max(0, (tempMaxC + 5) / 13)
        default: return max(0, (30 - tempMaxC) / 13)
        }
    }

    public var condition: WeatherCondition { WeatherCondition(code: weatherCode) }

    public var isGoodRunningDay: Bool { runningScore >= 0.65 }
}

public enum WeatherCondition: String, Codable, Sendable, Hashable {
    case clear, partlyCloudy, overcast, fog, drizzle, rain, heavyRain, snow, thunderstorm

    public init(code: Int) {
        switch code {
        case 0: self = .clear
        case 1, 2: self = .partlyCloudy
        case 3: self = .overcast
        case 45, 48: self = .fog
        case 51, 53, 55, 56, 57: self = .drizzle
        case 61, 63, 80, 81: self = .rain
        case 65, 66, 67, 82: self = .heavyRain
        case 71, 73, 75, 77, 85, 86: self = .snow
        case 95, 96, 99: self = .thunderstorm
        default: self = .partlyCloudy
        }
    }

    public var displayName: String {
        switch self {
        case .clear: "Clear"
        case .partlyCloudy: "Partly cloudy"
        case .overcast: "Overcast"
        case .fog: "Fog"
        case .drizzle: "Drizzle"
        case .rain: "Rain"
        case .heavyRain: "Heavy rain"
        case .snow: "Snow"
        case .thunderstorm: "Thunderstorms"
        }
    }

    /// SF Symbol name.
    public var symbolName: String {
        switch self {
        case .clear: "sun.max.fill"
        case .partlyCloudy: "cloud.sun.fill"
        case .overcast: "cloud.fill"
        case .fog: "cloud.fog.fill"
        case .drizzle: "cloud.drizzle.fill"
        case .rain: "cloud.rain.fill"
        case .heavyRain: "cloud.heavyrain.fill"
        case .snow: "cloud.snow.fill"
        case .thunderstorm: "cloud.bolt.rain.fill"
        }
    }
}
