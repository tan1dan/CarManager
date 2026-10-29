import SwiftUI

/// First-launch tour, shown once before the sign-in screen: what the app does and how to use
/// it. Finishing or skipping it marks onboarding complete, so signing out later goes straight
/// to sign-in.
struct IntroView: View {
    @Environment(\.appModel) private var model
    @State private var page = 0

    private let pages = IntroPage.all

    var body: some View {
        ZStack {
            SplashBackground()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    if page < pages.count - 1 {
                        Button("Skip", action: finish)
                            .font(DS.Text.rowTitle)
                            .foregroundStyle(Color.white.opacity(0.6))
                            .frame(minWidth: 44, minHeight: 44)
                            .accessibilityIdentifier("introSkip")
                    }
                }
                .frame(height: 44)
                .padding(.horizontal, DS.Layout.gutter)

                TabView(selection: $page) {
                    ForEach(pages.indices, id: \.self) { index in
                        IntroPageView(page: pages[index]).tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                VStack(spacing: 24) {
                    PageDots(count: pages.count, current: page)
                    AccentCapsuleButton(title: page == pages.count - 1 ? String(localized: "Get started") : String(localized: "Continue")) {
                        if page < pages.count - 1 {
                            withAnimation(.snappy) { page += 1 }
                        } else {
                            finish()
                        }
                    }
                    .accessibilityIdentifier("introContinue")
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 8)
            }
        }
        .environment(\.colorScheme, .dark)
        .sensoryFeedback(.selection, trigger: page)
    }

    private func finish() {
        withAnimation(.easeInOut) { model?.onboarding.complete() }
    }
}

// MARK: - Pages

struct IntroPage: Identifiable {
    enum Art { case garage, receipt, assistant, reminders }

    let id: Int
    let eyebrow: String
    let title: String
    let body: String
    let art: Art

    static let all: [IntroPage] = [
        IntroPage(
            id: 0, eyebrow: String(localized: "YOUR GARAGE"),
            title: String(localized: "Your whole car\nin one place"),
            body: String(localized: "Fill-ups, services, expenses and documents for every car you own — with mileage, consumption and costs worked out for you."),
            art: .garage
        ),
        IntroPage(
            id: 1, eyebrow: String(localized: "LOG IN SECONDS"),
            title: String(localized: "Snap a receipt,\nwe fill it in"),
            body: String(localized: "Tap + and photograph a receipt. AI reads the amount, litres and date, converts foreign currency — you check it and save."),
            art: .receipt
        ),
        IntroPage(
            id: 2, eyebrow: String(localized: "AI ASSISTANT"),
            title: String(localized: "Ask anything\nabout your car"),
            body: String(localized: "Chat about your car, scan a dashboard warning light or a dent. Answers are guidance, not a mechanic's diagnosis."),
            art: .assistant
        ),
        IntroPage(
            id: 3, eyebrow: String(localized: "STAY AHEAD"),
            title: String(localized: "Never miss\nwhat's due"),
            body: String(localized: "Reminders for service, inspection and insurance by date or mileage. Your data stays private in your own iCloud."),
            art: .reminders
        )
    ]
}

private struct IntroPageView: View {
    let page: IntroPage

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)
            IntroArt(art: page.art)
                .frame(height: 300)
                .accessibilityHidden(true)
            Spacer(minLength: 24)
            VStack(spacing: 12) {
                Text(page.eyebrow)
                    .font(DS.Text.eyebrow)
                    .tracking(DS.Text.eyebrowTracking)
                    .foregroundStyle(DS.Colors.accent)
                Text(page.title)
                    .font(DS.Text.title)
                    .tracking(DS.Text.titleTracking)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
                Text(page.body)
                    .font(DS.Text.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)
            Spacer(minLength: 16)
        }
    }
}

private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Color.white : Color.white.opacity(0.25))
                    .frame(width: index == current ? 22 : 8, height: 8)
            }
        }
        .animation(.snappy, value: current)
        .accessibilityElement()
        .accessibilityLabel("Page \(current + 1) of \(count)")
    }
}

// MARK: - Illustrations
//
// Small mock-ups of the real screens, drawn with the app's own tokens, so the tour shows what
// the user is about to see rather than abstract art.

private struct IntroArt: View {
    let art: IntroPage.Art

    var body: some View {
        switch art {
        case .garage: GarageArt()
        case .receipt: ReceiptArt()
        case .assistant: AssistantArt()
        case .reminders: RemindersArt()
        }
    }
}

/// A glass card with a hairline, the surface every illustration sits on.
private struct ArtCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(hex: 0x111A2B))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08)))
            )
            .shadow(color: .black.opacity(0.35), radius: 24, y: 14)
    }
}

private struct ArtIcon: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(Circle().fill(tint.opacity(0.16)))
    }
}

private struct ArtRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let subtitle: String
    let trailing: String

    var body: some View {
        HStack(spacing: 12) {
            ArtIcon(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                Text(subtitle).font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.5))
            }
            Spacer(minLength: 8)
            Text(trailing).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
        }
    }
}

private struct GarageArt: View {
    private let format = DisplayFormat()

