import Foundation
@testable import SwiftPageIndex
import Testing

@Suite("Parser Tests")
struct ParserTests {
  @Test("MarkdownParser detects markdown content")
  func markdownDetection() {
    let markdown = """
    # Title

    ## Section 1

    Some content with **bold** text.

    - Item 1
    - Item 2

    ## Section 2

    More content with [a link](https://example.com).
    """

    let parser = MarkdownParser()
    let data = Data(markdown.utf8)
    #expect(parser.canParse(content: data, mimeType: nil))
    #expect(parser.canParse(content: data, mimeType: "text/markdown"))
  }

  @Test("MarkdownParser extracts sections")
  func markdownSections() async throws {
    let markdown = """
    # Main Title

    Intro paragraph.

    ## Section One

    Content for section one.

    ## Section Two

    Content for section two.

    ### Subsection

    Subsection content.
    """

    let parser = MarkdownParser()
    let result = try await parser.parse(content: Data(markdown.utf8), sourceURL: nil)

    #expect(result.metadata.documentType == .markdown)
    #expect(result.metadata.title == "Main Title")
    #expect(result.sections.count >= 4)

    let titles = result.sections.map(\.title)
    #expect(titles.contains("Main Title"))
    #expect(titles.contains("Section One"))
    #expect(titles.contains("Section Two"))
    #expect(titles.contains("Subsection"))
  }

  @Test("HTMLParser detects HTML content")
  func htmlDetection() {
    let html = "<html><body><h1>Title</h1></body></html>"
    let parser = HTMLParser()
    #expect(parser.canParse(content: Data(html.utf8), mimeType: nil))
    #expect(parser.canParse(content: Data(html.utf8), mimeType: "text/html"))
  }

  @Test("HTMLParser extracts sections from headers")
  func htmlSections() async throws {
    let html = """
    <html>
    <head><title>Test Page</title></head>
    <body>
        <h1>Main Title</h1>
        <p>Introduction paragraph.</p>
        <h2>Section A</h2>
        <p>Content A.</p>
        <h2>Section B</h2>
        <p>Content B.</p>
    </body>
    </html>
    """

    let parser = HTMLParser()
    let result = try await parser.parse(content: Data(html.utf8), sourceURL: nil)

    #expect(result.metadata.documentType == .html)
    #expect(result.metadata.title == "Test Page")
    #expect(result.sections.count >= 3)

    let titles = result.sections.map(\.title)
    #expect(titles.contains("Main Title"))
    #expect(titles.contains("Section A"))
    #expect(titles.contains("Section B"))
  }

  @Test("TextParser detects plain text")
  func textDetection() {
    let text = "Just some plain text content."
    let parser = TextParser()
    #expect(parser.canParse(content: Data(text.utf8), mimeType: "text/plain"))
  }

  @Test("TextParser detects ALL CAPS headers")
  func textAllCapsHeaders() async throws {
    let text = """
    INTRODUCTION

    This is the introduction.

    MAIN CONTENT

    This is the main content section.

    CONCLUSION

    Final thoughts.
    """

    let parser = TextParser()
    let result = try await parser.parse(content: Data(text.utf8), sourceURL: nil)

    #expect(result.sections.count >= 3)
    let titles = result.sections.map(\.title)
    #expect(titles.contains("Introduction"))
    #expect(titles.contains("Main Content"))
    #expect(titles.contains("Conclusion"))
  }

  @Test("PDFParser detects PDF by magic number")
  func pdfDetection() {
    let parser = PDFParser()
    let pdfHeader = Data("%PDF-1.4".utf8)
    #expect(parser.canParse(content: pdfHeader, mimeType: nil))

    let notPdf = Data("Hello world".utf8)
    #expect(!parser.canParse(content: notPdf, mimeType: nil))
  }

  @Test("ParserFactory selects correct parser")
  func parserFactorySelection() {
    let mdParser = ParserFactory.getParser(content: Data("# Title\n\n- list".utf8), mimeType: "text/markdown")
    #expect(mdParser.documentType == .markdown)

    let htmlParser = ParserFactory.getParser(content: Data("<html></html>".utf8), mimeType: "text/html")
    #expect(htmlParser.documentType == .html)

    let pdfParser = ParserFactory.getParser(content: Data("%PDF-1.4".utf8), mimeType: "application/pdf")
    #expect(pdfParser.documentType == .pdf)

    let textParser = ParserFactory.getParser(content: Data("plain text".utf8), mimeType: "text/plain")
    #expect(textParser.documentType == .text)
  }

  @Test("DocumentType from extension")
  func documentTypeFromExtension() {
    #expect(ParserFactory.documentTypeFromExtension("doc.pdf") == .pdf)
    #expect(ParserFactory.documentTypeFromExtension("page.html") == .html)
    #expect(ParserFactory.documentTypeFromExtension("readme.md") == .markdown)
    #expect(ParserFactory.documentTypeFromExtension("notes.txt") == .text)
    #expect(ParserFactory.documentTypeFromExtension("binary.exe") == nil)
  }
}
