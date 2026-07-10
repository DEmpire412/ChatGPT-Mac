//
//  ChatViewModel.swift
//  ChatGPT-Mac
//
//  Owns the app-lifetime WKWebView and the native state mirrored out of the
//  ChatGPT web session (login state, current route, header controls).
//

import SwiftUI
import WebKit
import Observation

@Observable
@MainActor
final class ChatViewModel: NSObject {
    private(set) var isLoggedIn = false
    private(set) var hasReceivedState = false
    private(set) var currentPath = "/"
    private(set) var canShare = false
    private(set) var modelName = ""
    private(set) var hasConversationMenu = false
    private(set) var modes: [String] = []
    private(set) var selectedMode = ""
    private(set) var hasTemporaryChat = false
    private(set) var temporaryChatActive = false
    private(set) var sidebarVisible = true
    private(set) var fullscreenDialogOpen = false

    /// Incremented whenever the web app asks for the settings window (profile
    /// menu -> Settings / Personalization). Observed by ContentView to open the
    /// window and by SettingsView to jump to the requested tab.
    private(set) var settingsOpenRequestID = 0
    private(set) var requestedSettingsHash = "#settings/General"

    let webView: WKWebView

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        // Voice mode: let assistant speech play without a click gesture.
        configuration.mediaTypesRequiringUserActionForPlayback = []
        for script in Injection.userScripts {
            configuration.userContentController.addUserScript(script)
        }

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = Injection.safariUserAgent
        webView.allowsBackForwardNavigationGestures = true
        // No page zoom (pinch or otherwise); text size is adjusted via
        // ⌘+/⌘− instead, which scales only the chat surface.
        webView.allowsMagnification = false
        // Transparent so the native glass sidebar panel shows through the
        // (CSS-cleared) web sidebar region; the chat column stays opaque via CSS.
        webView.underPageBackgroundColor = .clear
        webView.setValue(false, forKey: "drawsBackground")

        super.init()

        configuration.userContentController.add(
            BridgeMessageHandler(model: self),
            name: Injection.messageHandlerName
        )
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.load(URLRequest(url: Injection.homeURL))
    }

    // MARK: - Actions

    func newChat() {
        webView.evaluateJavaScript("window.__cgptNewChat && window.__cgptNewChat()") { [weak self] result, _ in
            if (result as? Bool) != true {
                self?.webView.load(URLRequest(url: Injection.homeURL))
            }
        }
    }

    func reload() {
        if webView.url == nil {
            webView.load(URLRequest(url: Injection.homeURL))
        } else {
            webView.reload()
        }
    }

    func goHome() {
        webView.load(URLRequest(url: Injection.homeURL))
    }

    /// Opens ChatGPT's own share dialog for the current conversation.
    func share() {
        webView.evaluateJavaScript("window.__cgptShare && window.__cgptShare()")
    }

    /// Opens ChatGPT's model switcher menu. Logged out, the native button is
    /// centered in the toolbar, so the web menu is repositioned to match.
    func openModelMenu() {
        let centered = !isLoggedIn
        webView.evaluateJavaScript("window.__cgptOpenModelMenu && window.__cgptOpenModelMenu(\(centered))")
    }

    /// Switches the home screen's Chat / Work mode.
    func selectMode(_ name: String) {
        selectedMode = name
        let escaped = name.replacingOccurrences(of: "'", with: "\\'")
        webView.evaluateJavaScript("window.__cgptSelectMode && window.__cgptSelectMode('\(escaped)')")
    }

    /// Collapses or expands the web sidebar (the native glass panel follows).
    func toggleSidebar() {
        webView.evaluateJavaScript("window.__cgptToggleSidebar && window.__cgptToggleSidebar()")
    }

    /// Toggles ChatGPT's temporary chat mode.
    func toggleTemporaryChat() {
        webView.evaluateJavaScript("window.__cgptToggleTemporaryChat && window.__cgptToggleTemporaryChat()")
    }

    // MARK: - Chat text zoom

    /// Scale factor applied to the chat surface (`main`) only — the sidebar
    /// and the rest of the page keep their normal size.
    private(set) var chatTextZoom: Double = 1.0

    func increaseTextSize() {
        setTextZoom(chatTextZoom + 0.1)
    }

    func decreaseTextSize() {
        setTextZoom(chatTextZoom - 0.1)
    }

    func resetTextSize() {
        setTextZoom(1.0)
    }

    private func setTextZoom(_ value: Double) {
        chatTextZoom = min(max((value * 10).rounded() / 10, 0.5), 2.0)
        applyTextZoom()
    }

    fileprivate func applyTextZoom() {
        webView.evaluateJavaScript("window.__cgptSetTextZoom && window.__cgptSetTextZoom(\(chatTextZoom))")
    }

    /// Triggers an item from ChatGPT's conversation options ("...") menu by its label.
    func conversationMenuAction(_ label: String) {
        let escaped = label.replacingOccurrences(of: "'", with: "\\'")
        webView.evaluateJavaScript("window.__cgptMenuAction && window.__cgptMenuAction('\(escaped)')")
    }

    /// URL of the conversation currently open in the main window, if any.
    var currentConversationURL: URL? {
        guard currentPath.hasPrefix("/c/") else { return nil }
        return URL(string: currentPath, relativeTo: Injection.homeURL)?.absoluteURL
    }

    // MARK: - Bridge

    fileprivate func handleBridgeMessage(_ body: [String: Any]) {
        if body["type"] as? String == "openSettings" {
            let tab = body["tab"] as? String ?? "settings"
            requestedSettingsHash = tab == "personalization"
                ? "#settings/Personalization"
                : "#settings/General"
            settingsOpenRequestID += 1
            return
        }
        guard body["type"] as? String == "state" else { return }
        hasReceivedState = true
        isLoggedIn = body["loggedIn"] as? Bool ?? false
        currentPath = body["path"] as? String ?? "/"
        canShare = body["canShare"] as? Bool ?? false
        modelName = body["model"] as? String ?? ""
        hasConversationMenu = body["hasConversationMenu"] as? Bool ?? false
        modes = body["modes"] as? [String] ?? []
        selectedMode = body["selectedMode"] as? String ?? ""
        hasTemporaryChat = body["hasTemporaryChat"] as? Bool ?? false
        temporaryChatActive = body["temporaryChatActive"] as? Bool ?? false
        sidebarVisible = body["sidebarVisible"] as? Bool ?? false
        fullscreenDialogOpen = body["fullscreenDialogOpen"] as? Bool ?? false
        applyAppearance(body["appearance"] as? String ?? "")
    }

    /// Mirrors the web app's Appearance setting onto the whole app, so native
    /// chrome matches when the user overrides light/dark instead of following
    /// the system.
    private func applyAppearance(_ preference: String) {
        let target: NSAppearance?
        switch preference {
        case "dark": target = NSAppearance(named: .darkAqua)
        case "light": target = NSAppearance(named: .aqua)
        default: target = nil
        }
        if NSApp.appearance?.name != target?.name {
            NSApp.appearance = target
        }
    }
}

