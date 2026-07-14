//
//  UpdateSettingsView.swift
//  ChatGPT-Mac
//

import SwiftUI

struct UpdateSettingsView: View {
    @Environment(AppUpdater.self) private var updater

    var body: some View {
        Form {
            Section {
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.setAutomaticallyChecksForUpdates($0) }
                ))
                .disabled(!updater.isConfigured)

                Toggle("Download and install updates automatically", isOn: Binding(
                    get: { updater.automaticallyDownloadsUpdates },
                    set: { updater.setAutomaticallyDownloadsUpdates($0) }
                ))
                .disabled(!updater.isConfigured || !updater.allowsAutomaticUpdates)
            }

            Section {
                HStack {
                    Text("Last checked")
                    Spacer()
                    Text(lastCheckedText)
                        .foregroundStyle(.secondary)
                }

                Button {
                    updater.checkForUpdates()
                } label: {
                    Label("Check for Updates", systemImage: "arrow.clockwise")
                }
                .disabled(!updater.canCheckForUpdates)
            }

            if !updater.isConfigured {
                Section {
                    Text("Set SPARKLE_FEED_URL and SPARKLE_PUBLIC_ED_KEY in the ChatGPT-Mac target build settings before distributing update-enabled builds.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 460)
    }

    private var lastCheckedText: String {
        guard let date = updater.lastUpdateCheckDate else { return "Never" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
