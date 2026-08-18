import AppKit

struct SplitRenderResult {
    struct Part {
        let image: NSImage
        let slice: RenderSnapshotSlice
    }

    let contentSize: NSSize
    let geometry: RenderSplitGeometry
    let parts: [Part]

    var images: [NSImage] {
        parts.map(\.image)
    }
}
