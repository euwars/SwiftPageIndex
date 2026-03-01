import Foundation
@testable import SwiftPageIndex
import Testing

@Suite("TreeBuilder Tests")
struct TreeBuilderTests {
  @Test("Build tree from sections")
  func buildTreeFromSections() {
    let sections = [
      DocumentSection(level: 1, title: "Title", content: "Intro", startIndex: 0, endIndex: 20, lineNumber: 1),
      DocumentSection(level: 2, title: "Section A", content: "Content A", startIndex: 21, endIndex: 50, lineNumber: 5),
      DocumentSection(level: 2, title: "Section B", content: "Content B", startIndex: 51, endIndex: 80, lineNumber: 10),
      DocumentSection(
        level: 3,
        title: "Subsection B1",
        content: "Sub content",
        startIndex: 81,
        endIndex: 100,
        lineNumber: 15,
      ),
    ]
    let doc = ParsedDocument(
      content: String(repeating: "x", count: 100),
      metadata: DocumentMetadata(title: "Test", documentType: .markdown),
      sections: sections,
    )

    let builder = TreeBuilder()
    let tree = builder.buildTree(document: doc)

    #expect(tree.count == 1)
    #expect(tree[0].title == "Title")
    #expect(tree[0].nodes.count == 2)
    #expect(tree[0].nodes[0].title == "Section A")
    #expect(tree[0].nodes[1].title == "Section B")
    #expect(tree[0].nodes[1].nodes.count == 1)
    #expect(tree[0].nodes[1].nodes[0].title == "Subsection B1")
  }

  @Test("Node IDs are zero-padded sequential")
  func nodeIdsSequential() {
    let sections = [
      DocumentSection(level: 1, title: "A", content: "", startIndex: 0, endIndex: 10, lineNumber: 1),
      DocumentSection(level: 2, title: "B", content: "", startIndex: 11, endIndex: 20, lineNumber: 2),
      DocumentSection(level: 2, title: "C", content: "", startIndex: 21, endIndex: 30, lineNumber: 3),
    ]
    let doc = ParsedDocument(
      content: String(repeating: "x", count: 30),
      metadata: DocumentMetadata(documentType: .text),
      sections: sections,
    )

    let builder = TreeBuilder()
    let tree = builder.buildTree(document: doc)
    let flat = builder.flattenTree(tree)

    let ids = flat.map(\.nodeId)
    #expect(ids.allSatisfy { $0.count == 4 })
    #expect(Set(ids).count == ids.count)
  }

  @Test("Empty sections creates single root node")
  func emptySections() {
    let doc = ParsedDocument(
      content: "Some content",
      metadata: DocumentMetadata(title: "MyDoc", documentType: .text),
      sections: [],
    )

    let builder = TreeBuilder()
    let tree = builder.buildTree(document: doc)

    #expect(tree.count == 1)
    #expect(tree[0].title == "MyDoc")
    #expect(tree[0].nodes.isEmpty)
  }

  @Test("FlattenTree returns all nodes")
  func flattenTree() {
    let child = TreeNode(nodeId: "0001", title: "Child", summary: "", startIndex: 1, endIndex: 1, nodes: [])
    let root = TreeNode(nodeId: "0000", title: "Root", summary: "", startIndex: 1, endIndex: 1, nodes: [child])

    let builder = TreeBuilder()
    let flat = builder.flattenTree([root])

    #expect(flat.count == 2)
    #expect(flat[0].nodeId == "0000")
    #expect(flat[1].nodeId == "0001")
  }

  @Test("FindNodeById works recursively")
  func findNodeById() {
    let grandchild = TreeNode(nodeId: "0002", title: "GC", summary: "", startIndex: 1, endIndex: 1, nodes: [])
    let child = TreeNode(nodeId: "0001", title: "C", summary: "", startIndex: 1, endIndex: 1, nodes: [grandchild])
    let root = TreeNode(nodeId: "0000", title: "R", summary: "", startIndex: 1, endIndex: 1, nodes: [child])

    let builder = TreeBuilder()
    #expect(builder.findNodeById([root], nodeId: "0002")?.title == "GC")
    #expect(builder.findNodeById([root], nodeId: "9999") == nil)
  }

  @Test("GetNodePath returns breadcrumb")
  func getNodePath() {
    let grandchild = TreeNode(nodeId: "0002", title: "GC", summary: "", startIndex: 1, endIndex: 1, nodes: [])
    let child = TreeNode(nodeId: "0001", title: "C", summary: "", startIndex: 1, endIndex: 1, nodes: [grandchild])
    let root = TreeNode(nodeId: "0000", title: "R", summary: "", startIndex: 1, endIndex: 1, nodes: [child])

    let builder = TreeBuilder()
    let path = builder.getNodePath([root], nodeId: "0002")
    #expect(path == ["R", "C", "GC"])
  }

  @Test("GetTreeStats calculates correctly")
  func getTreeStats() {
    let child1 = TreeNode(nodeId: "0001", title: "C1", summary: "", startIndex: 1, endIndex: 1, nodes: [])
    let child2 = TreeNode(nodeId: "0002", title: "C2", summary: "", startIndex: 1, endIndex: 1, nodes: [])
    let root = TreeNode(nodeId: "0000", title: "R", summary: "", startIndex: 1, endIndex: 1, nodes: [child1, child2])

    let builder = TreeBuilder()
    let stats = builder.getTreeStats([root])

    #expect(stats.totalNodes == 3)
    #expect(stats.maxDepth == 2)
    #expect(stats.avgChildrenPerNode == 2.0)
  }

  @Test("PrintTree formats correctly")
  func printTree() {
    let child = TreeNode(nodeId: "0001", title: "Child", summary: "", startIndex: 1, endIndex: 1, nodes: [])
    let root = TreeNode(nodeId: "0000", title: "Root", summary: "", startIndex: 1, endIndex: 1, nodes: [child])

    let builder = TreeBuilder()
    let output = builder.printTree([root])

    #expect(output.contains("[0000] Root"))
    #expect(output.contains("  [0001] Child"))
  }

  @Test("Summary truncation at sentence boundary")
  func summaryTruncation() {
    let longContent = "This is the first sentence. This is the second sentence. " +
      String(repeating: "More content here. ", count: 30)

    let doc = ParsedDocument(
      content: longContent,
      metadata: DocumentMetadata(documentType: .text),
      sections: [],
    )

    let builder = TreeBuilder(options: TreeBuilderOptions(maxSummaryLength: 100))
    let tree = builder.buildTree(document: doc)

    #expect(tree[0].summary.count <= 110)
  }

  @Test("Fixture parity: joyzai-simple structure shape")
  func fixtureParityStructure() throws {
    let optionalURL = Bundle.module.url(forResource: "joyzai-simple", withExtension: "json", subdirectory: "Fixtures")
    let fixtureURL = try #require(optionalURL)
    let data = try Data(contentsOf: fixtureURL)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let doc = try decoder.decode(IndexedDocument.self, from: data)

    #expect(doc.structure.count == 1)
    let root = doc.structure[0]
    #expect(!root.nodes.isEmpty)

    let builder = TreeBuilder()
    let allNodes = builder.flattenTree(doc.structure)
    for node in allNodes {
      #expect(node.nodeId.count == 4, "Node ID '\(node.nodeId)' should be 4 digits")
    }
  }
}
