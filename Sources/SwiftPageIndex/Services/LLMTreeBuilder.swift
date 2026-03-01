import AnyLanguageModel
import Foundation

public struct LLMTreeBuilder: Sendable {
  private let llm: PageIndexLLM

  public init(llm: PageIndexLLM) {
    self.llm = llm
  }

  public func buildTree(document: ParsedDocument) async throws -> [TreeNode] {
    let pages = splitIntoPages(document.content, pageCount: document.metadata.pageCount)
    let tocItems = try await generateTocFromContent(pages)
    let flatNodes = tocToFlatNodes(tocItems, totalPages: pages.count)
    var tree = buildHierarchyFromStructure(flatNodes)
    try await generateSummaries(&tree, pages: pages)
    return tree
  }

  // MARK: - Split into pages

  private func splitIntoPages(_ content: String, pageCount: Int?) -> [String] {
    if content.contains("\u{0C}") { // form feed
      return content.components(separatedBy: "\u{0C}").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
    let targetPages = pageCount ?? max(1, Int(ceil(Double(content.count) / 3000.0)))
    let chunkSize = Int(ceil(Double(content.count) / Double(targetPages)))
    var pages: [String] = []
    var startIndex = content.startIndex
    while startIndex < content.endIndex {
      let endIndex = content.index(startIndex, offsetBy: chunkSize, limitedBy: content.endIndex) ?? content.endIndex
      pages.append(String(content[startIndex ..< endIndex]))
      startIndex = endIndex
    }
    return pages
  }

  // MARK: - TOC generation

  private func generateTocFromContent(_ pages: [String]) async throws -> [TocItemInternal] {
    var allItems: [TocItemInternal] = []
    let maxPagesPerGroup = 5
    let groups = groupPages(pages, maxPerGroup: maxPagesPerGroup)

    for groupIdx in 0 ..< groups.count {
      let group = groups[groupIdx]
      if groupIdx == 0 {
        let items = try await generateTocInit(text: group.text, startPage: group.startPage)
        allItems.append(contentsOf: items)
      } else {
        let items = try await generateTocContinue(existingToc: allItems, text: group.text, startPage: group.startPage)
        allItems.append(contentsOf: items)
      }
    }
    return allItems
  }

  private struct PageGroup {
    let text: String
    let startPage: Int
  }

  private func groupPages(_ pages: [String], maxPerGroup: Int) -> [PageGroup] {
    var groups: [PageGroup] = []
    var i = 0
    while i < pages.count {
      let groupPages = Array(pages[i ..< min(i + maxPerGroup, pages.count)])
      var text = ""
      for (idx, page) in groupPages.enumerated() {
        let pageNum = i + idx + 1
        text += "<physical_index_\(pageNum)>\n\(page)\n</physical_index_\(pageNum)>\n\n"
      }
      groups.append(PageGroup(text: text, startPage: i + 1))
      i += maxPerGroup
    }
    return groups
  }

  private func generateTocInit(text: String, startPage: Int) async throws -> [TocItemInternal] {
    let prompt = """
    You are an expert document analyzer. Your task is to identify the main sections and subsections from this document text.

    Look for:
    - Major headings and titles (often in ALL CAPS or on their own line)
    - Section headers like "SUMMARIZED FINANCIAL RESULTS", "DISCUSSION OF...", "GUIDANCE AND OUTLOOK"
    - The document title at the beginning
    - Subsections indicated by clear topic changes or headers

    The structure index represents hierarchy:
    - "1", "2", "3" for main sections
    - "1.1", "1.2" for subsections
    - "1.1.1" for sub-subsections

    The provided text contains tags like <physical_index_X> to indicate page numbers.

    Important:
    - Include the main document title as section "1"
    - Look for ALL CAPS headers as major sections
    - Clean up titles by removing extra tabs/spaces but keep the original wording

    Text to analyze:
    \(text)
    """

    do {
      let response = try await llm.generate(prompt, as: TocResponse.self, temperature: 0.1)
      return response.items.compactMap { item in
        let title = item.title.replacingOccurrences(of: "[\\t\\s]+", with: " ", options: .regularExpression)
          .trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        return TocItemInternal(structure: item.structure, title: title, physicalIndex: item.physicalIndex)
      }
    } catch {
      // Fallback: try plain text + JSON decode
      return try await generateTocFallback(text: text, startPage: startPage)
    }
  }

  private func generateTocContinue(
    existingToc: [TocItemInternal],
    text: String,
    startPage _: Int,
  ) async throws -> [TocItemInternal] {
    let lastStructure = existingToc.last?.structure ?? "0"
    let recentToc = existingToc.suffix(5).map { ["structure": $0.structure, "title": $0.title] }

    let prompt = """
    You are continuing to analyze a document and extract section headers.

    Previous sections already found:
    \(recentToc)

    The last structure index was: \(lastStructure)

    Continue extracting NEW sections from the following text pages. Only return sections NOT already listed above.

    Look for:
    - Major headings in ALL CAPS
    - Section headers indicating new topics

    The text contains <physical_index_X> tags indicating page numbers.

    Text to analyze:
    \(text)
    """

    do {
      let response = try await llm.generate(prompt, as: TocResponse.self, temperature: 0.1)
      return response.items.compactMap { item in
        let title = item.title.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
          .trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        return TocItemInternal(structure: item.structure, title: title, physicalIndex: item.physicalIndex)
      }
    } catch {
      return []
    }
  }

  private func generateTocFallback(text: String, startPage _: Int) async throws -> [TocItemInternal] {
    let prompt = """
    Analyze this document text and return a JSON array of sections:
    [{"structure": "1", "title": "Section Title", "physical_index": 1}]

    Text:
    \(text.prefix(8000))
    """

    let response = try await llm.chat(prompt, temperature: 0.1)
    guard let data = response.data(using: .utf8) else { return [] }

    struct FallbackItem: Decodable {
      let structure: String
      let title: String
      let physical_index: Int
    }

    do {
      let items = try JSONDecoder().decode([FallbackItem].self, from: data)
      return items.map { TocItemInternal(structure: $0.structure, title: $0.title, physicalIndex: $0.physical_index) }
    } catch {
      return []
    }
  }

  // MARK: - Build hierarchy

  private struct TocItemInternal {
    let structure: String
    let title: String
    let physicalIndex: Int
  }

  private func tocToFlatNodes(_ items: [TocItemInternal], totalPages: Int) -> [(item: TocItemInternal, endIndex: Int)] {
    items.enumerated().map { idx, item in
      let nextItem = idx + 1 < items.count ? items[idx + 1] : nil
      let endIndex = nextItem?.physicalIndex ?? totalPages
      return (item: item, endIndex: endIndex)
    }
  }

  private func buildHierarchyFromStructure(_ flatNodes: [(item: TocItemInternal, endIndex: Int)]) -> [TreeNode] {
    guard !flatNodes.isEmpty else { return [] }
    var tree: [TreeNode] = []
    var nodeStack: [(node: TreeNode, level: Int, index: Int)] = []
    var counter = 0

    for flat in flatNodes {
      let level = flat.item.structure.count(where: { $0 == "." })

      let node = TreeNode(
        nodeId: String(format: "%04d", counter),
        title: flat.item.title,
        summary: "",
        startIndex: flat.item.physicalIndex,
        endIndex: flat.endIndex,
        nodes: [],
      )
      counter += 1

      while !nodeStack.isEmpty, nodeStack.last!.level >= level {
        nodeStack.removeLast()
      }

      if nodeStack.isEmpty {
        tree.append(node)
        nodeStack.append((node: node, level: level, index: tree.count - 1))
      } else {
        // We need to mutate the tree. Use indices path.
        appendNode(&tree, node: node, stack: nodeStack)
        nodeStack.append((node: node, level: level, index: 0))
      }
    }

    updateParentEndIndices(&tree)
    return tree
  }

  private func appendNode(_ tree: inout [TreeNode], node: TreeNode, stack: [(node: TreeNode, level: Int, index: Int)]) {
    // Navigate through the stack to find and append to the correct parent
    if stack.isEmpty { return }

    /// Build path of indices
    func findAndAppend(nodes: inout [TreeNode], targetId: String, child: TreeNode) -> Bool {
      for i in 0 ..< nodes.count {
        if nodes[i].nodeId == targetId {
          nodes[i].nodes.append(child)
          return true
        }
        if findAndAppend(nodes: &nodes[i].nodes, targetId: targetId, child: child) {
          return true
        }
      }
      return false
    }

    let parentId = stack.last!.node.nodeId
    _ = findAndAppend(nodes: &tree, targetId: parentId, child: node)
  }

  private func updateParentEndIndices(_ nodes: inout [TreeNode]) {
    for i in 0 ..< nodes.count {
      if !nodes[i].nodes.isEmpty {
        updateParentEndIndices(&nodes[i].nodes)
        let maxChildEnd = nodes[i].nodes.map(\.endIndex).max() ?? 0
        nodes[i].endIndex = max(nodes[i].endIndex, maxChildEnd)
      }
    }
  }

  // MARK: - Summary generation

  private func generateSummaries(_ tree: inout [TreeNode], pages: [String]) async throws {
    let allNodes = flattenTree(tree)
    let batchSize = 5

    for batchStart in stride(from: 0, to: allNodes.count, by: batchSize) {
      let batchEnd = min(batchStart + batchSize, allNodes.count)
      let batch = Array(allNodes[batchStart ..< batchEnd])

      try await withThrowingTaskGroup(of: (String, String).self) { group in
        for node in batch {
          group.addTask {
            let startIdx = max(0, node.startIndex - 1)
            let endIdx = min(pages.count, node.endIndex)
            let nodeContent = pages[startIdx ..< endIdx].joined(separator: "\n\n")
            let truncated = String(nodeContent.prefix(4000))

            let prompt = """
            Summarize the following section titled "\(node
              .title)" in 2-3 sentences. Focus on the key information and main points.

            Content:
            \(truncated)

            Provide a concise summary:
            """

            let summary = try await llm.chat(prompt, temperature: 0.3, maxTokens: 300)
            return (node.nodeId, summary.trimmingCharacters(in: .whitespacesAndNewlines))
          }
        }

        for try await (nodeId, summary) in group {
          updateSummary(in: &tree, nodeId: nodeId, summary: summary)
        }
      }
    }
  }

  private func updateSummary(in nodes: inout [TreeNode], nodeId: String, summary: String) {
    for i in 0 ..< nodes.count {
      if nodes[i].nodeId == nodeId {
        nodes[i].summary = summary
        return
      }
      updateSummary(in: &nodes[i].nodes, nodeId: nodeId, summary: summary)
    }
  }

  private func flattenTree(_ nodes: [TreeNode]) -> [TreeNode] {
    var result: [TreeNode] = []
    for node in nodes {
      result.append(node)
      if !node.nodes.isEmpty {
        result.append(contentsOf: flattenTree(node.nodes))
      }
    }
    return result
  }
}
