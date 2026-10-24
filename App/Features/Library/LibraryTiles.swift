import SwiftUI
import SheafnoteCore

/// One notebook or folder in the grid or list. Selection state is drawn here; behavior lives in the content view.
struct LibraryTile: View {
    let entry: LibraryEntry
    let childCount: Int
    let isSelecting: Bool
    let isSelected: Bool
    let deletedDaysLeft: Int?

    var body: some View {
        VStack(spacing: 8) {
            art.overlay(alignment: .bottomTrailing) { if isSelecting { SelectionBadge(isSelected: isSelected) } }
                .overlay(alignment: .topTrailing) { if entry.isFavorite && deletedDaysLeft == nil { FavoriteBadge() } }
            VStack(spacing: 2) {
                Text(entry.title).font(.subheadline.weight(.medium)).lineLimit(2).multilineTextAlignment(.center)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("item.\(entry.title)")
    }

    @ViewBuilder private var art: some View {
        switch entry {
        case .notebook(let n):
            NotebookCoverView(cover: n.cover)
        case .folder:
            FolderArt().aspectRatio(3.0 / 4.0, contentMode: .fit)
        }
    }

    private var subtitle: String {
        if let days = deletedDaysLeft { return String(localized: "\(days) days left") }
        switch entry {
        case .folder: return String(localized: "\(childCount) items")
        case .notebook(let n): return n.modifiedAt.formatted(.dateTime.month(.abbreviated).day().year())
        }
    }

    private var accessibilityLabel: String {
        let kind = { if case .folder = entry { String(localized: "Folder") } else { String(localized: "Notebook") } }()
        let fav = entry.isFavorite ? String(localized: ", favorite") : ""
        return "\(entry.title), \(kind)\(fav), \(subtitle)"
    }
}

struct FolderArt: View {
    var body: some View {
        Image(systemName: "folder.fill")
            .resizable().scaledToFit()
            .foregroundStyle(.tint.opacity(0.85))
            .padding(.horizontal, 6)
            .accessibilityHidden(true)
    }
}

struct SelectionBadge: View {
    let isSelected: Bool

    var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title2)
            .symbolRenderingMode(.palette)
            .foregroundStyle(isSelected ? Color.white : Color.secondary, isSelected ? Color.accentColor : Color.clear)
            .background(Circle().fill(.thinMaterial))
            .padding(6)
            .accessibilityHidden(true)
    }
}

struct FavoriteBadge: View {
    var body: some View {
        Image(systemName: "star.fill")
            .font(.caption.bold())
            .foregroundStyle(.yellow)
            .padding(5)
            .background(Circle().fill(.thinMaterial))
            .padding(4)
            .accessibilityHidden(true)
    }
}

/// List-layout row.
struct LibraryRow: View {
    let entry: LibraryEntry
    let childCount: Int
    let isSelecting: Bool
    let isSelected: Bool
    let deletedDaysLeft: Int?

    var body: some View {
        HStack(spacing: 12) {
            if isSelecting { SelectionBadge(isSelected: isSelected).padding(0) }
            thumbnail.frame(width: 44, height: 58)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font(.body).lineLimit(2)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if entry.isFavorite && deletedDaysLeft == nil {
                Image(systemName: "star.fill").foregroundStyle(.yellow).accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(entry.title), \(subtitle)"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("item.\(entry.title)")
    }

    @ViewBuilder private var thumbnail: some View {
        switch entry {
        case .notebook(let n): CoverArtView(definition: n.cover.definition).clipShape(RoundedRectangle(cornerRadius: 3))
        case .folder: FolderArt()
        }
    }

    private var subtitle: String {
        if let days = deletedDaysLeft { return String(localized: "\(days) days left") }
        switch entry {
        case .folder: return String(localized: "\(childCount) items")
        case .notebook(let n): return n.modifiedAt.formatted(.dateTime.month(.abbreviated).day().year())
        }
    }
}
