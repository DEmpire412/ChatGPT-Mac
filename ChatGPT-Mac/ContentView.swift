//
//  ContentView.swift
//  ChatGPT-Mac
//

import SwiftUI

struct ContentView: View {
    @Environment(ChatViewModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ChatWebView(webView: model.webView)
            .ignoresSafeArea(edges: .bottom)
            .background(alignment: .leading) {
                // Layered behind the transparent web view: native glass under the
                // web sidebar region, the site's opaque surface color everywhere
                // else (extending up beneath the toolbar).
                HStack(spacing: 0) {
                    // A full-screen web dialog covers the sidebar region with the
                    // opaque surface, so drop the glass panel to match. Keyed off
                    // the web sidebar's actual presence (not login state) so the
                    // logged-out page's sidebar gets glass too.
                    if model.sidebarVisible && !model.fullscreenDialogOpen {
                        SidebarView()
                            .frame(width: SidebarView.width)
                            .transition(.move(edge: .leading))
                    }
                    Color.chatGPTSurface
                }
                .animation(.easeInOut(duration: 0.2), value: model.sidebarVisible)
                .ignoresSafeArea()
            }
            .onChange(of: model.settingsOpenRequestID) {
                openWindow(id: "settings")
            }
            .toolbar {
                // While a full-screen web dialog (e.g. "Upgrade your plan") is up,
                // it owns the window: no native controls floating over it.
                if !model.fullscreenDialogOpen {
                    ToolbarItemGroup(placement: .navigation) {
                        if model.isLoggedIn {
                            Button {
                                model.toggleSidebar()
                            } label: {
                                Label("Toggle Sidebar", systemImage: "sidebar.left")
                            }
                            .help("Show or hide the sidebar (⌃⌘S)")
                        }

                        Button {
                            model.newChat()
                        } label: {
                            Label("New Chat", systemImage: "square.and.pencil")
                        }
                        .help("New Chat (⌘N)")

                        Button {
                            model.reload()
                        } label: {
                            Label("Reload", systemImage: "arrow.clockwise")
                        }
                        .help("Reload (⌘R)")
                    }
                }

                if model.modes.count > 1 && !model.fullscreenDialogOpen {
                    ToolbarItem(placement: .principal) {
                        Picker("Mode", selection: modeBinding) {
                            ForEach(model.modes, id: \.self) { mode in
                                Text(mode).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .help("Switch between Chat and Work")
                    }
                }

                if !model.modelName.isEmpty && !model.fullscreenDialogOpen {
                    // Logged out there's no sidebar toggle pushing items right,
                    // so the picker would sit over the sidebar column; center it
                    // above the chat surface instead.
                    ToolbarItem(placement: model.isLoggedIn ? .automatic : .principal) {
                        Button {
                            model.openModelMenu()
                        } label: {
                            HStack(spacing: 4) {
                                Text(model.modelName)
                                Image(systemName: "chevron.down")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .help("Switch model")
                    }
                }

                // Pushes the share and options items to the trailing edge of the window.
                ToolbarSpacer(.flexible)

                if model.hasTemporaryChat && !model.fullscreenDialogOpen {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            model.toggleTemporaryChat()
                        } label: {
                            Label("Temporary Chat", systemImage: "circle.dotted")
                                .foregroundStyle(model.temporaryChatActive ? Color.accentColor : Color.primary)
                        }
                        .help(model.temporaryChatActive ? "Turn off temporary chat" : "Temporary chat")
                    }
                }

                if let conversationURL = model.currentConversationURL, !model.fullscreenDialogOpen {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            openWindow(value: conversationURL)
                        } label: {
                            Label("Open in Floating Window", systemImage: "macwindow.on.rectangle")
                        }
                        .help("Open this chat in a floating window")
                    }
                }

                if model.canShare && !model.fullscreenDialogOpen {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            model.share()
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .help("Share conversation")
                    }
                }

                if model.hasConversationMenu && !model.fullscreenDialogOpen {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button {
                                model.conversationMenuAction("View files in chat")
                            } label: {
                                Label("View Files in Chat", systemImage: "folder")
                            }
                            Button {
                                model.conversationMenuAction("Pin chat")
                            } label: {
                                Label("Pin Chat", systemImage: "pin")
                            }
                            Button {
                                model.conversationMenuAction("Archive")
                            } label: {
                                Label("Archive", systemImage: "archivebox")
                            }
                            Divider()
                            Button(role: .destructive) {
                                model.conversationMenuAction("Delete")
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        } label: {
                            Label("More", systemImage: "ellipsis")
                        }
                        .help("Conversation options")
                    }
                }
            }
    }

    private var modeBinding: Binding<String> {
        Binding(
            get: { model.selectedMode },
            set: { mode in
                if mode != model.selectedMode {
                    model.selectMode(mode)
                }
            }
        )
    }
}
