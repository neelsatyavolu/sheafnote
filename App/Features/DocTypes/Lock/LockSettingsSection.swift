import SheafnoteCore
import SwiftUI

enum LockSettingsSection {
    static let section = SettingsSection(
        id: "appLock", order: 50, title: LocalizedStringResource("App Lock", table: "DocTypes"), symbolName: "lock"
    ) { _ in AnyView(LockSettingsContent()) }
}

private struct LockSettingsContent: View {
    @State private var controller = AppLockController.shared
    @State private var errorMessage: String?

    private var enabled: Binding<Bool> {
        Binding(get: { controller.settings.isEnabled },
                set: { new in Task { errorMessage = await controller.setEnabled(new) } })
    }

    private var grace: Binding<LockGrace> {
        Binding(get: { controller.settings.grace }, set: { controller.setGrace($0) })
    }

    var body: some View {
        Section {
            Toggle(isOn: enabled) { Text("Require Face ID, Touch ID or Passcode", tableName: "DocTypes") }
                .accessibilityIdentifier("appLock.toggle")
            if controller.settings.isEnabled {
                Picker(selection: grace) {
                    ForEach(LockGrace.allCases, id: \.self) { Text($0.title).tag($0) }
                } label: { Text("Lock After Leaving", tableName: "DocTypes") }
                .accessibilityIdentifier("appLock.grace")
            }
        } header: {
            Text("App Lock", tableName: "DocTypes").paperHeader()
        } footer: {
            Text("Sheafnote asks for Face ID, Touch ID or your device passcode when you open it, and hides its contents in the app switcher. To lock a single notebook, touch and hold it in the library and choose Lock. Locks only control who can open the app on this device; your notes and iCloud sync are not changed.", tableName: "DocTypes")
        }
        .alert(Text("App Lock", tableName: "DocTypes"),
               isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button(role: .cancel) {} label: { Text("OK", tableName: "DocTypes") }
        } message: { Text(errorMessage ?? "") }
    }
}

extension LockGrace {
    var title: LocalizedStringResource {
        switch self {
        case .immediately: LocalizedStringResource("Immediately", table: "DocTypes")
        case .oneMinute: LocalizedStringResource("After 1 minute", table: "DocTypes")
        case .fiveMinutes: LocalizedStringResource("After 5 minutes", table: "DocTypes")
        case .fifteenMinutes: LocalizedStringResource("After 15 minutes", table: "DocTypes")
        }
    }
}
