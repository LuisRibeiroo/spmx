import ArgumentParser
import Foundation
import PSPMCore

struct DerivedDataPathCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "derived-data-path",
        abstract: "Compute the deterministic Xcode DerivedData path for a workspace or project."
    )

    @Argument(
        help: "Path to a .xcworkspace, .xcodeproj, or project directory (defaults to current directory)."
    )
    var path: String = "."

    func run() throws {
        let containerPath = try DerivedDataPathCalculator.resolveContainerPath(from: path)
        let derivedDataURL = DerivedDataPathCalculator.derivedDataURL(forContainerPath: containerPath)
        print(derivedDataURL.path)
    }
}
