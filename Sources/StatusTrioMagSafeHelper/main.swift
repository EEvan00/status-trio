import Foundation
import MagSafeSMC

let directory = URL(fileURLWithPath: "/Users/Shared/Status Trio", isDirectory: true)
let requestURL = directory.appendingPathComponent("magsafe-led-request")
let resultURL = directory.appendingPathComponent("magsafe-led-result")

guard let request = try? MagSafeLEDRequestFile.consume(at: requestURL) else {
    exit(EXIT_FAILURE)
}

let result = MagSafeLEDResult(
    id: request.id,
    succeeded: MagSafeSMC.setLEDMode(request.command)
)
do {
    try Data(result.configuration.utf8).write(to: resultURL, options: .atomic)
    exit(result.succeeded ? EXIT_SUCCESS : EXIT_FAILURE)
} catch {
    exit(EXIT_FAILURE)
}
