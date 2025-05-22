import SwiftUI

struct InlineCodeView: View {
  let text: String
  let backgroundColor: Color?
  let cornerRadius: CGFloat
  let textStyle: TextStyle

  var body: some View {
    TextStyleAttributesReader { attributes in
      let merged = self.textStyle.mergingAttributes(attributes)
      if self.cornerRadius == 0 && self.backgroundColor == nil {
        Text(self.text, attributes: merged)
      } else {
        var attributes = merged
        let bg = self.backgroundColor ?? attributes.backgroundColor
        attributes.backgroundColor = nil
        Text(self.text, attributes: attributes)
          .padding(.horizontal, 4)
          .padding(.vertical, 2)
          .background(
            RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)
              .fill(bg ?? Color.clear)
          )
      }
    }
  }
}
