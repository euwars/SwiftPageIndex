import Foundation

public struct DocumentSection: Codable, Sendable {
  public var level: Int
  public var title: String
  public var content: String
  public var startIndex: Int
  public var endIndex: Int
  public var lineNumber: Int

  public init(
    level: Int,
    title: String,
    content: String,
    startIndex: Int,
    endIndex: Int,
    lineNumber: Int,
  ) {
    self.level = level
    self.title = title
    self.content = content
    self.startIndex = startIndex
    self.endIndex = endIndex
    self.lineNumber = lineNumber
  }
}
