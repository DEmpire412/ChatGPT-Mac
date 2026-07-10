//
//  ChatGPT_MacApp.swift
//  ChatGPT-Mac
//

import SwiftUI

@main
struct ChatGPT_MacApp: App {
    @State private var model = ChatViewModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .frame(minWidth: 800, minHeight: 520)
                .containerBackground(.thickMaterial, for: .window)
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands {
            // Standard "Settings…" slot in the app menu, opening our custom
            // settings window instead of a SwiftUI Settings scene.
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    // The native settings window is a logged-in feature; logged
                    // out, open the site's inline popover in the main window.
                    if model.isLoggedIn {
                        openWindow(id: "settings")
                    } else {
                        model.showWebSettings()
                    }
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .newItem) {
                Button("New Chat") {
                    model.newChat()
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .toolbar) {
                Button("Toggle Sidebar") {
                    model.toggleSidebar()
                }
                .keyboardShortcut("s", modifiers: [.command, .control])

                Button("Reload Page") {
                    model.reload()
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Home") {
                    model.goHome()
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])

                Divider()

                // "=" so plain ⌘ and the +/= key works without shift.
                Button("Increase Text Size") {
                    model.increaseTextSize()
                }
                .keyboardShortcut("=", modifiers: .command)

                Button("Decrease Text Size") {
                    model.decreaseTextSize()
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Actual Text Size") {
                    model.resetTextSize()
                }
                .keyboardShortcut("0", modifiers: .command)
            }
        }

        // Compact always-on-top windows for individual chats, drawn with fully
        // custom chrome (no title bar or traffic lights). A real titled window
        // (not .plain) so it can become key and accept text input; the chrome
        // is stripped in FloatingChatView's window configurator.
        WindowGroup("Floating Chat", for: URL.self) { $url in
            if let url {
                FloatingChatView(url: url)
                    .environment(model)
                    .frame(minWidth: 360, minHeight: 400)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowLevel(.floating)
        .defaultSize(width: 440, height: 620)

        // ChatGPT's settings pane in its own window, opened from the app menu
        // (Cmd+,) via the command above. Styled like the main window: hidden
        // title bar with glass showing through the dialog's nav column.
        Window("Settings", id: "settings") {
            SettingsView()
                .environment(model)
                .containerBackground(.thickMaterial, for: .window)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 920, height: 700)
    }
}
