import Foundation
import XCTest
@testable import MD2PNG

final class MarkdownFileInputTests: XCTestCase {
    func testPickerPresentationAndMenuCopyAreLocalized() throws {
        let english = try XCTUnwrap(L10n.localizedBundle(for: "en"))
        let chinese = try XCTUnwrap(L10n.localizedBundle(for: "zh-Hans"))

        XCTAssertEqual(
            MarkdownFilePickerPresentation.make(localizationBundle: english),
            MarkdownFilePickerPresentation(
                title: "Render Markdown File",
                message: "Choose a Markdown or plain-text file to render locally.",
                prompt: "Render"
            )
        )
        XCTAssertEqual(
            MarkdownFilePickerPresentation.make(localizationBundle: chinese),
            MarkdownFilePickerPresentation(
                title: "渲染 Markdown 文件",
                message: "选择要在本机渲染的 Markdown 或纯文本文件。",
                prompt: "渲染"
            )
        )
    }

    func testSupportedUTF8FilesPreserveExactMarkdownAndRemoveOnlyTheBOM() throws {
        let expectedMarkdown = "\n  # Keep exact whitespace  \n"

        for filenameExtension in ["md", "MARKDOWN", "txt"] {
            let fileURL = URL(fileURLWithPath: "/tmp/source.\(filenameExtension)")
            let data = Data([0xEF, 0xBB, 0xBF]) + Data(expectedMarkdown.utf8)

            XCTAssertEqual(
                try MarkdownFileInput.load(from: fileURL) { _ in data },
                expectedMarkdown
            )
        }
    }

    func testSupportedFileURLUsesExactExtensions() {
        for filenameExtension in ["md", "MARKDOWN", "txt"] {
            XCTAssertTrue(MarkdownFileInput.supports(
                fileURL: URL(fileURLWithPath: "/tmp/source.\(filenameExtension)")
            ))
        }

        for filenameExtension in ["py", "csv", "rtf", "html"] {
            XCTAssertFalse(MarkdownFileInput.supports(
                fileURL: URL(fileURLWithPath: "/tmp/source.\(filenameExtension)")
            ))
        }

        XCTAssertFalse(MarkdownFileInput.supports(
            fileURL: URL(string: "https://example.com/source.md")!
        ))
    }

    @MainActor
    func testPickerDelegateDisablesUnsupportedFilesButKeepsDirectoriesEnabled() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "md2png-picker-\(UUID().uuidString)",
            isDirectory: true
        )
        let markdown = root.appendingPathComponent("source.md")
        let python = root.appendingPathComponent("source.py")
        let extensionDirectory = root.appendingPathComponent(
            "folder.csv",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: extensionDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertTrue(FileManager.default.createFile(
            atPath: markdown.path,
            contents: Data("# Markdown".utf8)
        ))
        XCTAssertTrue(FileManager.default.createFile(
            atPath: python.path,
            contents: Data("print('not markdown')".utf8)
        ))

        let delegate = MarkdownFilePickerDelegate()
        XCTAssertTrue(delegate.panel(NSObject(), shouldEnable: markdown))
        XCTAssertFalse(delegate.panel(NSObject(), shouldEnable: python))
        XCTAssertTrue(delegate.panel(NSObject(), shouldEnable: extensionDirectory))
        XCTAssertNoThrow(try delegate.panel(NSObject(), validate: markdown))
        XCTAssertThrowsError(try delegate.panel(NSObject(), validate: python))
    }

    func testFinderOpenRequestAcceptsExactlyOneFile() throws {
        let expected = URL(fileURLWithPath: "/tmp/source.md")
        XCTAssertEqual(
            try MarkdownFileOpenRequest.singleFileURL(from: [expected]),
            expected
        )

        for urls in [
            [URL](),
            [expected, URL(fileURLWithPath: "/tmp/another.md")]
        ] {
            XCTAssertThrowsError(
                try MarkdownFileOpenRequest.singleFileURL(from: urls)
            ) { error in
                guard case AppError.multipleMarkdownFilesUnsupported = error else {
                    return XCTFail(
                        "Expected multipleMarkdownFilesUnsupported, got \(error)"
                    )
                }
            }
        }
    }

    func testUnsupportedTypeIsRejectedBeforeReading() {
        var didRead = false

        XCTAssertThrowsError(try MarkdownFileInput.load(
            from: URL(fileURLWithPath: "/tmp/source.rtf"),
            readData: { _ in
                didRead = true
                return Data()
            }
        )) { error in
            guard case AppError.unsupportedMarkdownFileType = error else {
                return XCTFail("Expected unsupportedMarkdownFileType, got \(error)")
            }
        }
        XCTAssertFalse(didRead)

        XCTAssertThrowsError(try MarkdownFileInput.load(
            from: URL(string: "https://example.com/source.md")!,
            readData: { _ in
                didRead = true
                return Data("# Remote".utf8)
            }
        )) { error in
            guard case AppError.unsupportedMarkdownFileType = error else {
                return XCTFail("Expected unsupportedMarkdownFileType, got \(error)")
            }
        }
        XCTAssertFalse(didRead)
    }

    func testReadEncodingAndEmptyFailuresUseDistinctSafeErrors() {
        let fileURL = URL(fileURLWithPath: "/Users/private/secret.md")

        XCTAssertThrowsError(try MarkdownFileInput.load(from: fileURL) { _ in
            throw CocoaError(.fileReadNoPermission)
        }) { error in
            guard case AppError.markdownFileReadFailed = error else {
                return XCTFail("Expected markdownFileReadFailed, got \(error)")
            }
            XCTAssertFalse(error.localizedDescription.contains("/Users/private"))
        }

        XCTAssertThrowsError(try MarkdownFileInput.load(from: fileURL) { _ in
            Data([0xC3, 0x28])
        }) { error in
            guard case AppError.markdownFileInvalidEncoding = error else {
                return XCTFail("Expected markdownFileInvalidEncoding, got \(error)")
            }
        }

        XCTAssertThrowsError(try MarkdownFileInput.load(from: fileURL) { _ in
            Data(" \n\t ".utf8)
        }) { error in
            guard case AppError.emptyMarkdownFile = error else {
                return XCTFail("Expected emptyMarkdownFile, got \(error)")
            }
        }
    }

    func testFileErrorsExplainThatClipboardContentIsUnchanged() throws {
        let english = try XCTUnwrap(L10n.localizedBundle(for: "en"))
        let chinese = try XCTUnwrap(L10n.localizedBundle(for: "zh-Hans"))

        for error in [
            AppError.unsupportedMarkdownFileType,
            .markdownFileReadFailed,
            .markdownFileInvalidEncoding,
            .emptyMarkdownFile,
            .multipleMarkdownFilesUnsupported,
            .markdownFileOpenBusy
        ] {
            XCTAssertTrue(error.message(localizationBundle: english).contains(
                "clipboard is unchanged"
            ))
            XCTAssertTrue(error.message(localizationBundle: chinese).contains(
                "剪贴板内容未改变"
            ))
        }
    }
}
