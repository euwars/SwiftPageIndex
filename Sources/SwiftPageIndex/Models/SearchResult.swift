import Foundation

public struct SearchResult: Codable, Sendable {
  public var nodeId: String
  public var title: String
  public var content: String
  public var summary: String
  public var score: Double
  public var path: [String]
  public var reasoning: String?

  public init(
    nodeId: String,
    title: String,
    content: String,
    summary: String,
    score: Double,
    path: [String],
    reasoning: String? = nil,
  ) {
    self.nodeId = nodeId
    self.title = title
    self.content = content
    self.summary = summary
    self.score = score
    self.path = path
    self.reasoning = reasoning
  }

  enum CodingKeys: String, CodingKey {
    case nodeId = "node_id"
    case title, content, summary, score, path, reasoning
  }
}
