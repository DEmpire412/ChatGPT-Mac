//
//  FloatingChatView.swift
//  ChatGPT-Mac
//
//  A compact, always-on-top window showing a single conversation, drawn with
//  fully custom chrome: no traffic lights, a translucent glass top bar, and
//  large rounded corners. Uses its own WKWebView (sharing the default data
//  store, so the login session carries over) with the sidebar hidden.
//

import SwiftUI
import WebKit

struct FloatingChatView: View {
    let url: URL
    @Environment(ChatViewModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var holder = FloatingWebViewHolder()

    private static let cornerRadius: CGFloat = 22

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ChatWebView(webView: holder.webView)
        }
        .background(.thickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(.separator.opacity(0.5), lineWidth: 1)
        }
        .ignoresSafeArea()
        .background(FloatingWindowConfigurator())
        .onAppear {
            holder.loadIfNeeded(url)
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(.quaternary, in: .circle)
            }
            .buttonStyle(.plain)
            .help("Close")

            Spacer()

            Button {
                openInMainWindow()
            } label: {
                Image(systemName: "rectangle.on.rectangle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Open in main window")

            Button {
                holder.webView.load(Injection.freshRequest(for: Injection.homeURL))
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("New chat")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(.rect)
        .gesture(WindowDragGesture())
    }

    private func openInMainWindow() {
        let target = holder.webView.url ?? url
        model.openInMainWindow(target)
        NSApp.activate()
        model.webView.window?.makeKeyAndOrderFront(nil)
        dismiss()
    }
}

/// Strips the system chrome from the hosting window while keeping it a real
/// titled window (so it can become key and receive keyboard input, unlike a
/// borderless `.plain` window).
private struct FloatingWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ConfiguringView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ConfiguringView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            for button: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(button)?.isHidden = true
            }
            // Transparent window frame; the SwiftUI content's rounded glass
            // shape defines the visible bounds (and the shadow follows it).
            window.isOpaque = false
            window.backgroundColor = .clear
        }
    }
}

@Observable
@MainActor
private final class FloatingWebViewHolder {
    let webView: WKWebView
    private var hasLoaded = false
    private let uiDelegate = FileUploadUIDelegate()

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        for script in Injection.floatingWindowUserScripts {
            configuration.userContentController.addUserScript(script)
        }

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = Injection.safariUserAgent
        webView.allowsMagnification = true
        webView.underPageBackgroundColor = .clear
        webView.setValue(false, forKey: "drawsBackground")
        webView.uiDelegate = uiDelegate
    }

    func loadIfNeeded(_ url: URL) {
        guard !hasLoaded else { return }
        hasLoaded = true
        webView.load(Injection.freshRequest(for: url))
    }
}
