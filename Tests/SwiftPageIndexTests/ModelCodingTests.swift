import Foundation
@testable import SwiftPageIndex
import Testing

@Suite("Model Coding Tests")
struct ModelCodingTests {
  @Test("TreeNode encodes with snake_case keys")
  func treeNodeSnakeCaseKeys() throws {
    let node = TreeNode(
      nodeId: "0001",
      title: "Test Section",
      summary: "A summary",
      startIndex: 1,
      endIndex: 5,
      nodes: [],
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(node)
    let json = try #require(String(data: data, encoding: .utf8))

    #expect(json.contains("\"node_id\""))
    #expect(json.contains("\"start_index\""))
    #expect(json.contains("\"end_index\""))
    #expect(!json.contains("\"nodeId\""))
    #expect(!json.contains("\"startIndex\""))
  }

  @Test("TreeNode round-trip encoding")
  func treeNodeRoundTrip() throws {
    let child = TreeNode(
      nodeId: "0002",
      title: "Child",
      summary: "Child summary",
      startIndex: 2,
      endIndex: 3,
      nodes: [],
    )
    let parent = TreeNode(
      nodeId: "0001",
      title: "Parent",
      summary: "Parent summary",
      content: "Some content",
      startIndex: 1,
      endIndex: 5,
      nodes: [child],
    )

    let encoder = JSONEncoder()
    let data = try encoder.encode(parent)
    let decoder = JSONDecoder()
    let decoded = try decoder.decode(TreeNode.self, from: data)

    #expect(decoded.nodeId == "0001")
    #expect(decoded.title == "Parent")
    #expect(decoded.content == "Some content")
    #expect(decoded.nodes.count == 1)
    #expect(decoded.nodes[0].nodeId == "0002")
  }

  @Test("IndexedDocument encodes with snake_case doc_name")
  func indexedDocumentSnakeCase() throws {
    let doc = IndexedDocument(
      docName: "test-doc",
      structure: [],
      metadata: DocumentMetadata(title: "Test", documentType: .markdown),
      id: "test-doc",
      createdAt: Date(),
      updatedAt: Date(),
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(doc)
    let json = try #require(String(data: data, encoding: .utf8))

    #expect(json.contains("\"doc_name\""))
    #expect(!json.contains("\"docName\""))
  }

  @Test("Decode fixture JSON from TS output")
  func decodeFixture() throws {
    let optionalURL = Bundle.module.url(forResource: "joyzai-simple", withExtension: "json", subdirectory: "Fixtures")
    let fixtureURL = try #require(optionalURL)
    let data = try Data(contentsOf: fixtureURL)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let doc = try decoder.decode(IndexedDocument.self, from: data)

    #expect(doc.docName == "joyzai-simple")
    #expect(doc.id == "joyzai-simple")
    #expect(!doc.structure.isEmpty)

    let root = doc.structure[0]
    #expect(root.title == "JoyzAI - Custom AI Chatbot Platform")
    #expect(root.nodeId == "0040")
    #expect(!root.nodes.isEmpty)
  }

  @Test("SearchResult encodes with snake_case node_id")
  func searchResultSnakeCase() throws {
    let result = SearchResult(
      nodeId: "0001",
      title: "Test",
      content: "Content",
      summary: "Summary",
      score: 0.9,
      path: ["Doc", "Section"],
      reasoning: "Because",
    )

    let encoder = JSONEncoder()
    let data = try encoder.encode(result)
    let json = try #require(String(data: data, encoding: .utf8))

    #expect(json.contains("\"node_id\""))
    #expect(!json.contains("\"nodeId\""))
  }

  @Test("Node IDs are zero-padded 4 digits")
  func nodeIdFormat() {
    #expect(String(format: "%04d", 7) == "0007")
    #expect(String(format: "%04d", 42) == "0042")
    #expect(String(format: "%04d", 1234) == "1234")
  }
}
