import SwiftUI
import SheafnoteCore

struct StudySessionView: View {
    @State var model: StudySessionModel
    var onFinish: () -> Void = {}
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let card = model.current {
                cardView(card)
            } else {
                finished
            }
        }
        .background(Theme.paper)
        .navigationTitle(Text("Study", tableName: "AudioStudy"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func cardView(_ card: Flashcard) -> some View {
        VStack(spacing: 16) {
            ProgressView(value: Double(model.index), total: Double(max(model.total, 1)))
                .tint(Theme.accent)
                .accessibilityLabel(Text("Progress", tableName: "AudioStudy"))
                .accessibilityValue(Text("\(model.index) of \(model.total)", tableName: "AudioStudy"))
            Text("Card \(model.index + 1) of \(model.total)", tableName: "AudioStudy")
                .font(.footnote).foregroundStyle(Theme.inkMuted)
            ScrollView {
                VStack(spacing: 12) {
                    CardFace(data: card.frontImage, label: Text("Front", tableName: "AudioStudy"))
                        .accessibilityIdentifier("study.front")
                    if model.isRevealed {
                        Theme.rule.frame(height: 1)
                        CardFace(data: card.backImage, label: Text("Back", tableName: "AudioStudy"))
                            .accessibilityIdentifier("study.back")
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .paperCard(shadow: true)
                .padding(.vertical, 8)
                .padding(.horizontal, 2)
            }
            if let error = model.errorMessage {
                Text(error).font(.footnote).foregroundStyle(.red).accessibilityIdentifier("study.error")
            }
            controls
        }
        .padding()
    }

    @ViewBuilder
    private var controls: some View {
        if model.isRevealed {
            let intervals = model.nextIntervals
            HStack(spacing: 10) {
                gradeButton("Again", .again, intervals: intervals, tint: Theme.bubblegum, id: "again")
                gradeButton("Hard", .hard, intervals: intervals, tint: Theme.sunflower, id: "hard")
                gradeButton("Good", .good, intervals: intervals, tint: Theme.mint, id: "good")
                gradeButton("Easy", .easy, intervals: intervals, tint: Theme.sky, id: "easy")
            }
        } else {
            Button { model.reveal() } label: {
                Text("Show answer", tableName: "AudioStudy").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .controlSize(.large)
            .accessibilityIdentifier("study.reveal")
        }
    }

    private func gradeButton(_ key: LocalizedStringKey, _ grade: SM2Grade, intervals: [SM2Grade: String],
                             tint: Color, id: String) -> some View {
        Button {
            Haptics.light()
            model.grade(grade)
        } label: {
            VStack(spacing: 2) {
                Text(key, tableName: "AudioStudy").font(.headline)
                if let label = intervals[grade] { Text(label).font(.caption2) }
            }
            // Pastel fills need dark text in both modes.
            .foregroundStyle(colorScheme == .dark ? Theme.paper : Theme.ink)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .controlSize(.large)
        .accessibilityIdentifier("study.grade.\(id)")
    }

    private var finished: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal").font(.system(size: 52)).foregroundStyle(Theme.mint)
            Text(model.total == 0 ? "Nothing is due" : "All caught up", tableName: "AudioStudy").font(Theme.title(.title2))
                .foregroundStyle(Theme.ink)
            if model.reviewed > 0 {
                Text("Reviewed \(model.reviewed) cards, \(model.againCount) to see again tomorrow.", tableName: "AudioStudy")
                    .foregroundStyle(Theme.inkMuted)
            }
            Button { onFinish() } label: { Text("Done", tableName: "AudioStudy") }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .accessibilityIdentifier("study.done")
        }
        .padding()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("study.finished")
    }
}

struct CardFace: View {
    let data: Data
    let label: Text

    var body: some View {
        Group {
            if let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit()
                    .background(Color.white, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            } else {
                Text("This side of the card could not be shown.", tableName: "AudioStudy").foregroundStyle(Theme.inkMuted)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityHint(Text("Handwritten card image", tableName: "AudioStudy"))
    }
}
