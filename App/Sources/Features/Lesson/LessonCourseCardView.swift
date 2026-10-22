import SwiftUI
import LearningCore

/// One card of a lesson's course, read before the questions: big emoji or Arabic, title, text,
/// « À retenir » and an example. The pastel colour changes from card to card.
struct LessonCourseCard: View {
    let step: CourseCardStep
    let lessonTitle: String?
    let isBusy: Bool
    let onContinue: () -> Void

    private var isLast: Bool { step.index + 1 >= step.total }
    private var pastel: Pastel { Pastel.allCases[(step.index + 1) % Pastel.allCases.count] }

    var body: some View {
        LessonScaffold {
            VStack(alignment: .leading, spacing: Theme.Spacing.card) {
                card
                    .qAppear(0)
                if isLast {
                    Text("Maintenant, les questions : tout ce qui est demandé est dans ce cours.")
                        .font(Theme.Font.callout)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .qAppear(1)
                }
            }
        } footer: {
            Button(isLast ? "C'est parti !" : "Continuer", action: onContinue)
                .buttonStyle(.primary)
                .disabled(isBusy)
        }
    }

    private var card: some View {
        PastelCard(pastel, padding: 22) {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                HStack(spacing: Theme.Spacing.s) {
                    QPill(text: "Cours · \(step.index + 1)/\(step.total)", icon: .book)
                    if let lessonTitle, step.index == 0 {
                        Text(lessonTitle)
                            .font(Theme.Font.caption(.semibold))
                            .foregroundStyle(Theme.onPastelSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                if let arabic = step.card.arabic, !arabic.isEmpty {
                    HStack(alignment: .center, spacing: Theme.Spacing.m) {
                        Text(arabic)
                            .font(.system(size: 72, weight: .regular))
                            .foregroundStyle(Theme.ink)
                            .environment(\.layoutDirection, .rightToLeft)
                            .minimumScaleFactor(0.4)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        QSpeakerButton(text: arabic)
                    }
                } else if let emoji = step.card.emoji, !emoji.isEmpty {
                    Text(emoji)
                        .font(.system(size: 56))
                        .accessibilityHidden(true)
                }
                CardTitle(step.card.title)
                    .accessibilityAddTraits(.isHeader)
                Text(step.card.text).arabicAware(step.card.text, .title3)
                    .font(Theme.Font.headline)
                    .foregroundStyle(Theme.ink)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                if let keyFact = step.card.keyFact, !keyFact.isEmpty {
                    QCallout(systemImage: "lightbulb", tint: Theme.ink, fill: Theme.surface) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("À retenir")
                                .font(Theme.Font.caption(.semibold))
                                .foregroundStyle(Theme.secondaryText)
                            Text(keyFact).arabicAware(keyFact, .title3)
                                .font(Theme.Font.body(.semibold))
                                .foregroundStyle(Theme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                if let example = step.card.example {
                    HStack(alignment: .top, spacing: Theme.Spacing.s) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text(example.text).arabicAware(example.text, .title2)
                                .font(Theme.Font.body(.semibold))
                                .foregroundStyle(Theme.ink)
                            Text(example.translation)
                                .font(Theme.Font.callout)
                                .foregroundStyle(Theme.onPastelSecondary)
                        }
                        Spacer(minLength: 0)
                        QSpeakerButton(text: example.text)
                    }
                    .padding(Theme.Spacing.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(Theme.surface))
                }
            }
        }
    }
}
