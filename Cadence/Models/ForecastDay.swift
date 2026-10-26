import Foundation
import SwiftData
import TrainingEngine

/// Cached daily forecast so the plan stays explainable offline.
@Model
final class ForecastDay {
    @Attribute(.unique) var date: Date
    var tempMaxC: Double
    var tempMinC: Double
    var precipitationProbability: Double
    var precipitationMm: Double
    var windKph: Double
    var uvIndex: Double
    var weatherCode: Int
    var fetchedAt: Date

    init(_ forecast: DayForecast, fetchedAt: Date = .now) {
        date = forecast.date
        tempMaxC = forecast.tempMaxC
        tempMinC = forecast.tempMinC
        precipitationProbability = forecast.precipitationProbability
        precipitationMm = forecast.precipitationMm
        windKph = forecast.windKph
        uvIndex = forecast.uvIndex
        weatherCode = forecast.weatherCode
        self.fetchedAt = fetchedAt
    }

    func update(from forecast: DayForecast, fetchedAt: Date = .now) {
        tempMaxC = forecast.tempMaxC
        tempMinC = forecast.tempMinC
        precipitationProbability = forecast.precipitationProbability
        precipitationMm = forecast.precipitationMm
        windKph = forecast.windKph
        uvIndex = forecast.uvIndex
        weatherCode = forecast.weatherCode
        self.fetchedAt = fetchedAt
    }

    var forecast: DayForecast {
        DayForecast(date: date, tempMaxC: tempMaxC, tempMinC: tempMinC, precipitationProbability: precipitationProbability, precipitationMm: precipitationMm, windKph: windKph, uvIndex: uvIndex, weatherCode: weatherCode)
    }
}
