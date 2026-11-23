import NotchivityKit
import SwiftUI

/// The usage column's last block: today's and this week's spend at API list prices, and one bar
/// per day from Monday. Against a limit the figures and today's bar take the usage lamps (amber
/// from 75%, red from 90%); without one they stay white.
struct SpendView: View {
    let spend: Spend
    let dailyLimit: Double
    let weeklyLimit: Double

    static let stripHeight: CGFloat = 44
    private static let letters = ["m", "t", "w", "t", "f", "s", "s"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Spend")
            HStack(alignment: .firstTextBaseline) {
                Text("today ") + figure(spend.todayCost, limit: dailyLimit)
                Spacer(minLength: 8)
                Text("week ") + figure(spend.weekCost, limit: weeklyLimit)
            }
            .font(.body)
            .lineLimit(1)
            .padding(.top, 6)
            strip.padding(.top, 8)
            letters.padding(.top, 3)
            Text(summary).font(.detail).foregroundStyle(Color.dim).padding(.top, 3)
        }
        .padding(.top, 12)
        .help("Claude Code tokens priced at Anthropic's API list prices. A subscription is billed differently.")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenSummary)
    }

    private func figure(_ cost: Double, limit: Double) -> Text {
        Text(Spend.money(cost)).foregroundStyle(tone(cost, limit: limit) ?? .white)
    }

    private func tone(_ cost: Double, limit: Double) -> Color? {
        limit > 0 ? Color.usage(cost / limit * 100) : nil
    }

    /// Bars share one scale with the limit line, so a day over the line reads as over.
    private var strip: some View {
        let scale = max(spend.days.map(\.cost).max() ?? 0, dailyLimit, 0.01)
        let height = Self.stripHeight
        return HStack(alignment: .bottom, spacing: 5) {
            ForEach(spend.days.indices, id: \.self) { index in
                bar(index, height: height * spend.days[index].cost / scale)
            }
        }
        .frame(height: height, alignment: .bottom)
        .overlay(alignment: .top) {
            if dailyLimit > 0 {
                LimitLine()
                    .stroke(Color.dim, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .frame(height: 1)
                    .offset(y: height - height * dailyLimit / scale)
            }
        }
    }

    /// Past days in Stroke Grey, today white (or its lamp), days ahead a 2pt Track Grey stub.
    private func bar(_ index: Int, height: CGFloat) -> some View {
        let day = spend.days[index]
        let ahead = index > spend.today
        let color: Color =
            ahead ? .track : index == spend.today ? tone(day.cost, limit: dailyLimit) ?? .white : .stroke
        return UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2)
            .fill(color)
            .frame(maxWidth: .infinity)
            .frame(height: ahead || day.cost == 0 ? 2 : max(2, height))
            .help(ahead ? "" : "\(weekday(index)) · \(Spend.money(day.cost)) · \(Spend.tokens(day.tokens)) tok")
    }

    private var letters: some View {
        HStack(spacing: 5) {
            ForEach(Self.letters.indices, id: \.self) { index in
                Text(Self.letters[index])
                    .foregroundStyle(index == spend.today ? .white : Color.dim)
                    .frame(maxWidth: .infinity)
            }
        }
        .font(.detail)
    }

    /// "1.42B tok this week · $60/day line"
    private var summary: String {
        ["\(Spend.tokens(spend.weekTokens)) tok this week", dailyLimit > 0 ? "\(Spend.limit(dailyLimit))/day line" : nil]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private var spokenSummary: String {
        func part(_ name: String, _ cost: Double, _ limit: Double) -> String {
            "\(name) \(Spend.money(cost))" + (limit > 0 ? " of \(Spend.limit(limit))" : "")
        }
        return "spend, " + part("today", spend.todayCost, dailyLimit) + ", " + part("this week", spend.weekCost, weeklyLimit)
    }

    private func weekday(_ index: Int) -> String {
        let date = Spend.calendar.date(byAdding: .day, value: index, to: spend.weekStart) ?? spend.weekStart
        return date.formatted(.dateTime.weekday(.abbreviated))
    }
}

/// The daily limit across the strip.
private struct LimitLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}
