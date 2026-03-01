import Foundation

public struct SearchOptions: Sendable {
  public var topK: Int
  public var maxIterations: Int
  public var confidenceThreshold: Double
  public var includeReasoning: Bool

  public init(
    topK: Int = 3,
    maxIterations: Int = 5,
    confidenceThreshold: Double = 0.7,
    includeReasoning: Bool = true,
  ) {
    self.topK = topK
    self.maxIterations = maxIterations
    self.confidenceThreshold = confidenceThreshold
    self.includeReasoning = includeReasoning
  }
}
