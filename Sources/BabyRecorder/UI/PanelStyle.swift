import SwiftUI

extension View {
    func panelStyle() -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}
