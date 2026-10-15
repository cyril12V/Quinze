import SwiftUI
import LearningCore

// MARK: - Reorder (tap words to build the sentence, tap a placed word to remove it)

private struct ReorderItem: Identifiable, Hashable {
    let id: Int
    let text: String
}

struct ExerciseReorderInput: View {
    let exercise: Exercise
    @Binding var answer: AnswerSubmission?

    @State private var chosen: [Int] = []

    init(exercise: Exercise, answer: Binding<AnswerSubmission?>) {
        self.exercise = exercise
        self._answer = answer
    }

    private var solution: [String] {
        exercise.answer.split(separator: " ").map { String($0) }
    }

    private var items: [ReorderItem] {
        let source: [String]
        if let tokens = exercise.tokens, !tokens.isEmpty {
            source = tokens
        } else {
            source = solution
        }
        let indexed: [ReorderItem] = source.enumerated().map { ReorderItem(id: $0.offset, text: $0.element) }
        var shuffled: [ReorderItem] = indexed.stableShuffled(seed: exercise.id)
        // Never present the solved order.
        if shuffled.count > 1, shuffled.map({ $0.text }) == solution {
            shuffled.append(shuffled.removeFirst())
        }
        return shuffled
    }

    var body: some View {
        let allItems: [ReorderItem] = items
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            answerZone(allItems)
            bank(allItems)
        }
    }

    /// White rounded zone where the sentence is built; placed words are ink capsules.
    private func answerZone(_ allItems: [ReorderItem]) -> some View {
        ZStack(alignment: .topLeading) {
            if chosen.isEmpty {
                Text("Touche les mots dans l'ordre")
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.tertiaryText)
                    .padding(Theme.Spacing.m)
                    .accessibilityHidden(true)
            }
            QFlowLayout() {
                ForEach(Array(chosen.enumerated()), id: \.element) { position, id in
                    if let item = allItems.first(where: { $0.id == id }) {
                        Button {
                            remove(id, allItems: allItems)
                        } label: {
                            Text(item.text)
                        }
                        .buttonStyle(QChipButtonStyle(isSelected: true))
                        .accessibilityLabel("\(item.text), mot \(position + 1) sur \(chosen.count)")
                        .accessibilityHint("Retire ce mot de ta phrase")
                    }
                }
            }
            .padding(Theme.Spacing.m)
        }
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .fill(Theme.surface)
        )
    }

    private func bank(_ allItems: [ReorderItem]) -> some View {
        QFlowLayout() {
            ForEach(allItems) { item in
                let isUsed: Bool = chosen.contains(item.id)
                Button {
                    add(item.id, allItems: allItems)
                } label: {
                    Text(item.text)
                }
                .buttonStyle(QChipButtonStyle())
                .disabled(isUsed)
                .opacity(isUsed ? 0.25 : 1)
                .accessibilityHidden(isUsed)
                .accessibilityHint("Ajoute ce mot à ta phrase")
            }
        }
    }

    private func add(_ id: Int, allItems: [ReorderItem]) {
        guard !chosen.contains(id) else { return }
        chosen.append(id)
        publish(allItems)
    }

    private func remove(_ id: Int, allItems: [ReorderItem]) {
        chosen.removeAll { $0 == id }
        publish(allItems)
    }

    private func publish(_ allItems: [ReorderItem]) {
        guard chosen.count == allItems.count else {
            answer = nil
            return
        }
        var words: [String] = []
        for id in chosen {
            if let item = allItems.first(where: { $0.id == id }) {
                words.append(item.text)
            }
        }
        answer = .ordering(words)
    }
}

// MARK: - Match (tap a left item, then its right item; tap again to unpair)

private struct MatchRightItem: Identifiable {
    /// Index of the pair this right-hand text belongs to.
    let id: Int
    let text: String
}

struct ExerciseMatchInput: View {
    let exercise: Exercise
    @Binding var answer: AnswerSubmission?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedLeft: Int?
    /// Left index -> right id.
    @State private var paired: [Int: Int] = [:]

    init(exercise: Exercise, answer: Binding<AnswerSubmission?>) {
        self.exercise = exercise
        self._answer = answer
    }

    private var pairs: [MatchPair] { exercise.pairs ?? [] }

    private var rightItems: [MatchRightItem] {
        let base: [MatchRightItem] = pairs.enumerated().map { MatchRightItem(id: $0.offset, text: $0.element.right) }
        var shuffled: [MatchRightItem] = base.stableShuffled(seed: exercise.id)
        // Never present the pairs already aligned.
        if shuffled.count > 1, shuffled.map({ $0.id }) == base.map({ $0.id }) {
            shuffled.append(shuffled.removeFirst())
        }
        return shuffled
    }

