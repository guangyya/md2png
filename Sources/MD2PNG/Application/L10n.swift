import Foundation

enum PackageResources {
    private static let bundleName = "md2png_MD2PNG.bundle"

    static func packagedBundle(resourcesURL: URL?) -> Bundle? {
        guard let resourcesURL else { return nil }
        return Bundle(
            url: resourcesURL.appendingPathComponent(bundleName, isDirectory: true)
        )
    }

    static var bundle: Bundle {
        packagedBundle(resourcesURL: Bundle.main.resourceURL) ?? Bundle.module
    }
}

enum L10n {
    static func text(
        _ key: String,
        defaultValue: String,
        bundle: Bundle? = nil
    ) -> String {
        (bundle ?? PackageResources.bundle).localizedString(
            forKey: key,
            value: defaultValue,
            table: nil
        )
    }

    static func format(
        _ key: String,
        defaultValue: String,
        bundle: Bundle? = nil,
        _ arguments: CVarArg...
    ) -> String {
        String(
            format: text(key, defaultValue: defaultValue, bundle: bundle),
            arguments: arguments
        )
    }

    static func localizedBundle(
        for language: String,
        resourcesBundle: Bundle? = nil
    ) -> Bundle? {
        let resourcesBundle = resourcesBundle ?? PackageResources.bundle
        let resourceName = resourcesBundle.localizations.first {
            $0.caseInsensitiveCompare(language) == .orderedSame
        } ?? language
        guard let path = resourcesBundle.path(forResource: resourceName, ofType: "lproj") else {
            return nil
        }
        return Bundle(path: path)
    }
}