    var body: some View {
        ZStack {
            // The vehicle card, as on Home.
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("My vehicle").font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.6))
                    Text("Volkswagen Golf").font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                }
                HStack(spacing: 10) {
                    stat(String(localized: "MILEAGE"), format.integer(84_210), format.distanceUnit)
                    stat(String(localized: "AVG"), format.decimal(6.1), format.consumptionUnit)
                }
            }
            .padding(18)
            .frame(width: 260, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous).fill(DS.Gradients.vehicleCard)
                    .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
            )
            .shadow(color: Color(hex: 0x3B82F6).opacity(0.35), radius: 30, y: 16)
            .offset(y: -62)

            ArtCard(padding: 14) {
                VStack(spacing: 12) {
                    ArtRow(symbol: "fuelpump.fill", tint: DS.Colors.accent, title: String(localized: "Fill-up"), subtitle: String(localized: "Shell · 42 L"), trailing: format.money(Decimal(string: "71.40")!, .eur, fractionDigits: 2))
                    ArtRow(symbol: "wrench.adjustable.fill", tint: Color(hex: 0x8B6CF6), title: String(localized: "Oil change"), subtitle: String(localized: "Service"), trailing: format.money(129, .eur))
                }
            }
            .frame(width: 290)
            .offset(y: 78)
        }
    }

    private func stat(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(DS.Text.statLabel).tracking(DS.Text.statLabelTracking).foregroundStyle(Color.white.opacity(0.5))
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                Text(unit).font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Capsule().fill(Color.white.opacity(0.06)).overlay(Capsule().strokeBorder(Color.white.opacity(0.1))))
    }
}

private struct ReceiptArt: View {
    private let format = DisplayFormat()

    var body: some View {
        ZStack {
            // The paper receipt, tilted behind.
            VStack(alignment: .leading, spacing: 7) {
                Text("FUEL STATION").font(.system(size: 11, weight: .bold, design: .monospaced))
                ForEach(0..<5, id: \.self) { i in
                    Capsule().fill(Color.black.opacity(0.12)).frame(width: i % 2 == 0 ? 100 : 72, height: 6)
                }
                Text("TOTAL").font(.system(size: 11, weight: .bold, design: .monospaced)).padding(.top, 4)
                Text("322,60 zł").font(.system(size: 15, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(Color.black.opacity(0.75))
            .padding(16)
            .frame(width: 170, height: 210, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.96)))
            .rotationEffect(.degrees(-8))
            .offset(x: -62, y: -14)
            .shadow(color: .black.opacity(0.4), radius: 20, y: 10)

            // What the app read from it.
            ArtCard(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles").foregroundStyle(DS.Colors.accent)
                        Text("Read by AI").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.white.opacity(0.7))
                    }
                    field(String(localized: "Total"), format.money(Decimal(string: "75.89")!, .eur, fractionDigits: 2))
                    field(String(localized: "Fuel"), "48.32 L")
                    field(String(localized: "Date"), String(localized: "8 Oct"))
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.left.arrow.right").font(.system(size: 10, weight: .bold))
                        Text("PLN → EUR · ECB rate").font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(DS.Colors.accent)
                }
            }
            .frame(width: 190)
            .offset(x: 62, y: 30)

            ArtIcon(symbol: "checkmark", tint: DS.Colors.success, size: 44)
                .background(Circle().fill(Color(hex: 0x0A121F)))
                .offset(x: 140, y: -78)
        }
    }

    private func field(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.5))
            Spacer()
            Text(value).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
        }
    }
}

private struct AssistantArt: View {
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Spacer(minLength: 60)
                bubble(String(localized: "The oil light came on. Can I keep driving?"), user: true)
            }
            HStack(alignment: .bottom, spacing: 8) {
                ArtIcon(symbol: "sparkles", tint: .white, size: 30)
                    .background(Circle().fill(DS.Gradients.aiCard))
                bubble(String(localized: "Pull over safely and check the oil level. If it's low, don't drive further."), user: false)
                Spacer(minLength: 30)
            }
            HStack(spacing: 10) {
                tool("gauge.with.dots.needle.33percent", String(localized: "Scan dashboard"))
                tool("car.side.rear.and.collision.and.car.side.front", String(localized: "Analyze damage"))
            }
            .padding(.top, 6)
        }
        .frame(width: 320)
    }

    private func bubble(_ text: String, user: Bool) -> some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(user ? AnyShapeStyle(DS.Gradients.accentButton) : AnyShapeStyle(Color(hex: 0x111A2B)))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(user ? 0 : 0.08)))
            )
    }

    private func tool(_ symbol: String, _ title: String) -> some View {
        ArtCard(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                ArtIcon(symbol: symbol, tint: Color(hex: 0x14C3B8), size: 32)
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct RemindersArt: View {
    private let format = DisplayFormat()

    var body: some View {
        VStack(spacing: 12) {
            ArtCard(padding: 14) {
                VStack(spacing: 12) {
                    ArtRow(symbol: "checkmark.seal.fill", tint: DS.Colors.danger, title: String(localized: "Technical inspection"), subtitle: String(localized: "Due in 5 days"), trailing: "")
                    ArtRow(symbol: "drop.fill", tint: DS.Colors.warning, title: String(localized: "Oil change"), subtitle: String(localized: "In 1 200 km"), trailing: "")
                    ArtRow(symbol: "shield.fill", tint: DS.Colors.accent, title: String(localized: "Insurance renewal"), subtitle: String(localized: "12 Mar"), trailing: "")
                }
            }
            HStack(spacing: 12) {
                ArtCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("This month").font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.5))
                        Text(format.money(284, .eur)).font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                        HStack(alignment: .bottom, spacing: 5) {
                            ForEach(Array([0.4, 0.7, 0.5, 0.9, 0.6, 1.0].enumerated()), id: \.offset) { item in
                                Capsule().fill(item.offset == 5 ? DS.Colors.accent : Color.white.opacity(0.18))
                                    .frame(width: 10, height: 34 * item.element)
                            }
                        }
                        .frame(height: 34, alignment: .bottom)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                ArtCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        ArtIcon(symbol: "icloud.fill", tint: Color(hex: 0x14C3B8), size: 32)
                        Text("Private\nin your iCloud").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 310)
    }
}

#Preview {
    IntroView()
}
