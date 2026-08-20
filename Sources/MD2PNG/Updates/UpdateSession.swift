import Foundation

@MainActor
protocol UpdateSession: AnyObject {
    var status: UpdateStatus { get }
    var isUpdating: Bool { get }
    var onStatusChange: (@MainActor (UpdateStatus) -> Void)? { get set }

    func checkAgain()
    func downloadAvailableUpdate()
    func cancelUpdate()
    func installAndRelaunch()
    func installLater()
    func cancelPreparedInstallationForApplicationTermination(
        completion: @escaping @MainActor () -> Void
    ) -> Bool
    func viewFullReleaseNotes()
    func viewReleasesFallback()

#if DEBUG
    func setStatusForTesting(_ status: UpdateStatus)
#endif
}

extension UpdateSession {
    func downloadAvailableUpdate() {}
    func cancelUpdate() {}
    func installAndRelaunch() {}
    func installLater() {}

    func cancelPreparedInstallationForApplicationTermination(
        completion: @escaping @MainActor () -> Void
    ) -> Bool {
        false
    }

    func viewFullReleaseNotes() {
        viewReleasesFallback()
    }
}