    var body: some View {
        let rights: [MatchRightItem] = rightItems
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    leftColumn
                    rightColumn(rights)
                }
            } else {
                HStack(alignment: .top, spacing: Theme.Spacing.m) {
                    leftColumn
                    rightColumn(rights)
                }
            }
        }
    }

    // MARK: Columns

    private var leftColumn: some View {
        VStack(spacing: Theme.Spacing.s) {
            ForEach(Array(pairs.enumerated()), id: \.offset) { index, pair in
                leftButton(index: index, text: pair.left)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func rightColumn(_ rights: [MatchRightItem]) -> some View {
        VStack(spacing: Theme.Spacing.s) {
            ForEach(rights) { item in
                rightButton(item)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func leftButton(index: Int, text: String) -> some View {
        let isSelected: Bool = selectedLeft == index
        let rightId: Int? = paired[index]
        let isPaired: Bool = rightId != nil
        let badge: MatchBadgeStyle = isSelected ? .selected : (isPaired ? .paired : .idle)
        return Button {
            tapLeft(index)
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                numberBadge(index + 1, style: badge)
                Text(text)
                    .font(Theme.Font.callout(.semibold))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(isSelected ? Theme.onInk : Theme.ink)
            .modifier(MatchCellStyle(isInk: isSelected))
        }
        .buttonStyle(.press)
        .accessibilityLabel("\(index + 1). \(text)")
        .accessibilityValue(leftValue(isSelected: isSelected, rightId: rightId))
        .accessibilityHint(isPaired ? "Touche pour défaire l'association" : "Choisis ce mot, puis sa traduction")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func rightButton(_ item: MatchRightItem) -> some View {
        let owner: Int? = paired.first(where: { $0.value == item.id })?.key
        let isPaired: Bool = owner != nil
        return Button {
            tapRight(item.id)
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                if let owner {
                    numberBadge(owner + 1, style: .paired)
                }
                Text(item.text)
                    .font(Theme.Font.callout(.semibold))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(Theme.ink)
            .modifier(MatchCellStyle(isInk: false))
        }
        .buttonStyle(.press)
        .accessibilityLabel(item.text)
        .accessibilityValue(owner.map { "associé au numéro \($0 + 1)" } ?? "pas encore associé")
        .accessibilityHint(rightHint(isPaired: isPaired))
    }

    // MARK: Cell styling

    /// Number disc: light when idle, white on the ink capsule when selected, ink once paired.
    private func numberBadge(_ number: Int, style: MatchBadgeStyle) -> some View {
        let fillColor: Color
        let textColor: Color
        switch style {
        case .idle:
            fillColor = Theme.background
            textColor = Theme.tertiaryText
        case .selected:
            fillColor = Theme.onInk
            textColor = Theme.ink
        case .paired:
            fillColor = Theme.ink
            textColor = Theme.onInk
        }
        return Text("\(number)")
            .font(Theme.Font.caption(.bold).monospacedDigit())
            .foregroundStyle(textColor)
            .frame(minWidth: 26, minHeight: 26)
            .padding(.horizontal, 2)
            .background(Capsule().fill(fillColor))
            .accessibilityHidden(true)
    }

    private func leftValue(isSelected: Bool, rightId: Int?) -> String {
        if let rightId, rightId < pairs.count {
            return "associé à \(pairs[rightId].right)"
        }
        return isSelected ? "sélectionné" : "pas encore associé"
    }

    private func rightHint(isPaired: Bool) -> String {
        if selectedLeft != nil { return "Associe ce mot à celui que tu as choisi" }
        if isPaired { return "Touche pour défaire l'association" }
        return "Choisis d'abord un mot dans la première liste"
    }

    // MARK: Interaction

    private func tapLeft(_ index: Int) {
        if paired[index] != nil {
            paired[index] = nil
            selectedLeft = index
        } else {
            selectedLeft = (selectedLeft == index) ? nil : index
        }
        publish()
    }

    private func tapRight(_ rightId: Int) {
        let owner: Int? = paired.first(where: { $0.value == rightId })?.key
        if let left = selectedLeft {
            if let owner { paired[owner] = nil }
            paired[left] = rightId
            selectedLeft = nil
        } else if let owner {
            paired[owner] = nil
        }
        publish()
    }

    private func publish() {
        guard !pairs.isEmpty, paired.count == pairs.count else {
            answer = nil
            return
        }
        var result: [MatchPair] = []
        for index in pairs.indices {
            guard let rightId = paired[index], rightId < pairs.count else {
                answer = nil
                return
            }
            result.append(MatchPair(left: pairs[index].left, right: pairs[rightId].right))
        }
        answer = .matches(result)
    }
}

// MARK: - Match cell helpers

private enum MatchBadgeStyle {
    case idle, selected, paired
}

/// White capsule cell (ink when selected), no border.
private struct MatchCellStyle: ViewModifier {
    let isInk: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, Theme.Spacing.m - 2)
            .padding(.vertical, Theme.Spacing.s)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(Capsule().fill(isInk ? Theme.ink : Theme.surface))
            .contentShape(Capsule())
    }
}
