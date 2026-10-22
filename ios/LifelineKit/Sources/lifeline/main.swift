import Foundation
import LifelineKit

do {
    let result = try CLI.run(Array(CommandLine.arguments.dropFirst()))
    let handle = result.exitCode == 0 ? FileHandle.standardOutput : FileHandle.standardError
    handle.write(Data(result.output.utf8))
    exit(result.exitCode)
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
