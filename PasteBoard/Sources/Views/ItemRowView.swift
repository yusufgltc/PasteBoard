import SwiftUI
import AppKit

// MARK: - Instant-click + context-menu NSView overlay

/// Transparent `NSView` overlay that handles both instant `mouseDown` selection
/// and a right-click context menu (Paste / Copy / Delete).
///
/// `hitTest` behaviour differs by button:
/// - Left-click on the rightmost 56 pt: returns `nil` so the copy `Button` in
///   `NSHostingView` receives the event normally.
/// - Right-click anywhere: returns `self` so the context menu appears over the
///   full row width.
private final class RowInteractionNSView: NSView {
    weak var coordinator: RowInteraction.Coordinator?

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            coordinator?.onDoubleClick?()
        } else {
            coordinator?.onSingleClick?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let coordinator else { return }

        let menu = NSMenu()

        let pasteItem = NSMenuItem(title: "Paste",
                                   action: #selector(RowInteraction.Coordinator.paste),
                                   keyEquivalent: "")
        pasteItem.image  = NSImage(systemSymbolName: "arrow.turn.up.left",
                                   accessibilityDescription: nil)
        pasteItem.target = coordinator
        menu.addItem(pasteItem)

        let copyItem = NSMenuItem(title: "Copy",
                                  action: #selector(RowInteraction.Coordinator.copyItem),
                                  keyEquivalent: "")
        copyItem.image  = NSImage(systemSymbolName: "doc.on.doc",
                                  accessibilityDescription: nil)
        copyItem.target = coordinator
        menu.addItem(copyItem)

        let deleteItem = NSMenuItem(title: "Delete",
                                    action: #selector(RowInteraction.Coordinator.delete),
                                    keyEquivalent: "")
        deleteItem.image  = NSImage(systemSymbolName: "trash",
                                    accessibilityDescription: nil)
        deleteItem.target = coordinator
        menu.addItem(deleteItem)

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Right-click: cover the full row so the context menu is reachable everywhere.
        if let event = NSApp.currentEvent, event.type == .rightMouseDown {
            return super.hitTest(point)
        }
        // Left-click: pass through to NSHostingView for the copy button area.
        guard point.x < bounds.width - 56 else { return nil }
        return super.hitTest(point)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { false }
}

// MARK: - NSViewRepresentable wrapper

private struct RowInteraction: NSViewRepresentable {
    let onSingleClick: () -> Void
    let onDoubleClick: () -> Void
    let onPaste:       () -> Void
    let onCopy:        () -> Void
    let onDelete:      () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> RowInteractionNSView {
        let interactionView = RowInteractionNSView()
        interactionView.coordinator = context.coordinator
        return interactionView
    }

    func updateNSView(_ v: RowInteractionNSView, context: Context) {
        context.coordinator.onSingleClick = onSingleClick
        context.coordinator.onDoubleClick = onDoubleClick
        context.coordinator.onPaste       = onPaste
        context.coordinator.onCopy        = onCopy
        context.coordinator.onDelete      = onDelete
    }

    final class Coordinator: NSObject {
        var onSingleClick: (() -> Void)?
        var onDoubleClick: (() -> Void)?
        var onPaste:       (() -> Void)?
        var onCopy:        (() -> Void)?
        var onDelete:      (() -> Void)?

        @objc func paste()     { onPaste?()  }
        @objc func copyItem()  { onCopy?()   }
        @objc func delete()    { onDelete?() }
    }
}

// MARK: - App icon cache

/// Process-wide cache for source-app icons loaded from `NSWorkspace`.
/// Keyed by bundle identifier to avoid redundant disk reads on every render pass.
private enum AppIconCache {
    private static var cache: [String: NSImage] = [:]
    static func icon(for bundleID: String) -> NSImage? {
        if let hit = cache[bundleID] { return hit }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let appIcon = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = appIcon
        return appIcon
    }
}

// MARK: - Row view

