import Foundation
import XCTest

final class SourceLayoutTests: XCTestCase {
    func testSwiftSourceFilesStayWithinLineLimit() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourcesRoot = packageRoot.appendingPathComponent("Sources/health")

        let enumerator = FileManager.default.enumerator(
            at: sourcesRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var violations: [String] = []

        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else { continue }

            let fileContents = try String(contentsOf: fileURL)
            let lineCount = fileContents.split(
                separator: "\n",
                omittingEmptySubsequences: false
            ).count

            if lineCount > 300 {
                let relativePath = fileURL.path.replacingOccurrences(
                    of: packageRoot.path + "/",
                    with: ""
                )
                violations.append("\(relativePath): \(lineCount) lines")
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            """
            Swift source files must stay at or below 300 lines:
            \(violations.joined(separator: "\n"))
            """
        )
    }
}
