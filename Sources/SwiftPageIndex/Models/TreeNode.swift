import Foundation

public struct TreeNode: Codable, Sendable {
  public var nodeId: String
  public var title: String
  public var summary: String
  public var content: String?
  public var startIndex: Int
  public var endIndex: Int
  public var nodes: [TreeNode]

  public init(
    nodeId: String,
    title: String,
    summary: String,
    content: String? = nil,
    startIndex: Int,
    endIndex: Int,
    nodes: [TreeNode] = [],
  ) {
    self.nodeId = nodeId
    self.title = title
    self.summary = summary
    self.content = content
    self.startIndex = startIndex
    self.endIndex = endIndex
    self.nodes = nodes
  }

  enum CodingKeys: String, CodingKey {
    case nodeId = "node_id"
    case title
    case summary
    case content
    case startIndex = "start_index"
    case endIndex = "end_index"
    case nodes
  }
}
