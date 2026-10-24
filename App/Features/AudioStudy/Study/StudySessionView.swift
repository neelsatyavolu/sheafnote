import SwiftUI
import SheafnoteCore

struct StudySessionView: View {
    @State var model: StudySessionModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let card = model.current {
                cardView(card)
            } else {
                finished
            }
        }
        .navigationTitle(Text("Study", tableName: "AudioStudy"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("study.session")
    }

    private func cardView(_ card: Flashcard) -> some View {
        VStack(spacing: 16) {
            ProgressView(value: Double(model.index), total: Double(max(model.total, 1)))
                .accessibilityLabel(Text("Progress", tableName: "AudioStudy"))
                .accessibilityValue(Text("\(model.index) of \(model.total)", tableName: "AudioStudy"))
            Text("Card \(model.index + 1) of \(model.total)", tableName: "AudioStudy")
                .font(.footnote).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 12) {
                    CardFace(data: card.frontImage, label: Text("Front", tableName: "AudioStudy"))
                        .accessibilityIdentifier("study.front")
                    if model.isRevealed {
                        Divider()
                        CardFace(data: card.backImage, label: Text("Back", tableName: "AudioStudy"))
                            .accessibilityIdentifier("study.back")
                    }
                }
                .padding(.vertical, 4)
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
                gradeButton("Again", .again, intervals: intervals, tint: .red, id: "again")
                gradeButton("Hard", .hard, intervals: intervals, tint: .orange, id: "hard")
                gradeButton("Good", .good, intervals: intervals, tint: .green, id: "good")
                gradeButton("Easy", .easy, intervals: intervals, tint: .blue, id: "easy")
            }
        } else {
            Button { model.reveal() } label: {
                Text("Show answer", tableName: "AudioStudy").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("study.reveal")
        }
    }

    private func gradeButton(_ key: LocalizedStringKey, _ grade: SM2Grade, intervals: [SM2Grade: String],
                             tint: Color, id: String) -> some View {
        Button { model.grade(grade) } label: {
            VStack(spacing: 2) {
                Text(key, tableName: "AudioStudy").font(.headline)
                if let label = intervals[grade] { Text(label).font(.caption2) }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(tint)
        .controlSize(.large)
        .accessibilityIdentifier("study.grade.\(id)")
    }

    private var finished: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal").font(.system(size: 52)).foregroundStyle(.green)
            Text(model.total == 0 ? "Nothing is due" : "All caught up", tableName: "AudioStudy").font(.title2.bold())
            if model.reviewed > 0 {
                Text("Reviewed \(model.reviewed) cards, \(model.againCount) to see again tomorrow.", tableName: "AudioStudy")
                    .foregroundStyle(.secondary)
            }
            Button { dismiss() } label: { Text("Done", tableName: "AudioStudy") }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("study.done")
        }
        .padding()
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
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
            } else {
                Text("This side of the card could not be shown.", tableName: "AudioStudy").foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityHint(Text("Handwritten card image", tableName: "AudioStudy"))
    }
}
