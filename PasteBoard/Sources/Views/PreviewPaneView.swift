import SwiftUI
import AppKit

struct PreviewPaneView: View {
    let item: ClipboardItem?
    let store: ClipboardStore

    var body: some View {
        Group {
            if let item {
                switch item.type {
                case .text:
                    ScrollView([.vertical, .horizontal]) {
                        Text(item.text ?? "")
                            .font(.system(size: 13, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                case .image:
                    if let image = store.image(for: item) {
                        ScrollView([.vertical, .horizontal]) {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .padding(16)
                        }
                    } else {
                        placeholder(symbol: "photo", label: "Image not found")
                    }
                case .url:
                    VStack(spacing: 16) {
                        Image(systemName: "link.circle.fill")
                            .font(.system(size: 52))
                            .foregroundColor(.blue)
                        Text(item.url ?? "")
                            .font(.system(size: 13))
                            .foregroundColor(.blue)
                            .textSelection(.enabled)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .file:
                    VStack(spacing: 12) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 52))
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(item.filePaths ?? [], id: \.self) { path in
                                Text(path)
                                    .font(.system(size: 12, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                placeholder(symbol: "doc.on.clipboard", label: "Copy something to get started")
            }
        }
    }

    private func placeholder(symbol: String, label: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
