/// Names every feature module. Foundation-owned and final: units never edit this file.
@MainActor
enum FeatureModules {
    static let all: [any FeatureModule.Type] = [
        EditorFeature.self, SyncFeature.self, PdfIOFeature.self, InkToolsFeature.self,
        ElementsFeature.self, SearchFeature.self, PresentFeature.self,
        AudioStudyFeature.self, DocTypesFeature.self,
    ]
}
