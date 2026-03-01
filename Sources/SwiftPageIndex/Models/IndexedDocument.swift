import Foundation

public struct IndexedDocument: Codable, Sendable {
  public var docName: String
  public var structure: [TreeNode]
  public var metadata: DocumentMetadata?
  public var id: String?
  public var createdAt: Date?
  public var updatedAt: Date?

  public init(
    docName: String,
    structure: [TreeNode],
    metadata: DocumentMetadata? = nil,
    id: String? = nil,
    createdAt: Date? = nil,
    updatedAt: Date? = nil,
  ) {
    self.docName = docName
    self.structure = structure
    self.metadata = metadata
    self.id = id
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  enum CodingKeys: String, CodingKey {
    case docName = "doc_name"
    case structure
    case metadata
    case id
    case createdAt
    case updatedAt
  }
}
