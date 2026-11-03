import SwiftUI
import WeatherKit

/// The Apple Weather mark and the legal link WeatherKit's terms ask for wherever its data shows.
struct WeatherAttributionView: View {
    @State private var attribution: WeatherAttribution?

    var body: some View {
        HStack(spacing: 12) {
            if let attribution {
                AsyncImage(url: attribution.combinedMarkDarkURL) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Text(attribution.serviceName).font(.label).foregroundStyle(Palette.inkSecondary)
                }
                .frame(height: 12)
                .accessibilityLabel(attribution.serviceName)
                Link(destination: attribution.legalPageURL) {
                    Text("Other data sources")
                        .font(.label)
                        .foregroundStyle(Palette.inkTertiary)
                        .underline()
                        .frame(minHeight: 44)
                }
            }
        }
        .task {
            attribution = try? await WeatherService.shared.attribution
        }
    }
}