/// A single row in the clipboard history list.
///
/// Visual states:
/// - **Focused** (`isFocused == true`): accent-colour background — the item is
///   selected via keyboard and its title is shown in the search-bar chip.
/// - **Selected** (`isSelected == true`, not focused): system gray
///   (`unemphasizedSelectedContentBackgroundColor`).
/// - **Hovered**: subtle `primary.opacity(0.06)` tint.
///
/// Right-clicking anywhere on the row shows a context menu: Paste / Copy / Delete.
struct ItemRowView: View {
    let item:       ClipboardItem
    let store:      ClipboardStore
    let isSelected: Bool
    let isFocused:  Bool
    let onCopy:     () -> Void
    let onSelect:   () -> Void
    let onPaste:    () -> Void
    let onDelete:   () -> Void

    @State private var showCopied = false
    @State private var isHovered  = false

    var body: some View {
        HStack(spacing: 12) {
            iconStack.frame(width: 50, height: 50)
            textStack.frame(maxWidth: .infinity, alignment: .leading)
            copyButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onHover { isHovered = $0 }
        .overlay(
            RowInteraction(
                onSingleClick: onSelect,
                onDoubleClick: onPaste,
                onPaste:       onPaste,
                onCopy:        onCopy,
                onDelete:      onDelete
            )
        )
    }

    // MARK: - Icon

    private var iconStack: some View {
        ZStack(alignment: .bottomTrailing) {
            contentIcon
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 9))

            if let badge = sourceAppIcon {
                Image(nsImage: badge)
                    .resizable()
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 4.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4.5)
                            .strokeBorder(Color(nsColor: .windowBackgroundColor).opacity(0.85), lineWidth: 1.5)
                    )
                    .offset(x: 7, y: 7)
            }
        }
    }

    @ViewBuilder
    private var contentIcon: some View {
        switch item.type {
        case .text:
            ZStack {
                LinearGradient(colors: [.blue.opacity(0.14), .blue.opacity(0.05)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "doc.text")
                    .font(.system(size: 20, weight: .light))
                    .foregroundColor(.blue.opacity(0.85))
            }
        case .image:
            ZStack {
                LinearGradient(colors: [.purple.opacity(0.14), .purple.opacity(0.05)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "photo")
                    .font(.system(size: 20, weight: .light))
                    .foregroundColor(.purple.opacity(0.85))
            }
        case .url:
            ZStack {
                LinearGradient(colors: [.green.opacity(0.14), .green.opacity(0.05)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "link")
                    .font(.system(size: 20, weight: .light))
                    .foregroundColor(.green.opacity(0.85))
            }
        case .file:
            ZStack {
                LinearGradient(colors: [.orange.opacity(0.14), .orange.opacity(0.05)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "doc")
                    .font(.system(size: 20, weight: .light))
                    .foregroundColor(.orange.opacity(0.85))
            }
        }
    }

    // MARK: - Text

    private var textStack: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.displayTitle)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(2)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)

            Text(subtitle)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: - Copy button

    private var copyButton: some View {
        Button {
            onCopy()
            withAnimation(.easeInOut(duration: 0.12)) { showCopied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                withAnimation(.easeInOut(duration: 0.2)) { showCopied = false }
            }
        } label: {
            Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 13))
                .foregroundColor(showCopied ? .green : .secondary.opacity(0.6))
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity((isSelected || isFocused) ? 0.6 : 0.0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private static let unfocusedSelectionBG = Color(nsColor: .unemphasizedSelectedContentBackgroundColor)

    private var rowBackground: AnyShapeStyle {
        if isFocused  { return AnyShapeStyle(Color.accentColor.opacity(0.15)) }
        if isSelected { return AnyShapeStyle(Self.unfocusedSelectionBG) }
        if isHovered  { return AnyShapeStyle(Color.primary.opacity(0.06)) }
        return AnyShapeStyle(Color.clear)
    }

    private var sourceAppIcon: NSImage? {
        guard let id = item.sourceAppBundleID else { return nil }
        return AppIconCache.icon(for: id)
    }

    private var subtitle: String {
        "\(item.typeLabel) · Copied \(copiedTime(item.timestamp))"
    }
}

/// Equatable conformance lets SwiftUI skip re-rendering rows whose inputs haven't changed.
/// Closures are deliberately excluded — they don't affect the rendered output.
extension ItemRowView: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.item == rhs.item &&
        lhs.isSelected == rhs.isSelected &&
        lhs.isFocused == rhs.isFocused
    }
}
