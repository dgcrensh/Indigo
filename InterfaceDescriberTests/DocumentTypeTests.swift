import XCTest

@testable import InterfaceDescriber

final class DocumentTypeTests: XCTestCase {
    @MainActor
    func testDocumentReadsProjectPackages() {
        XCTAssertTrue(Document.readableTypes.contains(AppIdentity.documentTypeIdentifier))
    }

    @MainActor
    func testProjectTypeIsAPackageWithTheExpectedExtension() throws {
        let declarations = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "UTExportedTypeDeclarations") as? [[String: Any]]
        )
        let project = try XCTUnwrap(
            declarations.first { $0["UTTypeIdentifier"] as? String == AppIdentity.documentTypeIdentifier }
        )
        let conformsTo = try XCTUnwrap(project["UTTypeConformsTo"] as? [String])
        XCTAssertTrue(conformsTo.contains("com.apple.package"))
        let tags = try XCTUnwrap(project["UTTypeTagSpecification"] as? [String: Any])
        XCTAssertEqual(tags["public.filename-extension"] as? [String], [AppIdentity.fileExtension])
    }
}
