import SwiftUI

/// The open work Cadence is built on, with the attribution each licence asks for.
struct CreditsView: View {
    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    credit(
                        title: "Movement drawings",
                        body: "Drawings from Everkinetic, created by Greg Priday, through the Everkinetic open data project. Cadence removes the white fill, crops them and draws the lines in its own colours. The changed drawings are shared under the same licence.",
                        links: [
                            ("Everkinetic data", "https://github.com/everkinetic/data"),
                            ("CC BY-SA 4.0", "https://creativecommons.org/licenses/by-sa/4.0/"),
                        ]
                    )
                    credit(
                        title: "Muscle map",
                        body: "Body figures from react-native-body-highlighter by Hicham Elabbassi. Cadence splits them by muscle and draws them in its own colours.",
                        links: [("react-native-body-highlighter", "https://github.com/HichamELBSI/react-native-body-highlighter")],
                        licence: Self.mitLicence
                    )
                    credit(
                        title: "Weather",
                        body: "Weather data by Open-Meteo.",
                        links: [
                            ("Open-Meteo", "https://open-meteo.com"),
                            ("CC BY 4.0", "https://creativecommons.org/licenses/by/4.0/"),
                        ]
                    )
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
        .navigationTitle("Credits")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func credit(title: String, body: String, links: [(String, String)], licence: String? = nil) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.rowTitle).foregroundStyle(Palette.ink)
                Text(body).font(.body2).foregroundStyle(Palette.inkSecondary).fixedSize(horizontal: false, vertical: true)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 20) { linkRow(links) }
                    VStack(alignment: .leading, spacing: 0) { linkRow(links) }
                }
                if let licence {
                    Text(licence)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(Palette.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.raised, in: .rect(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    private func linkRow(_ links: [(String, String)]) -> some View {
        ForEach(links, id: \.1) { label, url in
            Link(destination: URL(string: url)!) {
                HStack(spacing: 6) {
                    Text(label)
                    Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold))
                }
                .font(.label)
                .foregroundStyle(Palette.accent)
                .frame(minHeight: 44)
                .fixedSize()
            }
        }
    }

    private static let mitLicence = """
        MIT License

        Copyright (c) 2022 ELABBASSI Hicham

        Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
        """
}
