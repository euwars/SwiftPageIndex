import Foundation

public struct DocumentMetadata: Codable, Sendable {
  public var title: String?
  public var author: String?
  public var createdAt: Date?
  public var pageCount: Int?
  public var wordCount: Int?
  public var sourceUrl: String?
  public var documentType: DocumentType

  public init(
    title: String? = nil,
    author: String? = nil,
    createdAt: Date? = nil,
    pageCount: Int? = nil,
    wordCount: Int? = nil,
    sourceUrl: String? = nil,
    documentType: DocumentType,
  ) {
    self.title = title
    self.author = author
    self.createdAt = createdAt
    self.pageCount = pageCount
    self.wordCount = wordCount
    self.sourceUrl = sourceUrl
    self.documentType = documentType
  }

  enum CodingKeys: String, CodingKey {
    case title, author, createdAt, pageCount, wordCount, sourceUrl, documentType
  }
}
