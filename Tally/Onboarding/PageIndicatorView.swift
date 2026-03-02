import SwiftUI

struct PageIndicatorView: View {
    let pageCount: Int
    let currentPage: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<pageCount, id: \.self) { index in
                Capsule()
                    .fill(index == currentPage ? TallyColors.accent : TallyColors.textSecondary.opacity(0.25))
                    .frame(width: index == currentPage ? 24 : 8, height: 8)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        PageIndicatorView(pageCount: 3, currentPage: 0)
        PageIndicatorView(pageCount: 3, currentPage: 1)
        PageIndicatorView(pageCount: 3, currentPage: 2)
    }
}
