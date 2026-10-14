import Foundation

/// The app's name, document extension and document type in one place, so a rename is a one-line change here plus
/// the matching entries in `Info.plist` (roadmap decision D5).
enum AppIdentity {
    static let appName = "Interface Describer"
    static let fileExtension = "uidesc"
    static let documentTypeIdentifier = "com.dgcrensh.interface-describer.project"
}
