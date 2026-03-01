import Foundation

public protocol DocumentParser: Sendable {
  var documentType: DocumentType { get }
  func canParse(content: Data, mimeType: String?) -> Bool
  func parse(content: Data, sourceURL: String?) async throws -> ParsedDocument
}

extension DocumentParser {
  func countWords(_ text: String) -> Int {
    text.split(whereSeparator: { $0.isWhitespace }).count
  }
}
