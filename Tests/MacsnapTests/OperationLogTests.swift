import XCTest
@testable import MacsnapCore

final class OperationLogTests: XCTestCase {
    func testSerializationRoundTrip() throws {
        var log = OperationLog(version: 1, index: 2, nextId: 10, nextMarker: 3, previewWidth: 1920, previewHeight: 1080)
        let ann1 = Annotation(
            id: 1,
            kind: .arrow,
            start: CGPoint(x: 10, y: 20),
            end: CGPoint(x: 100, y: 200),
            text: "Hello",
            colorHex: "#ff375f",
            size: 4.0
        )
        let ann2 = Annotation(
            id: 2,
            kind: .marker,
            start: CGPoint(x: 50, y: 50),
            number: 1
        )
        let cut = CutOp(orientation: .horizontal, sourceStart: 100, sourceEnd: 150, logicalStart: 50, logicalEnd: 75)

        log.ops = [
            Operation(type: .annotate, annotations: [ann1]),
            Operation(type: .cut, cut: cut),
            Operation(type: .annotate, annotations: [ann2])
        ]

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(log)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(OperationLog.self, from: data)

        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.index, 2)
        XCTAssertEqual(decoded.nextId, 10)
        XCTAssertEqual(decoded.nextMarker, 3)
        XCTAssertEqual(decoded.previewWidth, 1920)
        XCTAssertEqual(decoded.previewHeight, 1080)
        XCTAssertEqual(decoded.ops.count, 3)

        // Verify replay
        let state = decoded.replay()
        XCTAssertEqual(state.annotations.count, 1)
        XCTAssertEqual(state.cuts.count, 1)
    }

    func testOmasnapCompatibility() throws {
        // Sample JSON directly from omasnap style
        let jsonStr = """
        {
          "version": 1,
          "index": 1,
          "nextId": "42",
          "nextMarker": 2,
          "previewWidth": 1440,
          "previewHeight": 900,
          "ops": [
            {
              "type": "background",
              "style": "aurora",
              "shadow": true
            },
            {
              "type": "annotate",
              "annotation": {
                "id": "1",
                "tool": "text",
                "start": [100.0, 200.0],
                "end": [300.0, 250.0],
                "color": "#ffffffff",
                "size": 16.0,
                "text": "Bug here",
                "textFont": "jetbrains-mono",
                "textBackground": "pill"
              }
            }
          ]
        }
        """

        let data = jsonStr.data(using: .utf8)!
        let log = try JSONDecoder().decode(OperationLog.self, from: data)
        XCTAssertEqual(log.nextId, 42)
        XCTAssertEqual(log.ops.count, 2)
        XCTAssertEqual(log.ops[0].type, .background)
        XCTAssertEqual(log.ops[0].background, .aurora)
        XCTAssertEqual(log.ops[1].type, .annotate)
        XCTAssertEqual(log.ops[1].annotations[0].kind, .text)
        XCTAssertEqual(log.ops[1].annotations[0].textFont, .jetbrainsMono)
    }
}
