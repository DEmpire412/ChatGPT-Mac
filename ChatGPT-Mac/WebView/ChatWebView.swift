//
//  ChatWebView.swift
//  ChatGPT-Mac
//
//  SwiftUI host for the model-owned WKWebView.
//

import SwiftUI
import WebKit

struct ChatWebView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

/// Shows the system open panel for a web page's file input, as a sheet on the
/// web view's window when possible.
@MainActor
func presentOpenPanel(
    for webView: WKWebView,
    parameters: WKOpenPanelParameters,
    completionHandler: @escaping @MainActor ([URL]?) -> Void
) {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = parameters.allowsDirectories
    panel.allowsMultipleSelection = parameters.allowsMultipleSelection
    let finish: @MainActor (NSApplication.ModalResponse) -> Void = { response in
        completionHandler(response == .OK ? panel.urls : nil)
    }
    if let window = webView.window {
        panel.beginSheetModal(for: window) { response in
            MainActor.assumeIsolated { finish(response) }
        }
    } else {
        finish(panel.runModal())
    }
}

/// Minimal UI delegate for the auxiliary web views (floating chats, settings)
/// so their file inputs also open the system picker.
final class FileUploadUIDelegate: NSObject, WKUIDelegate {
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
}
