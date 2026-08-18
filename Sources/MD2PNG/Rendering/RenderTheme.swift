import Foundation

struct RenderTheme: RawRepresentable, CaseIterable, Hashable, Sendable {
    let rawValue: String

    init?(rawValue: String) {
        guard RenderThemeRegistry.bundled.contains(id: rawValue) else { return nil }
        self.rawValue = rawValue
    }

    fileprivate init(uncheckedRawValue: String) {
        rawValue = uncheckedRawValue
    }

    static let cleanLight = RenderTheme(uncheckedRawValue: "cleanLight")
    static let warmPaper = RenderTheme(uncheckedRawValue: "warmPaper")
    static let dark = RenderTheme(uncheckedRawValue: "dark")

    static var allCases: [RenderTheme] {
        RenderThemeRegistry.bundled.themes
    }

    var menuTitle: String {
        menuTitle(localizationBundle: nil)
    }

    func menuTitle(localizationBundle: Bundle?) -> String {
        guard let descriptor = RenderThemeRegistry.bundled.descriptor(for: self) else {
            return rawValue
        }
        return L10n.text(
            descriptor.localizationKey,
            defaultValue: descriptor.defaultTitle,
            bundle: localizationBundle
        )
    }
}

struct RenderThemeRegistry: Sendable {
    static let supportedSchemaVersion = 1

    struct Descriptor: Equatable, Sendable {
        enum Appearance: String, Decodable, Sendable {
            case light
            case dark
        }

        let theme: RenderTheme
        let localizationKey: String
        let defaultTitle: String
        let appearance: Appearance
        let stylesheet: String
    }

    enum RegistryError: Error, Equatable {
        case unsupportedSchemaVersion(Int)
        case missingDefaultTheme
        case invalidDescriptor
    }

    private struct Manifest: Decodable {
        let schemaVersion: Int
        let themes: [ManifestTheme]
    }

    private struct ManifestTheme: Decodable {
        let id: String
        let localizationKey: String
        let defaultTitle: String
        let appearance: Descriptor.Appearance
        let stylesheet: String
    }

    static let bundled: RenderThemeRegistry = {
        guard let manifestURL = RendererResources.themeManifestURL,
              let data = try? Data(contentsOf: manifestURL),
              let registry = try? RenderThemeRegistry(manifestData: data) else {
            return .fallback
        }
        return registry
    }()

    private static let fallback = RenderThemeRegistry(descriptors: [
        Descriptor(
            theme: .cleanLight,
            localizationKey: "render_theme.clean_light",
            defaultTitle: "Clean Light",
            appearance: .light,
            stylesheet: "Themes/clean-light/theme.css"
        )
    ])

    let descriptors: [Descriptor]
    private let descriptorsByTheme: [RenderTheme: Descriptor]
    private let themeIDs: Set<String>

    var themes: [RenderTheme] {
        descriptors.map(\.theme)
    }

    init(manifestData: Data) throws {
        let manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)
        guard manifest.schemaVersion == Self.supportedSchemaVersion else {
            throw RegistryError.unsupportedSchemaVersion(manifest.schemaVersion)
        }

        var seenIDs = Set<String>()
        let descriptors = try manifest.themes.map { manifestTheme in
            guard Self.isValidID(manifestTheme.id),
                  seenIDs.insert(manifestTheme.id).inserted,
                  !manifestTheme.localizationKey.isEmpty,
                  !manifestTheme.defaultTitle.isEmpty,
                  Self.isValidStylesheetPath(manifestTheme.stylesheet) else {
                throw RegistryError.invalidDescriptor
            }
            return Descriptor(
                theme: RenderTheme(uncheckedRawValue: manifestTheme.id),
                localizationKey: manifestTheme.localizationKey,
                defaultTitle: manifestTheme.defaultTitle,
                appearance: manifestTheme.appearance,
                stylesheet: manifestTheme.stylesheet
            )
        }
        guard descriptors.first?.theme == .cleanLight else {
            throw RegistryError.missingDefaultTheme
        }
        self.init(descriptors: descriptors)
    }

    func contains(id: String) -> Bool {
        themeIDs.contains(id)
    }

    func descriptor(for theme: RenderTheme) -> Descriptor? {
        descriptorsByTheme[theme]
    }

    private init(descriptors: [Descriptor]) {
        self.descriptors = descriptors
        descriptorsByTheme = Dictionary(
            uniqueKeysWithValues: descriptors.map { ($0.theme, $0) }
        )
        themeIDs = Set(descriptors.map(\.theme.rawValue))
    }

    private static func isValidID(_ id: String) -> Bool {
        guard let first = id.utf8.first,
              (65 ... 90).contains(first) || (97 ... 122).contains(first) else { return false }
        return id.utf8.allSatisfy { byte in
            (48 ... 57).contains(byte)
                || (65 ... 90).contains(byte)
                || (97 ... 122).contains(byte)
        }
    }

    private static func isValidStylesheetPath(_ path: String) -> Bool {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 3,
              components[0] == "Themes",
              components[2] == "theme.css" else { return false }
        return !components[1].isEmpty && components[1].utf8.allSatisfy { byte in
            (48 ... 57).contains(byte) || (97 ... 122).contains(byte) || byte == 45
        }
    }
}

struct RenderThemePreference {
    static let defaultsKey = "Render.theme.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var selectedTheme: RenderTheme {
        guard let rawValue = defaults.string(forKey: Self.defaultsKey) else {
            return .cleanLight
        }
        return RenderTheme(rawValue: rawValue) ?? .cleanLight
    }

    func select(_ theme: RenderTheme) {
        defaults.set(theme.rawValue, forKey: Self.defaultsKey)
    }
}
