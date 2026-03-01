import Foundation

public struct TreeBuilderOptions: Sendable {
  public var generateSummaries: Bool
  public var maxSummaryLength: Int
  public var includeContent: Bool

  public init(generateSummaries: Bool = true, maxSummaryLength: Int = 500, includeContent: Bool = false) {
    self.generateSummaries = generateSummaries
    self.maxSummaryLength = maxSummaryLength
    self.includeContent = includeContent
  }
}

public struct TreeBuilder: Sendable {
  private let options: TreeBuilderOptions

  public init(options: TreeBuilderOptions = TreeBuilderOptions()) {
    self.options = options
  }

  public func buildTree(document: ParsedDocument) -> [TreeNode] {
    var counter = 0

    if document.sections.isEmpty {
      return [TreeNode(
        nodeId: generateNodeId(&counter),
        title: document.metadata.title ?? "Document",
        summary: createSummary(document.content),
        content: options.includeContent ? document.content : nil,
        startIndex: 1,
        endIndex: 1,
        nodes: [],
      )]
    }

    let sortedSections = document.sections.sorted { $0.startIndex < $1.startIndex }
    return buildHierarchy(
      sections: sortedSections,
      start: 0,
      end: sortedSections.count,
      fullContent: document.content,
      counter: &counter,
    )
  }

  private func buildHierarchy(
    sections: [DocumentSection], start: Int, end: Int,
    fullContent: String, counter: inout Int,
  ) -> [TreeNode] {
    guard start < end else { return [] }
    var nodes: [TreeNode] = []
    var i = start

    while i < end {
      let section = sections[i]
      let currentLevel = section.level

      var childEnd = i + 1
      while childEnd < end, sections[childEnd].level > currentLevel {
        childEnd += 1
      }

      let contentEnd = i + 1 < sections.count ? sections[i + 1].startIndex : section.endIndex
      let sectionContent: String
      if section.startIndex < fullContent.count, contentEnd <= fullContent.count {
        let startIdx = fullContent.index(fullContent.startIndex, offsetBy: min(section.startIndex, fullContent.count))
        let endIdx = fullContent.index(fullContent.startIndex, offsetBy: min(contentEnd, fullContent.count))
        sectionContent = String(fullContent[startIdx ..< endIdx])
      } else {
        sectionContent = section.content
      }

      let childNodes = buildHierarchy(
        sections: sections,
        start: i + 1,
        end: childEnd,
        fullContent: fullContent,
        counter: &counter,
      )

      let node = TreeNode(
        nodeId: generateNodeId(&counter),
        title: section.title,
        summary: createSummary(section.content.isEmpty ? sectionContent : section.content),
        content: options.includeContent ? sectionContent : nil,
        startIndex: section.lineNumber > 0 ? section.lineNumber : i + 1,
        endIndex: childNodes
          .isEmpty ? (section.lineNumber > 0 ? section.lineNumber : i + 1) : getMaxEndIndex(childNodes),
        nodes: childNodes,
      )

      nodes.append(node)
      i = childEnd
    }

    return nodes
  }

  private func getMaxEndIndex(_ nodes: [TreeNode]) -> Int {
    var maxIdx = 0
    for node in nodes {
      maxIdx = max(maxIdx, node.endIndex)
      if !node.nodes.isEmpty {
        maxIdx = max(maxIdx, getMaxEndIndex(node.nodes))
      }
    }
    return maxIdx
  }

  private func generateNodeId(_ counter: inout Int) -> String {
    let id = String(format: "%04d", counter)
    counter += 1
    return id
  }

  private func createSummary(_ content: String) -> String {
    guard options.generateSummaries, !content.isEmpty else { return "" }

    var summary = content
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .replacingOccurrences(of: "[#*_`]", with: "", options: .regularExpression)
      .trimmingCharacters(in: .whitespaces)

    let maxLength = options.maxSummaryLength
    if summary.count > maxLength {
      let truncated = String(summary.prefix(maxLength))
      if let lastSentence = truncated.range(of: ". ", options: .backwards),
         truncated.distance(from: truncated.startIndex, to: lastSentence.lowerBound) > maxLength / 2
      {
        summary = String(truncated[..<truncated.index(after: lastSentence.lowerBound)])
      } else {
        summary = truncated + "..."
      }
    }

    return summary
  }

  // MARK: - Utility methods

  public func flattenTree(_ nodes: [TreeNode]) -> [TreeNode] {
    var result: [TreeNode] = []
    for node in nodes {
      result.append(node)
      if !node.nodes.isEmpty {
        result.append(contentsOf: flattenTree(node.nodes))
      }
    }
    return result
  }

  public func findNodeById(_ nodes: [TreeNode], nodeId: String) -> TreeNode? {
    for node in nodes {
      if node.nodeId == nodeId { return node }
      if !node.nodes.isEmpty, let found = findNodeById(node.nodes, nodeId: nodeId) {
        return found
      }
    }
    return nil
  }

  public func getNodePath(_ nodes: [TreeNode], nodeId: String, path: [String] = []) -> [String]? {
    for node in nodes {
      let currentPath = path + [node.title]
      if node.nodeId == nodeId { return currentPath }
      if !node.nodes.isEmpty, let found = getNodePath(node.nodes, nodeId: nodeId, path: currentPath) {
        return found
      }
    }
    return nil
  }

  public func getAllChildrenIds(_ node: TreeNode) -> [String] {
    var ids: [String] = []
    for child in node.nodes {
      ids.append(child.nodeId)
      ids.append(contentsOf: getAllChildrenIds(child))
    }
    return ids
  }

  public func getTreeStats(_ nodes: [TreeNode]) -> (totalNodes: Int, maxDepth: Int, avgChildrenPerNode: Double) {
    var totalNodes = 0
    var maxDepth = 0
    var totalChildren = 0
    var nonLeafNodes = 0

    func analyze(_ nodeList: [TreeNode], depth: Int) {
      for node in nodeList {
        totalNodes += 1
        maxDepth = max(maxDepth, depth)
        if !node.nodes.isEmpty {
          totalChildren += node.nodes.count
          nonLeafNodes += 1
          analyze(node.nodes, depth: depth + 1)
        }
      }
    }
    analyze(nodes, depth: 1)

    return (totalNodes, maxDepth, nonLeafNodes > 0 ? Double(totalChildren) / Double(nonLeafNodes) : 0)
  }

  public func printTree(_ nodes: [TreeNode], indent: Int = 0) -> String {
    var output = ""
    let prefix = String(repeating: "  ", count: indent)
    for node in nodes {
      output += "\(prefix)[\(node.nodeId)] \(node.title)\n"
      if !node.nodes.isEmpty {
        output += printTree(node.nodes, indent: indent + 1)
      }
    }
    return output
  }
}
