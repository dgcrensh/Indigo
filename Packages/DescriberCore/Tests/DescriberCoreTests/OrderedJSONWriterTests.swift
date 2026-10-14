import XCTest

@testable import DescriberCore

final class OrderedJSONWriterTests: XCTestCase {
    func testNestedObjectsKeepKeyOrderAndIndentByTwoSpaces() {
        let value = JSONValue.object([
            ("zebra", .int(1)),
            ("apple", .object([("inner", .string("x")), ("list", .array([.int(1), .int(2)]))])),
        ])
        XCTAssertEqual(
            OrderedJSONWriter.string(value),
            """
            {
              "zebra": 1,
              "apple": {
                "inner": "x",
                "list": [
                  1,
                  2
                ]
              }
            }

            """
        )
    }

    func testEmptyContainers() {
        let value = JSONValue.object([("array", .array([])), ("object", .object([]))])
        XCTAssertEqual(OrderedJSONWriter.string(value), "{\n  \"array\": [],\n  \"object\": {}\n}\n")
        XCTAssertEqual(OrderedJSONWriter.string(.object([])), "{}\n")
        XCTAssertEqual(OrderedJSONWriter.string(.array([])), "[]\n")
    }

    func testNumbers() {
        let value = JSONValue.array([.int(0), .int(-16), .int(1440), .double(1), .double(1.5), .double(-0.25)])
        XCTAssertEqual(OrderedJSONWriter.string(value), "[\n  0,\n  -16,\n  1440,\n  1,\n  1.5,\n  -0.25\n]\n")
    }

    func testLiterals() {
        let value = JSONValue.array([.bool(true), .bool(false), .null])
        XCTAssertEqual(OrderedJSONWriter.string(value), "[\n  true,\n  false,\n  null\n]\n")
    }

    func testStringEscaping() {
        let value = JSONValue.string("Quote \" backslash \\ slash / tab \t newline \n return \r bell \u{07} café 👋")
        XCTAssertEqual(
            OrderedJSONWriter.string(value),
            "\"Quote \\\" backslash \\\\ slash / tab \\t newline \\n return \\r bell \\u0007 café 👋\"\n"
        )
    }

    func testEscapedStringsRoundTripThroughJSONSerialization() throws {
        let original = "a\"b\\c/d\te\nf\u{01}g\u{1F}h é 👋"
        let data = OrderedJSONWriter.data(.array([.string(original)]))
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String])
        XCTAssertEqual(decoded, [original])
    }

    func testOutputEndsWithOneNewline() {
        let output = OrderedJSONWriter.string(.object([("a", .int(1))]))
        XCTAssertTrue(output.hasSuffix("}\n"))
        XCTAssertFalse(output.hasSuffix("\n\n"))
    }
}
