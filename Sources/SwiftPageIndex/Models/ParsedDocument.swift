import Foundation

public struct ParsedDocument: Sendable {
  public var content: String
  public var metadata: DocumentMetadata
  public var sections: [DocumentSection]

  public init(content: String, metadata: DocumentMetadata, sections: [DocumentSection]) {
    self.content = content
    self.metadata = metadata
    self.sections = sections
  }
}
