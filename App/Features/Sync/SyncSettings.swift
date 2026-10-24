import SwiftUI
import SheafnoteCore

enum SyncSettings {
    /// "iCloud sync", order 20 in Settings.
    @MainActor
    static func section(controller: SyncController) -> SettingsSection {
        SettingsSection(id: "sync", order: 20, title: LocalizedStringResource("iCloud Sync", table: "Sync"), symbolName: "icloud") { services in
            AnyView(SyncSettingsContent(controller: controller, services: services))
        }
    }
}

private struct SyncSettingsContent: View {
    let controller: SyncController
    let services: AppServices
    @State private var recoveredCount = 0
    @State private var loadError: String?

    private var presentation: SyncStatusPresentation { SyncStatusPresentation(status: controller.status) }

    var body: some View {
        statusSection
        if controller.awaitingAccountDecision { accountSwitchSection }
        recoveredSection
        accountSection
    }

    private var statusSection: some View {
        Section {
            Toggle(isOn: Binding(get: { controller.isEnabled }, set: { on in Task { await controller.setEnabled(on) } })) {
                Text("iCloud Sync", tableName: "Sync")
            }
            .accessibilityIdentifier("sync.toggle")
            LabeledContent {
                Text(presentation.title).foregroundStyle(presentation.needsAttention ? Color.orange : Color.secondary)
            } label: {
                Label { Text("Status", tableName: "Sync") } icon: { Image(systemName: presentation.symbolName) }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("sync.status")
            if controller.isEnabled, controller.status != .syncing, case .error = controller.status { errorDetail }
            if let problem = controller.settingsProblem {
                Text(problem).font(.footnote).foregroundStyle(.orange)
            }
            if let last = controller.lastSyncDate {
                LabeledContent(String(localized: "Last Synced", table: "Sync")) { Text(last, format: .dateTime.day().month().hour().minute()) }
            }
            Button { Task { await controller.syncNow() } } label: { Text("Sync Now", tableName: "Sync") }
                .disabled(!controller.isEnabled || controller.status == .syncing)
                .accessibilityIdentifier("sync.syncNow")
        } footer: {
            Text("Notebooks, folders and pages sync between your devices through your own iCloud. With sync off, everything stays on this device. Sheafnote has no server of its own.", tableName: "Sync")
        }
    }

    private var errorDetail: some View {
        Text(presentation.detail).font(.footnote).foregroundStyle(.secondary)
    }

    private var accountSwitchSection: some View {
        Section {
            Text("You signed in to a different iCloud account. Upload this device's notebooks to it? Nothing on this device is deleted either way.", tableName: "Sync")
            Button { Task { await controller.resolveAccountSwitch(upload: true) } } label: { Text("Upload to New Account", tableName: "Sync") }
                .accessibilityIdentifier("sync.accountSwitch.upload")
            Button { Task { await controller.resolveAccountSwitch(upload: false) } } label: { Text("Keep on This Device Only", tableName: "Sync") }
                .accessibilityIdentifier("sync.accountSwitch.keepLocal")
        }
    }

    private var recoveredSection: some View {
        Section {
            NavigationLink {
                RecoveredPagesView(services: services)
            } label: {
                LabeledContent(String(localized: "Recovered Pages", table: "Sync"), value: recoveredCount.formatted())
            }
            .accessibilityIdentifier("sync.recovered")
        } footer: {
            Text("When two devices change the same page at once, Sheafnote merges the ink. If it can't, it keeps both versions here for 30 days so nothing is lost.", tableName: "Sync")
        }
        .task { reloadCount() }
        .alert(Text("Couldn't Load Recovered Pages", tableName: "Sync"), isPresented: Binding(get: { loadError != nil }, set: { if !$0 { loadError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(loadError ?? "") }
    }

    private var accountSection: some View {
        Section {
            Label { Text("If you sign out of iCloud, your notebooks stay on this device and sync resumes when you sign back in.", tableName: "Sync") } icon: { Image(systemName: "person.crop.circle.badge.minus") }
            Label { Text("If you switch to another iCloud account, Sheafnote asks before uploading this device's notebooks to it. Nothing is deleted.", tableName: "Sync") } icon: { Image(systemName: "arrow.left.arrow.right") }
            Label { Text("Deleted notebooks stay in Recently Deleted for 30 days on every device before they are removed from iCloud.", tableName: "Sync") } icon: { Image(systemName: "trash") }
        } header: {
            Text("Good to Know", tableName: "Sync")
        }
    }

    private func reloadCount() {
        do { recoveredCount = try RecoveredArea(context: services.context).items().count } catch { loadError = error.localizedDescription }
    }
}
