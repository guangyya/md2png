import AppKit

@MainActor
final class UpdateController {
    func showReleasesPrompt(releasesURL: URL? = ProjectLinks.releases) {
        guard let releasesURL else { return }
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? L10n.text("releases.development", defaultValue: "Development")

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.text(
            "releases.title",
            defaultValue: "md2png Releases"
        )
        alert.informativeText = L10n.format(
            "releases.body",
            defaultValue: "You’re using version %@.\n\nNew versions are published on the project’s Releases page. md2png does not check in the background, contact an update server, or download anything automatically.",
            version
        )
        alert.addButton(withTitle: L10n.text(
            "releases.open",
            defaultValue: "Open Releases"
        ))
        alert.addButton(withTitle: L10n.text("common.cancel", defaultValue: "Cancel"))

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(releasesURL)
        }
    }
}
