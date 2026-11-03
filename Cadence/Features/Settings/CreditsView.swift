import SwiftUI

/// The open work Cadence is built on, with the attribution each licence asks for.
struct CreditsView: View {
    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    credit(
                        title: "Movement photos",
                        body: "Photos from Free Exercise DB, which builds on the exercises.json project and is dedicated to the public domain. Cadence crops them to one size.",
                        links: [
                            ("Free Exercise DB", "https://github.com/yuhonas/free-exercise-db"),
                            ("Unlicense", "https://unlicense.org"),
                        ]
                    )
                    credit(
                        title: "Muscle map",
                        body: "Body figures from react-native-body-highlighter by Hicham Elabbassi. Cadence splits them by muscle and draws them in its own colours.",
                        links: [("react-native-body-highlighter", "https://github.com/HichamELBSI/react-native-body-highlighter")],
                        licence: Self.mitLicence
                    )
                    credit(
                        title: "Typeface",
                        body: "Sora, designed by Jonathan Barnbrook and Julián Moncada for the Sora Project, under the SIL Open Font License.",
                        links: [
                            ("Sora", "https://github.com/sora-xor/sora-font"),
                            ("OFL 1.1", "https://openfontlicense.org"),
                        ],
                        licence: Self.oflLicence
                    )
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Weather").font(.rowTitle).foregroundStyle(Palette.ink)
                            Text("Forecasts from Apple Weather.").font(.body2).foregroundStyle(Palette.inkSecondary)
                            WeatherAttributionView()
                        }
                    }
                }
                .padding(.horizontal, Metrics.gutter)
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

    private static let oflLicence = """
        Copyright 2019 The Sora Project Authors (https://github.com/sora-xor/sora-font)

        This Font Software is licensed under the SIL Open Font License, Version 1.1.

        SIL OPEN FONT LICENSE Version 1.1 - 26 February 2007

        PREAMBLE
        The goals of the Open Font License (OFL) are to stimulate worldwide development of collaborative font projects, to support the font creation efforts of academic and linguistic communities, and to provide a free and open framework in which fonts may be shared and improved in partnership with others.

        The OFL allows the licensed fonts to be used, studied, modified and redistributed freely as long as they are not sold by themselves. The fonts, including any derivative works, can be bundled, embedded, redistributed and/or sold with any software provided that any reserved names are not used by derivative works. The fonts and derivatives, however, cannot be released under any other type of license. The requirement for fonts to remain under this license does not apply to any document created using the fonts or their derivatives.

        DEFINITIONS
        "Font Software" refers to the set of files released by the Copyright Holder(s) under this license and clearly marked as such. This may include source files, build scripts and documentation.

        "Reserved Font Name" refers to any names specified as such after the copyright statement(s).

        "Original Version" refers to the collection of Font Software components as distributed by the Copyright Holder(s).

        "Modified Version" refers to any derivative made by adding to, deleting, or substituting -- in part or in whole -- any of the components of the Original Version, by changing formats or by porting the Font Software to a new environment.

        "Author" refers to any designer, engineer, programmer, technical writer or other person who contributed to the Font Software.

        PERMISSION & CONDITIONS
        Permission is hereby granted, free of charge, to any person obtaining a copy of the Font Software, to use, study, copy, merge, embed, modify, redistribute, and sell modified and unmodified copies of the Font Software, subject to the following conditions:

        1) Neither the Font Software nor any of its individual components, in Original or Modified Versions, may be sold by itself.

        2) Original or Modified Versions of the Font Software may be bundled, redistributed and/or sold with any software, provided that each copy contains the above copyright notice and this license. These can be included either as stand-alone text files, human-readable headers or in the appropriate machine-readable metadata fields within text or binary files as long as those fields can be easily viewed by the user.

        3) No Modified Version of the Font Software may use the Reserved Font Name(s) unless explicit written permission is granted by the corresponding Copyright Holder. This restriction only applies to the primary font name as presented to the users.

        4) The name(s) of the Copyright Holder(s) or the Author(s) of the Font Software shall not be used to promote, endorse or advertise any Modified Version, except to acknowledge the contribution(s) of the Copyright Holder(s) and the Author(s) or with their explicit written permission.

        5) The Font Software, modified or unmodified, in part or in whole, must be distributed entirely under this license, and must not be distributed under any other license. The requirement for fonts to remain under this license does not apply to any document created using the Font Software.

        TERMINATION
        This license becomes null and void if any of the above conditions are not met.

        DISCLAIMER
        THE FONT SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO ANY WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT OF COPYRIGHT, PATENT, TRADEMARK, OR OTHER RIGHT. IN NO EVENT SHALL THE COPYRIGHT HOLDER BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, INCLUDING ANY GENERAL, SPECIAL, INDIRECT, INCIDENTAL, OR CONSEQUENTIAL DAMAGES, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF THE USE OR INABILITY TO USE THE FONT SOFTWARE OR FROM OTHER DEALINGS IN THE FONT SOFTWARE.
        """
}
