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
            .overlay(alignment: .trailing) {
                Divider()
            }
    }
}

extension Color {
    /// Matches chatgpt.com's page background: white in light mode, pitch black in dark mode.
    static let chatGPTSurface = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? .black
            : .white
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
