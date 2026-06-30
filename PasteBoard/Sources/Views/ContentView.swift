import SwiftUI
import AppKit

/// Root view of the floating clipboard-history panel.
///
/// Composed of two sections:
/// - **Search bar** — a styled `TextField` that filters ``ContentViewModel/filteredItems``.
///   When an item is selected (Tab / arrow key) the field is replaced by a title chip
///   showing the item's name and "– Paste" in muted text.
/// - **Item list** — a `ScrollView` containing a `LazyVStack` of ``ItemRowView``s.
///   Each row uses `.equatable()` so only rows whose `item`/`isSelected`/`isFocused`
///   state changed are re-rendered.
///
/// Panel enter/exit animations are driven by `panelScale` and `panelOpacity` on
/// ``ContentViewModel``, which ``PanelController`` animates via `withAnimation {}`.
struct ContentView: View {
    @ObservedObject var viewModel: ContentViewModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 6)

            Color(nsColor: .separatorColor)
                .frame(height: 0.5)

            itemList
        }
        .frame(width: 680, height: 500)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(nsColor: .windowFrameColor), lineWidth: 0.5)
        )
        .scaleEffect(viewModel.panelScale)
        .opacity(viewModel.panelOpacity)
        .onChange(of: viewModel.shouldFocusSearch) { _, focused in
            if focused { searchFocused = true; viewModel.shouldFocusSearch = false }
        }
        // Typing → exit chip mode, clear selection (no highlight while filtering)
        .onChange(of: viewModel.searchText) {
            if !viewModel.isItemTitleMode {
                viewModel.selectedID = nil
            }
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))

            ZStack(alignment: .leading) {
                TextField("Clipboard", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22))
                    .focused($searchFocused)
                    .onChange(of: viewModel.searchText) { _, newVal in
                        if !newVal.isEmpty || !viewModel.isItemTitleMode {
                            viewModel.isItemTitleMode = false
                        }
                    }
                    .opacity(viewModel.isItemTitleMode ? 0 : 1)
                    .overlay(alignment: .leading) {
                        if viewModel.isItemTitleMode, let title = viewModel.selectedItem?.displayTitle {
                            titleChip(text: title)
                                .onTapGesture {
                                    viewModel.isItemTitleMode = false
                                    viewModel.searchText      = ""
                                    searchFocused             = true
                                }
                        }
                    }

                if !viewModel.isItemTitleMode && viewModel.searchText.isEmpty {
                    Text("Clipboard")
                        .font(.system(size: 22))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        .allowsHitTesting(false)
                }
            }

            if !viewModel.searchText.isEmpty && !viewModel.isItemTitleMode {
                Button { viewModel.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary.opacity(0.55))
                        .font(.system(size: 17))
                }
                .buttonStyle(.plain)
            }

            Menu {
                Button(role: .destructive) {
                    viewModel.store.clearAll()
                } label: {
                    Label("Clear History", systemImage: "trash")
                }
                Divider()
                Button {
                    viewModel.onShowSettings?()
                } label: {
                    Label("Settings…", systemImage: "gearshape")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 19, weight: .light))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // Title chip: "Sample text - Paste" where " - Paste" is muted (same style as
    // the type·time metadata in list rows)
    @ViewBuilder
    private func titleChip(text: String) -> some View {
        HStack {
            HStack(spacing: 0) {
                Text(text)
                    .font(.system(size: 22))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundColor(.primary)
                Text(" – Paste")
                    .font(.system(size: 22))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.22))
            )
            Spacer()
        }
    }

    // MARK: - Item list

    private var itemList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 1) {
                    if viewModel.filteredItems.isEmpty {
                        emptyState
                    } else {
                        ForEach(viewModel.filteredItems) { item in
                            ItemRowView(
                                item:       item,
                                store:      viewModel.store,
                                isSelected: isSelected(item),
                                isFocused:  isFocused(item),
                                onCopy:     { viewModel.copyToPasteboard(item) },
                                onSelect:   {
                                    viewModel.selectedID      = item.id
                                    viewModel.isItemTitleMode = true
                                },
                                onPaste:    {
                                    viewModel.selectedID = item.id
                                    viewModel.pasteSelected()
                                },
                                onDelete:   { viewModel.store.remove(item) }
                            )
                            .equatable()
                            .id(item.id)
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
            }
            .onChange(of: viewModel.selectedID) { _, id in
                guard let id else { return }
                proxy.scrollTo(id)  // no anchor = minimum scroll to fully reveal; no-op if already visible
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: viewModel.searchText.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 36, weight: .ultraLight))
                .foregroundColor(.secondary.opacity(0.4))
            Text(viewModel.searchText.isEmpty
                 ? "Nothing copied yet"
                 : "No results for \"\(viewModel.searchText)\"")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // An item is "selected" (has any highlight) only when selectedID is explicitly set
    private func isSelected(_ item: ClipboardItem) -> Bool {
        viewModel.selectedID == item.id
    }

    // An item is "focused" (accent color) when it is selected AND the panel is in
    // item-title mode (Tab was pressed or arrow-key navigated to it)
    private func isFocused(_ item: ClipboardItem) -> Bool {
        viewModel.selectedID == item.id && viewModel.isItemTitleMode
    }
}
