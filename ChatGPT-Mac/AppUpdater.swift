//
//  AppUpdater.swift
//  ChatGPT-Mac
//

import Foundation
import Observation
import Sparkle

@Observable
@MainActor
final class AppUpdater: NSObject, SPUUpdaterDelegate {
    private(set) var isConfigured: Bool
    private(set) var canCheckForUpdates = false
    private(set) var isCheckingForUpdates = false
    private(set) var lastUpdateCheckDate: Date?

    @ObservationIgnored private var updaterController: SPUStandardUpdaterController!

    override init() {
        isConfigured = Self.hasUpdateConfiguration
        super.init()

        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )

        if isConfigured {
            updaterController.startUpdater()
        }
        refreshState()
    }

    var automaticallyChecksForUpdates: Bool {
        updater.automaticallyChecksForUpdates
    }

    var automaticallyDownloadsUpdates: Bool {
        updater.automaticallyDownloadsUpdates
    }

    var allowsAutomaticUpdates: Bool {
        updater.allowsAutomaticUpdates
    }

    func checkForUpdates() {
        guard isConfigured, updater.canCheckForUpdates else { return }
        updaterController.checkForUpdates(nil)
        refreshState()
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        guard isConfigured else { return }
        updater.automaticallyChecksForUpdates = enabled
        refreshState()
    }

    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        guard isConfigured, updater.allowsAutomaticUpdates else { return }
        updater.automaticallyDownloadsUpdates = enabled
        refreshState()
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: (any Error)?
    ) {
        refreshState()
    }

    private var updater: SPUUpdater {
        updaterController.updater
    }

    private func refreshState() {
        canCheckForUpdates = isConfigured && updater.canCheckForUpdates
        isCheckingForUpdates = updater.sessionInProgress
        lastUpdateCheckDate = updater.lastUpdateCheckDate
    }

    private static var hasUpdateConfiguration: Bool {
        hasInfoPlistValue(forKey: "SUFeedURL") && hasInfoPlistValue(forKey: "SUPublicEDKey")
    }

    private static func hasInfoPlistValue(forKey key: String) -> Bool {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return false }
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedValue.isEmpty && !trimmedValue.hasPrefix("$(")
    }
}
