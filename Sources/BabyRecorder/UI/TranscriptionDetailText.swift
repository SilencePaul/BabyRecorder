import SwiftUI

struct TranscriptionDetailText: View {
    let text: String
    let lineLimit: Int

    var body: some View {
        Text(text)
            .font(.callout)
            .textSelection(.enabled)
            .lineLimit(lineLimit)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}
