import ModelLayer
import PhotoBookCore
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Editorial home for an empty document. The primary action starts the guided
/// creation flow; opening an existing project stays deliberately secondary.
struct WelcomeView: View {
    let onCreate: () -> Void

    #if os(macOS)
    @Environment(\.openDocument) private var openDocument
    @State private var showOpenImporter = false
    @State private var errorMessage: String?
    #endif

    var body: some View {
        ZStack {
            Color.primary.opacity(0.035).ignoresSafeArea()
            #if os(macOS)
            HStack(spacing: 64) {
                heroCopy
                    .frame(maxWidth: .infinity, alignment: .leading)
                bookPreview
                    .frame(maxWidth: .infinity)
                    .frame(height: 320)
            }
            .padding(56)
            .frame(maxWidth: 980)
            #else
            ScrollView {
                VStack(spacing: 28) {
                    bookPreview
                        .frame(maxWidth: 360)
                        .frame(height: 260)
                    heroCopy
                        .frame(maxWidth: 430, alignment: .leading)
                }
                .padding(28)
            }
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 680, minHeight: 520)
        #endif
        #if os(macOS)
        .fileImporter(isPresented: $showOpenImporter,
                      allowedContentTypes: [.photoBook]) { result in
            switch result {
            case .success(let url): openProject(at: url)
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
        #endif
    }

    private var heroCopy: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("PHOTOBOOKS", bundle: .module)
                .font(.caption.weight(.semibold))
                .tracking(2.4)
                .foregroundStyle(.secondary)
            Text("Turn your photos\ninto a book.", bundle: .module)
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .tracking(-1.2)
            Text("Choose the moments you love. We’ll arrange them into a polished book you can refine and print.", bundle: .module)
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 12) {
                Button(action: onCreate) {
                    HStack {
                        Label(String(localized: "Create a new book", bundle: .module), systemImage: "plus")
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .font(.headline)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: 340)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .focusEffectDisabled()
                .accessibilityIdentifier("welcome-create")

                #if os(macOS)
                Button {
                    showOpenImporter = true
                } label: {
                    Label(String(localized: "Open an existing book", bundle: .module), systemImage: "folder")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("welcome-open")

                if let errorMessage {
                    Text(errorMessage).font(.callout).foregroundStyle(.red)
                }
                #endif
            }

            Link(destination: URL(string: "https://graphicmeat.com")!) {
                HStack(spacing: 10) {
                    graphicMeatLogo
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Made by Graphic Meat", bundle: .module)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(verbatim: "graphicmeat.com")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(Text("Visit graphicmeat.com", bundle: .module))
            .accessibilityLabel(Text("Visit Graphic Meat website", bundle: .module))
        }
    }

    private var graphicMeatLogo: Image {
        guard let url = Bundle.module.url(forResource: "GraphicMeatLogo", withExtension: "png") else {
            return Image(systemName: "globe")
        }
        #if os(macOS)
        guard let image = NSImage(contentsOf: url) else { return Image(systemName: "globe") }
        return Image(nsImage: image)
        #else
        guard let image = UIImage(contentsOfFile: url.path) else { return Image(systemName: "globe") }
        return Image(uiImage: image)
        #endif
    }

    private var bookPreview: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / 400, geometry.size.height / 320)

            ZStack {
                RoundedRectangle(cornerRadius: 28)
                    .fill(Color.accentColor.opacity(0.10))
                    .frame(width: 330, height: 260)
                    .rotationEffect(.degrees(5))
                HStack(spacing: 3) {
                    previewPage(alignment: .trailing)
                    previewPage(alignment: .leading)
                }
                .padding(14)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.16), radius: 22, y: 12)
                .rotationEffect(.degrees(-3))
            }
            .frame(width: 400, height: 320)
            .scaleEffect(scale)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .accessibilityHidden(true)
    }

    private func previewPage(alignment: Alignment) -> some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3)
                .fill(LinearGradient(colors: [Color.accentColor.opacity(0.8),
                                              Color.orange.opacity(0.55)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(Color.secondary.opacity(0.18))
                RoundedRectangle(cornerRadius: 2).fill(Color.secondary.opacity(0.28))
            }
            .frame(height: 62)
        }
        .frame(width: 150, height: 210, alignment: alignment)
    }

    #if os(macOS)
    private func openProject(at url: URL) {
        errorMessage = nil
        let scoped = url.startAccessingSecurityScopedResource()
        Task {
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do { try await openDocument(at: url) }
            catch { errorMessage = error.localizedDescription }
        }
    }
    #endif
}
