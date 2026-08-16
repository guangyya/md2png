import Foundation

enum RendererResources {
    static func packagedPageURL(resourcesURL: URL?) -> URL? {
        guard let bundle = PackageResources.packagedBundle(resourcesURL: resourcesURL) else {
            return nil
        }
        return bundle.url(forResource: "renderer", withExtension: "html")
    }

    static var pageURL: URL? {
        packagedPageURL(resourcesURL: Bundle.main.resourceURL)
            ?? PackageResources.bundle.url(forResource: "renderer", withExtension: "html")
    }
}
