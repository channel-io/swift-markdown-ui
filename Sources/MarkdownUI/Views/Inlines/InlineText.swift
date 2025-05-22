import SwiftUI
import Foundation

struct InlineText: View {
  @Environment(\.inlineImageProvider) private var inlineImageProvider
  @Environment(\.baseURL) private var baseURL
  @Environment(\.imageBaseURL) private var imageBaseURL
  @Environment(\.softBreakMode) private var softBreakMode
  @Environment(\.theme) private var theme

  @State private var inlineImages: [String: Image] = [:]

  private let inlines: [InlineNode]

  init(_ inlines: [InlineNode]) {
    self.inlines = inlines
  }

  var body: some View {
    TextStyleAttributesReader { attributes in
      if #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) {
        let renderer = InlineViewRenderer(
          baseURL: self.baseURL,
          theme: self.theme,
          images: self.inlineImages,
          softBreakMode: self.softBreakMode,
          attributes: attributes
        )
        InlineFlow(items: renderer.render(self.inlines))
      } else {
        self.inlines.renderText(
          baseURL: self.baseURL,
          textStyles: .init(
            code: self.theme.code,
            emphasis: self.theme.emphasis,
            strong: self.theme.strong,
            strikethrough: self.theme.strikethrough,
            link: self.theme.link
          ),
          images: self.inlineImages,
          softBreakMode: self.softBreakMode,
          attributes: attributes
        )
      }
    }
    .task(id: self.inlines) {
      self.inlineImages = (try? await self.loadInlineImages()) ?? [:]
    }
  }

  private func loadInlineImages() async throws -> [String: Image] {
    let images = Set(self.inlines.compactMap(\.imageData))
    guard !images.isEmpty else { return [:] }

    return try await withThrowingTaskGroup(of: (String, Image).self) { taskGroup in
      for image in images {
        guard let url = URL(string: image.source, relativeTo: self.imageBaseURL) else {
          continue
        }

        taskGroup.addTask {
          (image.source, try await self.inlineImageProvider.image(with: url, label: image.alt))
        }
      }

      var inlineImages: [String: Image] = [:]

      for try await result in taskGroup {
        inlineImages[result.0] = result.1
      }

      return inlineImages
    }
  }
}

#if swift(>=5.7)
@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
private struct InlineFlow: View {
  let items: [AnyView]

  var body: some View {
    FlowLayout(horizontalSpacing: 0, verticalSpacing: 0) {
      ForEach(Array(self.items.enumerated()), id: \.0) { _, item in
        item
      }
    }
  }
}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
private struct InlineViewRenderer {
  let baseURL: URL?
  let theme: Theme
  let images: [String: Image]
  let softBreakMode: SoftBreak.Mode
  var attributes: AttributeContainer
  var shouldSkipNextWhitespace = false

  func render(_ inlines: [InlineNode]) -> [AnyView] {
    var renderer = self
    renderer.render(inlines)
    return renderer.result
  }

  private var result: [AnyView] = []

  private mutating func render(_ inlines: [InlineNode]) {
    for inline in inlines {
      self.render(inline)
    }
  }

  private mutating func render(_ inline: InlineNode) {
    switch inline {
    case .text(let content):
      self.renderText(content)
    case .softBreak:
      self.renderSoftBreak()
    case .lineBreak:
      self.renderLineBreak()
    case .code(let content):
      self.renderCode(content)
    case .html(let content):
      self.renderHTML(content)
    case .emphasis(let children):
      self.renderEmphasis(children: children)
    case .strong(let children):
      self.renderStrong(children: children)
    case .strikethrough(let children):
      self.renderStrikethrough(children: children)
    case .link(let destination, let children):
      self.renderLink(destination: destination, children: children)
    case .image(let source, _):
      self.renderImage(source: source)
    }
  }

  private mutating func renderText(_ text: String) {
    var text = text
    if self.shouldSkipNextWhitespace {
      self.shouldSkipNextWhitespace = false
      text = text.replacingOccurrences(of: "^\\s+", with: "", options: .regularExpression)
    }
    self.result.append(AnyView(Text(AttributedString(text, attributes: self.attributes))))
  }

  private mutating func renderSoftBreak() {
    switch self.softBreakMode {
    case .space where self.shouldSkipNextWhitespace:
      self.shouldSkipNextWhitespace = false
    case .space:
      self.result.append(AnyView(Text(" ")))
    case .lineBreak:
      self.renderLineBreak()
    }
  }

  private mutating func renderLineBreak() {
    self.shouldSkipNextWhitespace = true
    self.result.append(AnyView(Spacer().layoutPriority(-1)))
  }

  private mutating func renderCode(_ code: String) {
    var attributes = self.attributes
    self.theme.code._collectAttributes(in: &attributes)
    let label = Text(AttributedString(code, attributes: attributes))
    let configuration = CodeInlineConfiguration(text: code, label: .init(label))
    self.result.append(self.theme.inlineCode.makeBody(configuration: configuration))
  }

  private mutating func renderHTML(_ html: String) {
    let tag = HTMLTag(html)
    switch tag?.name.lowercased() {
    case "br":
      self.renderLineBreak()
    default:
      self.renderText(html)
    }
  }

  private mutating func renderEmphasis(children: [InlineNode]) {
    let savedAttributes = self.attributes
    self.attributes = self.theme.emphasis.mergingAttributes(self.attributes)
    for child in children { self.render(child) }
    self.attributes = savedAttributes
  }

  private mutating func renderStrong(children: [InlineNode]) {
    let savedAttributes = self.attributes
    self.attributes = self.theme.strong.mergingAttributes(self.attributes)
    for child in children { self.render(child) }
    self.attributes = savedAttributes
  }

  private mutating func renderStrikethrough(children: [InlineNode]) {
    let savedAttributes = self.attributes
    self.attributes = self.theme.strikethrough.mergingAttributes(self.attributes)
    for child in children { self.render(child) }
    self.attributes = savedAttributes
  }

  private mutating func renderLink(destination: String, children: [InlineNode]) {
    let savedAttributes = self.attributes
    self.attributes = self.theme.link.mergingAttributes(self.attributes)
    self.attributes.link = URL(string: destination, relativeTo: self.baseURL)
    var childRenderer = InlineViewRenderer(
      baseURL: self.baseURL,
      theme: self.theme,
      images: self.images,
      softBreakMode: self.softBreakMode,
      attributes: self.attributes
    )
    let childItems = childRenderer.render(children)
    let label = InlineFlow(items: childItems)
    let configuration = LinkInlineConfiguration(
      destination: destination,
      text: children.renderPlainText(),
      label: .init(label)
    )
    self.result.append(self.theme.inlineLink.makeBody(configuration: configuration))
    self.attributes = savedAttributes
  }

  private mutating func renderImage(source: String) {
    if let image = self.images[source] {
      self.result.append(AnyView(image))
    }
  }
}
#endif

#if swift(>=5.7)
extension TextStyle {
  fileprivate func mergingAttributes(_ attributes: AttributeContainer) -> AttributeContainer {
    var newAttributes = attributes
    self._collectAttributes(in: &newAttributes)
    return newAttributes
  }
}
#endif
