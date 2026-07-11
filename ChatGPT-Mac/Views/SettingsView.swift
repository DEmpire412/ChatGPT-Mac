//
//  SettingsView.swift
//  ChatGPT-Mac
//
//  Native Settings window (Cmd+,) hosting ChatGPT's web settings dialog.
//  A dedicated WKWebView loads the #settings deep link; injected CSS hides the
//  app shell and stretches the dialog to fill the window over glass.
//

import SwiftUI
import WebKit

struct SettingsView: View {
    @Environment(ChatViewModel.self) private var model
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var holder = SettingsWebViewHolder()

    var body: some View {
        ChatWebView(webView: holder.webView)
            .frame(minWidth: 850, idealWidth: 920, minHeight: 600, idealHeight: 700)
            .ignoresSafeArea()
            .background(alignment: .leading) {
                // Same treatment as the main window: native glass under the
                // dialog's (transparent) nav column, opaque surface elsewhere.
                HStack(spacing: 0) {
                    SidebarView()
                        .frame(width: Injection.settingsSidebarWidth)
                    Color.chatGPTSurface
                }
                .ignoresSafeArea()
            }
            .onAppear {
                holder.setOpenInMainWindowHandler { url in
                    dismissWindow(id: "settings")
                    model.openInMainWindow(url)
                }
                holder.open(hash: model.requestedSettingsHash)
            }
            .onChange(of: model.settingsOpenRequestID) {
                holder.open(hash: model.requestedSettingsHash)
            }
            .onChange(of: model.settingsReloadRequestID) {
                holder.reload(hash: model.requestedSettingsHash)
            }
            .onChange(of: model.isLoggedIn) {
                if model.isLoggedIn {
                    // The session changed under us (sign-in in the main window);
                    // a full reload picks up the new cookies.
                    holder.reload(hash: model.requestedSettingsHash)
                } else {
                    // The native settings window is a logged-in feature.
                    dismissWindow(id: "settings")
                }
            }
    }
}

private final class SettingsWindowDragRegion: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

@MainActor
private final class SettingsNavigationDelegate: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    var openInMainWindow: ((URL) -> Void)?

    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == Injection.settingsNavigationHandlerName,
              let body = message.body as? [String: Any],
              let type = body["type"] as? String,
              let value = body["url"] as? String,
              let url = URL(string: value) else { return }
        Task { @MainActor [weak self] in
            switch type {
            case "openMainWindow":
                self?.openInMainWindow?(url)
            case "openExternal":
                NSWorkspace.shared.open(url)
            default:
                break
            }
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        Task { @MainActor [weak self] in
            guard let url = navigationAction.request.url,
                  let host = url.host() else {
                decisionHandler(.allow)
                return
            }

            let isChatGPT = host == "chatgpt.com" || host.hasSuffix(".chatgpt.com")
            let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
            let providerURL = url.absoluteString.lowercased()
            if isChatGPT && (providerURL.contains("linkedin") || providerURL.contains("github")) {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }

            if !isChatGPT && isMainFrame {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }

            guard navigationAction.navigationType == .linkActivated else {
                decisionHandler(.allow)
                return
            }

            let settingsURL = url.absoluteString.lowercased()
            let isSettingsLink = url.fragment?.lowercased().hasPrefix("settings") == true
                || settingsURL.contains("settings")
                || settingsURL.contains("billing")
                || settingsURL.contains("invoice")
                || settingsURL.contains("subscription")
            if isChatGPT && !isSettingsLink {
                self?.openInMainWindow?(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}

private final class SettingsUIDelegate: NSObject, WKUIDelegate {
    nonisolated func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor ([URL]?) -> Void
    ) {
        Task { @MainActor in
            presentOpenPanel(for: webView, parameters: parameters, completionHandler: completionHandler)
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        MainActor.assumeIsolated {
            if let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
            }
        }
        return nil
    }
}

@Observable
@MainActor
private final class SettingsWebViewHolder {
    let webView: WKWebView
    private var hasLoaded = false
    private let uiDelegate = SettingsUIDelegate()
    private let navigationDelegate: SettingsNavigationDelegate

    init() {
        let navigationDelegate = SettingsNavigationDelegate()
        self.navigationDelegate = navigationDelegate

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        for script in Injection.settingsWindowUserScripts {
            configuration.userContentController.addUserScript(script)
        }
        configuration.userContentController.add(
            navigationDelegate,
            name: Injection.settingsNavigationHandlerName
        )

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = Injection.safariUserAgent
        webView.underPageBackgroundColor = .clear
        webView.setValue(false, forKey: "drawsBackground")
        webView.uiDelegate = uiDelegate
        webView.navigationDelegate = navigationDelegate

        let dragRegion = SettingsWindowDragRegion()
        dragRegion.translatesAutoresizingMaskIntoConstraints = false
        webView.addSubview(dragRegion, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            dragRegion.leadingAnchor.constraint(equalTo: webView.leadingAnchor, constant: 84),
            // Stop at the nav column's edge: detail views (e.g. Billing's
            // invoice list) place a back button at the top of the content
            // panel, and the overlay would swallow clicks on it.
            dragRegion.trailingAnchor.constraint(
                equalTo: webView.leadingAnchor,
                constant: Injection.settingsSidebarWidth
            ),
            dragRegion.topAnchor.constraint(equalTo: webView.topAnchor),
            dragRegion.heightAnchor.constraint(equalToConstant: 36),
        ])
    }

    func setOpenInMainWindowHandler(_ handler: @escaping (URL) -> Void) {
        navigationDelegate.openInMainWindow = handler
    }

    /// Opens the settings dialog at the given tab hash (e.g. "#settings/Personalization"),
    /// navigating in place when the page is already loaded.
    func open(hash: String) {
        if hasLoaded {
            let escaped = hash.replacingOccurrences(of: "'", with: "\\'")
            webView.evaluateJavaScript("location.hash = '\(escaped)'")
        } else {
            reload(hash: hash)
        }
        // The hash deep link doesn't reliably select the tab; click it by
        // label once the dialog has rendered.
        if let tab = hash.split(separator: "/").last {
            selectTab(named: String(tab))
        }
    }

    private var tabSelectionAttempt = 0

    private func selectTab(named name: String) {
        tabSelectionAttempt += 1
        let attempt = tabSelectionAttempt
        let escaped = name.replacingOccurrences(of: "'", with: "\\'")
        let call = "window.__cgptSelectSettingsTab ? window.__cgptSelectSettingsTab('\(escaped)') : false"
        Task { @MainActor [webView] in
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(500))
                guard attempt == tabSelectionAttempt else { return }
                let result = try? await webView.evaluateJavaScript(call)
                if (result as? Bool) == true { return }
            }
        }
    }

    /// Full page load, picking up the current session's cookies.
    func reload(hash: String) {
        hasLoaded = true
        webView.load(URLRequest(url: URL(string: hash, relativeTo: Injection.homeURL) ?? Injection.settingsURL))
    }
}