// MARK: - WKNavigationDelegate / WKUIDelegate

extension ChatViewModel: WKNavigationDelegate, WKUIDelegate {
    nonisolated func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        Task { @MainActor in
            guard let url = navigationAction.request.url, let host = url.host() else {
                decisionHandler(.allow)
                return
            }
            // Only ChatGPT itself and the sign-in flows stay in-app; other
            // main-frame navigations open in the default browser — but only when
            // the user actually clicked a link. Server redirects and form
            // submissions always load in place: OAuth flows (e.g. Google) hop
            // through hosts outside the allowlist (accounts.youtube.com,
            // googleapis.com, ...) after credentials are entered, and bouncing
            // those to the browser breaks sign-in.
            let allowedSuffixes = [
                "chatgpt.com", "chat.openai.com", "auth.openai.com", "auth0.com",
                // Google sign-in (youtube/googleapis appear in its redirect chain)
                "google.com", "googleusercontent.com", "gstatic.com", "recaptcha.net",
                "googleapis.com", "youtube.com",
                // Apple sign-in
                "apple.com", "cdn-apple.com",
                // Microsoft sign-in (personal and work/school accounts)
                "microsoftonline.com", "microsoft.com", "live.com",
                "msauth.net", "msftauth.net", "windows.net",
                // Common enterprise SSO providers
                "okta.com", "oktacdn.com", "onelogin.com", "duosecurity.com",
                "pingidentity.com", "pingone.com",
            ]
            let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
            let isLinkClick = navigationAction.navigationType == .linkActivated
            if allowedSuffixes.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
                decisionHandler(.allow)
            } else if isMainFrame && isLinkClick {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            } else {
                // Redirects, form posts, and subframes (captchas, embeds) load in place.
                decisionHandler(.allow)
            }
        }
    }

    // Reapply the chat text zoom after full page loads (reload, sign-in return),
    // which wipe the injected zoom style.
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated {
            if chatTextZoom != 1.0 {
                applyTextZoom()
            }
        }
    }

    // Voice mode: approve microphone capture for ChatGPT itself; the system-level
    // microphone consent prompt is still shown by macOS on first use.
    nonisolated func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void
    ) {
        Task { @MainActor in
            let host = origin.host
            let trusted = host == "chatgpt.com" || host.hasSuffix(".chatgpt.com")
                || host == "openai.com" || host.hasSuffix(".openai.com")
            if trusted && (type == .microphone || type == .cameraAndMicrophone) {
                decisionHandler(.grant)
            } else {
                decisionHandler(.prompt)
            }
        }
    }

    // File uploads ("Add photos and files"): show the system open panel.
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

    // Auth popups (Google sign-in) request a new window; load them in place instead.
    nonisolated func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        MainActor.assumeIsolated {
            if let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
        }
        return nil
    }
}

/// Breaks the retain cycle WKUserContentController would otherwise create with the model.
private final class BridgeMessageHandler: NSObject, WKScriptMessageHandler {
    weak var model: ChatViewModel?

    init(model: ChatViewModel) {
        self.model = model
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any] else { return }
        MainActor.assumeIsolated {
            model?.handleBridgeMessage(body)
        }
    }
}
