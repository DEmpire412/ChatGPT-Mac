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
    @State private var holder = SettingsWebViewHolder()

    var body: some View {
        ChatWebView(webView: holder.webView)
            .frame(minWidth: 850, idealWidth: 920, minHeight: 560, idealHeight: 700)
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
                holder.open(hash: model.requestedSettingsHash)
            }
            .onChange(of: model.settingsOpenRequestID) {
                holder.open(hash: model.requestedSettingsHash)
            }
    }
}

@Observable
@MainActor
private final class SettingsWebViewHolder {
    let webView: WKWebView
    private var hasLoaded = false
    private let uiDelegate = FileUploadUIDelegate()

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        for script in Injection.settingsWindowUserScripts {
            configuration.userContentController.addUserScript(script)
        }

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = Injection.safariUserAgent
        webView.underPageBackgroundColor = .clear
        webView.setValue(false, forKey: "drawsBackground")
        webView.uiDelegate = uiDelegate
    }

    /// Opens the settings dialog at the given tab hash (e.g. "#settings/Personalization"),
    /// navigating in place when the page is already loaded.
    func open(hash: String) {
        if hasLoaded {
            let escaped = hash.replacingOccurrences(of: "'", with: "\\'")
            webView.evaluateJavaScript("location.hash = '\(escaped)'")
        } else {
            hasLoaded = true
            webView.load(URLRequest(url: URL(string: hash, relativeTo: Injection.homeURL) ?? Injection.settingsURL))
        }
    }
}
