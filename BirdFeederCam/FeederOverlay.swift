import SwiftUI

struct FeederOverlay: View {
    @Binding var rect: CGRect // normalized
    let canvasSize: CGSize

    @State private var dragStart: CGRect?

    var body: some View {
        let actual = CGRect(
            x: rect.minX * canvasSize.width,
            y: rect.minY * canvasSize.height,
            width: rect.width * canvasSize.width,
            height: rect.height * canvasSize.height
        )

        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())

            Rectangle()
                .strokeBorder(.yellow, lineWidth: 4)
                .background(Rectangle().fill(.yellow.opacity(0.08)))
                .frame(width: actual.width, height: actual.height)
                .position(x: actual.midX, y: actual.midY)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if dragStart == nil { dragStart = rect }
                            guard let start = dragStart else { return }
                            let dx = value.translation.width / max(canvasSize.width, 1)
                            let dy = value.translation.height / max(canvasSize.height, 1)
                            rect.origin.x = min(max(start.origin.x + dx, 0), 1 - rect.width)
                            rect.origin.y = min(max(start.origin.y + dy, 0), 1 - rect.height)
                        }
                        .onEnded { _ in dragStart = nil }
                )

            Text("Drag box over feeder")
                .font(.caption.bold())
                .padding(6)
                .background(.black.opacity(0.55))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .position(x: actual.midX, y: max(actual.minY - 18, 18))
        }
    }
}
