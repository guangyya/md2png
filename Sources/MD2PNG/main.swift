import AppKit
import Darwin

let application = NSApplication.shared
let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.first == "--self-test" {
    guard arguments.count == 1 else {
        FileHandle.standardError.write(Data("Usage: md2png --self-test\n".utf8))
        exit(64)
    }
    application.setActivationPolicy(.prohibited)
    let delegate = PackagedRenderSelfTestApplicationDelegate()
    application.delegate = delegate
    application.run()
    exit(delegate.exitCode)
} else {
    let delegate = AppDelegate()
    application.delegate = delegate
    application.run()
}
