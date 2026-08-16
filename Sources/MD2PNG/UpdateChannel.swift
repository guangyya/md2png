import Foundation

enum AppBuildConfiguration: Equatable, Sendable {
    case debug
    case release

    static var current: AppBuildConfiguration {
#if DEBUG
        .debug
#else
        .release
#endif
    }

    func displayName(bundle: Bundle? = nil) -> String {
        switch self {
        case .debug:
            return L10n.text("about.build_debug", defaultValue: "DEBUG", bundle: bundle)
        case .release:
            return L10n.text("about.build_release", defaultValue: "RELEASE", bundle: bundle)
        }
    }
}

enum UpdateChannel: Equatable, Sendable {
    case disabled
    case stableGitHubReleases(repository: GitHubRepository)

    static func resolve(
        buildConfiguration: AppBuildConfiguration,
        projectURL: URL?
    ) -> UpdateChannel {
        guard buildConfiguration == .release,
              let projectURL,
              let repository = GitHubRepository(projectURL: projectURL) else {
            return .disabled
        }
        return .stableGitHubReleases(repository: repository)
    }

    static func current(bundle: Bundle = .main) -> UpdateChannel {
        resolve(
            buildConfiguration: .current,
            projectURL: ProjectLinks.projectURL(bundle: bundle)
        )
    }

    var repository: GitHubRepository? {
        switch self {
        case .disabled:
            return nil
        case let .stableGitHubReleases(repository):
            return repository
        }
    }

    var allowsUpdateChecks: Bool {
        repository != nil
    }
}
