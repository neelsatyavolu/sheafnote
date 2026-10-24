import SwiftUI
import SheafnoteCore

/// Audio recording with stroke-linked playback, flashcards and spaced-repetition study.
enum AudioStudyFeature: FeatureModule {
    static let id = "audio-study"

    static func register(into host: FeatureHost) {
        host.tools.register(PlaybackTool())
        host.settings.register(AudioSettings.section)
        registerNotebookMenus(into: host.notebookMenu)
        host.selectionActions.register(MakeFlashcardAction())
    }

    private static func registerNotebookMenus(into menu: NotebookMenuRegistry) {
        let paged: Set<NotebookKind> = [.paged, .whiteboard]
        menu.registerBarItem(EditorBarItem(id: "audio.bar", slot: .trailing(order: 40), kinds: paged) { editor in
            AnyView(AudioBarButton(editor: editor))
        })
        menu.registerMenuItem(NotebookMenuItem(
            id: "audio.record", group: .tools, order: 10, kinds: paged,
            title: LocalizedStringResource("Record audio", table: "AudioStudy"), symbolName: "record.circle",
            isEnabled: { _ in true }, perform: { editor in presentAudioSheet(in: editor) }))
        menu.registerPageMenuItem(PageMenuItem(
            id: "audio.flashcards", order: 50, title: LocalizedStringResource("Make flashcards", table: "AudioStudy"),
            symbolName: "rectangle.on.rectangle.angled") { pageIDs, editor in
                guard let first = pageIDs.first else { return }
                presentCardMaker(pageID: first, selection: nil, in: editor)
            })
        menu.registerNavigatorTab(NavigatorTab(
            id: "audio.flashcards", order: 60, title: LocalizedStringResource("Flashcards", table: "AudioStudy"),
            symbolName: "rectangle.stack") { editor in AnyView(FlashcardsTab(editor: editor)) })
    }

    @MainActor
    static func presentAudioSheet(in editor: any EditorContext) {
        let session = AudioStudyHub.shared.session(for: editor)
        editor.present(EditorSheet(detents: [.medium, .large]) { AnyView(AudioSheet(session: session)) })
    }

    @MainActor
    static func presentCardMaker(pageID: UUID, selection: CGRect?, in editor: any EditorContext) {
        let services = editor.services
        guard let size = services.pages.page(id: pageID)?.size, size.width > 0, size.height > 0 else {
            editor.showToast(LocalizedStringResource("That page could not be found.", table: "AudioStudy"))
            return
        }
        let store = AudioStudyHub.shared.session(for: editor).study
        let decks = ((try? store.decks(in: editor.notebook.id)) ?? []).map(\.name)
        let maker = FlashcardMaker(editor: editor, pageID: pageID, pageSize: size, selection: selection,
                                   deck: decks.first ?? StudyStore.defaultDeck)
        editor.present(EditorSheet(detents: [.large]) { AnyView(MakeFlashcardSheet(maker: maker, decks: decks)) })
    }
}

/// Lasso selection -> "Make flashcard": the selection becomes the front, the back is picked in the card maker.
@MainActor
final class MakeFlashcardAction: SelectionAction {
    let id = "audio.makeFlashcard"
    let title = LocalizedStringResource("Make flashcard", table: "AudioStudy")
    let symbolName = "rectangle.on.rectangle.angled"
    let order = 80

    func isEnabled(for selection: SelectionModel, editor: EditorContext) -> Bool {
        selection.pageID != nil && selection.bounds != nil
    }

    func perform(selection: SelectionModel, page: any PageContext, editor: EditorContext) async throws {
        AudioStudyFeature.presentCardMaker(pageID: page.pageID, selection: selection.bounds, in: editor)
    }
}
