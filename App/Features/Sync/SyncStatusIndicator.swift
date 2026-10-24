import SwiftUI
import SheafnoteCore

/// Small iCloud status button for the library toolbar. Tapping shows the status and a "Sync Now" action.
/// It also asks the account-switch question, since that can come up while the library is on screen.
struct SyncStatusIndicator: View {
    @State private var isShowingDetail = false

    var body: some View {
        if let controller = SyncController.shared {
            IndicatorBody(controller: controller, isShowingDetail: $isShowingDetail)
        }
    }
}

private struct IndicatorBody: View {
    let controller: SyncController
    @Binding var isShowingDetail: Bool

    private var presentation: SyncStatusPresentation { SyncStatusPresentation(status: controller.status) }

    var body: some View {
        Button { isShowingDetail = true } label: {
            Image(systemName: presentation.symbolName)
                .symbolEffect(.pulse, isActive: controller.status == .syncing)
                .foregroundStyle(presentation.needsAttention ? Theme.accent : Theme.inkMuted)
        }
        .accessibilityLabel(Text("iCloud sync status", tableName: "Sync"))
        .accessibilityValue(Text(presentation.title))
        .accessibilityIdentifier("library.syncStatus")
        .popover(isPresented: $isShowingDetail) { detail.presentationCompactAdaptation(.popover) }
        .alert(Text("Upload to the new iCloud account?", tableName: "Sync"),
               isPresented: .constant(controller.awaitingAccountDecision && !isShowingDetail)) {
            Button(String(localized: "Upload", table: "Sync")) { Task { await controller.resolveAccountSwitch(upload: true) } }
            Button(String(localized: "Keep on This Device Only", table: "Sync"), role: .cancel) {
                Task { await controller.resolveAccountSwitch(upload: false) }
            }
        } message: {
            Text("You signed in to a different iCloud account. Upload this device's notebooks to it? Nothing on this device is deleted either way.", tableName: "Sync")
        }
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(presentation.title, systemImage: presentation.symbolName).font(Theme.title(.headline)).foregroundStyle(Theme.ink)
            Text(presentation.detail).font(.subheadline).foregroundStyle(Theme.inkMuted)
            if let last = controller.lastSyncDate {
                Text("Last synced \(last.formatted(.relative(presentation: .named)))", tableName: "Sync")
                    .font(.footnote).foregroundStyle(Theme.inkMuted)
            }
            if controller.isEnabled {
                Button(String(localized: "Sync Now", table: "Sync")) { Task { await controller.syncNow() } }
                    .buttonStyle(.bordered)
                    .disabled(controller.status == .syncing)
                    .accessibilityIdentifier("library.syncNow")
            }
        }
        .padding()
        .frame(minWidth: 260, maxWidth: 360, alignment: .leading)
        .background(Theme.paperRaised)
    }
}
