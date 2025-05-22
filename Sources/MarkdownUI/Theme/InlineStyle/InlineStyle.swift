import SwiftUI

/// A type that applies a custom appearance to specific inline views in a Markdown view.
///
/// Inline styles are used by ``Theme`` to customize the appearance of inline code or link
/// elements. You typically don't create inline styles directly. Instead, you use the
/// ``View/markdownInlineStyle(_:body:)`` modifier to override a particular inline style of the
/// current theme.
public struct InlineStyle<Configuration> {
  private let body: (Configuration) -> AnyView

  /// Creates an inline style that customizes an inline element by applying the given body.
  /// - Parameter body: A view builder that receives the inline configuration and returns the
  ///   customized view.
  public init<Body: View>(@ViewBuilder body: @escaping (_ configuration: Configuration) -> Body) {
    self.body = { AnyView(body($0)) }
  }

  func makeBody(configuration: Configuration) -> AnyView {
    self.body(configuration)
  }
}

extension InlineStyle where Configuration == Void {
  /// Creates an inline style for an inline element with no configuration.
  /// - Parameter body: A view builder that returns the customized inline element.
  public init<Body: View>(@ViewBuilder body: @escaping () -> Body) {
    self.init { _ in body() }
  }
}
