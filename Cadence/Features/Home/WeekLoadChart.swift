import SwiftUI

/// Monday to Sunday as hatched bars: solid for load already logged, dashed for what is still
/// planned. Today is the mint one, with its number pinned above it.
struct WeekLoadChart: View {
    struct Day: Identifiable {
        let date: Date
        let logged: Double
        let planned: Double
        var id: Date { date }
        var total: Double { logged + planned }
    }

    let days: [Day]
    let today: Date
    let calendar: Calendar

    private let plotHeight: CGFloat = 168
    private let axisWidth: CGFloat = 34

    private var scaleMax: Double { Self.niceCeiling((days.map(\.total).max() ?? 0) * 1.25) }
    private var logged: Double { days.map(\.logged).reduce(0, +) }
    private var total: Double { days.map(\.total).reduce(0, +) }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    TitleIcon(symbol: "flame")
                    Text("Load this week").font(.rowTitle).foregroundStyle(Palette.ink)
                    Spacer(minLength: 8)
                    Text("\(Format.load(logged)) of \(Format.load(total))")
                        .font(.label.monospacedDigit())
                        .foregroundStyle(Palette.inkSecondary)
                }
                chart
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Load this week")
        .accessibilityValue(accessibilitySummary)
    }

    private var chart: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                ForEach(0...4, id: \.self) { step in
                    let value = scaleMax * Double(step) / 4
                    HStack(spacing: 8) {
                        Text(Format.load(value))
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(Palette.inkTertiary)
                            .frame(width: axisWidth, alignment: .trailing)
                        Rectangle().fill(Palette.hairline).frame(height: 1)
                    }
                    .alignmentGuide(.bottom) { $0[VerticalAlignment.center] }
                    .offset(y: -plotHeight * CGFloat(step) / 4)
                }
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(days) { day in column(day) }
                }
                .padding(.leading, axisWidth + 12)
                // A session logged or re-planned grows or shrinks its day's bar.
                .animation(Motion.settle, value: days.map(\.total))
            }
            .frame(height: plotHeight, alignment: .bottom)

            HStack(spacing: 10) {
                ForEach(days) { day in
                    Text(Format.shortWeekday.string(from: day.date))
                        .font(.system(size: 12, weight: calendar.isDate(day.date, inSameDayAs: today) ? .semibold : .medium))
                        .foregroundStyle(calendar.isDate(day.date, inSameDayAs: today) ? Palette.today : Palette.inkTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.leading, axisWidth + 12)
        }
    }

    private func column(_ day: Day) -> some View {
        let isToday = calendar.isDate(day.date, inSameDayAs: today)
        let scale = scaleMax > 0 ? plotHeight / CGFloat(scaleMax) : 0
        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            if isToday, day.total > 0 {
                ValueCallout(text: Format.load(day.total)).padding(.bottom, 6)
            }
            if day.planned > 0 {
                HatchedBar(isToday: isToday, isPlanned: true)
                    .frame(height: max(CGFloat(day.planned) * scale, 16))
            }
            if day.planned > 0, day.logged > 0 { Spacer().frame(height: 3) }
            if day.logged > 0 {
                HatchedBar(isToday: isToday)
                    .frame(height: max(CGFloat(day.logged) * scale, 16))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: plotHeight)
    }

    private var accessibilitySummary: String {
        days.filter { $0.total > 0 }.map { day in
            "\(Format.weekday.string(from: day.date)) \(Format.load(day.logged)) logged, \(Format.load(day.planned)) planned"
        }.joined(separator: ", ")
    }

    /// Rounds up to the next value whose quarters are round numbers (1,200 reads 300, 600, 900),
    /// in steps fine enough that the tallest bar fills most of the plot.
    static func niceCeiling(_ value: Double) -> Double {
        guard value > 0 else { return 100 }
        let magnitude = pow(10, floor(log10(value)))
        let step = [1, 1.2, 1.6, 2, 2.4, 3.2, 4, 6, 8, 10].first { $0 * magnitude >= value } ?? 10
        return step * magnitude
    }
}
