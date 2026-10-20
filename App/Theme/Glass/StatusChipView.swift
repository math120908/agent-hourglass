import SwiftUI

/// Small capsule tag: plan pill (neutral), status chip (tinted).
struct StatusChipView: View {
    var text: String
    var tint: Color? = nil

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(tint ?? Color.secondary)
            .padding(.horizontal, 5.5)
            .padding(.vertical, 1.5)
            .background(Capsule().fill((tint ?? Color.primary).opacity(tint == nil ? 0.08 : 0.15)))
            .lineLimit(1)
            .fixedSize()
    }
}
