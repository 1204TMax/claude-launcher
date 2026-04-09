import Foundation

struct PTYSession {
    enum BootstrapStatus: String {
        case spawned
        case initialOutputObserved
        case readyForBootstrap
        case renameSent
        case preloadSent
        case interactiveReady
        case failed
    }

    let id: UUID
    let sessionName: String
    let workingDirectory: String
    let launchedAt: Date
    var bootstrapStatus: BootstrapStatus
    var pid: Int32?
}
