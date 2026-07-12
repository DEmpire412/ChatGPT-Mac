//
//  SidebarView.swift
//  ChatGPT-Mac
//
//  Native translucent backdrop for ChatGPT's web sidebar. The web view sits on
//  top of this panel; injected CSS clears the web sidebar's background, so this
//  Apple-style sidebar material shows through it.
//

import SwiftUI
import AppKit

struct SidebarView: View {
    /// Matches ChatGPT's default sidebar width (its --sidebar-width token).
    static let width: CGFloat = 260

    var body: some View {
        SidebarMaterial()
    }
}

extension Color {
    /// Matches chatgpt.com's page background, including transparent web view gaps
    /// exposed during scroll/overscroll.
    static let chatGPTSurface = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? .black
            : NSColor(calibratedRed: 247.0 / 255.0, green: 247.0 / 255.0, blue: 248.0 / 255.0, alpha: 1)
    })
}

/// The system sidebar material with behind-window blending — the same
/// translucent effect Finder and Notes sidebars use.
private struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
