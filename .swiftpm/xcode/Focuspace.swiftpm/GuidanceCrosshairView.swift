import SwiftUI

struct GuidanceCrosshairView: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.white)
                .frame(width: 18, height: 2)
                .cornerRadius(1)

            Rectangle()
                .fill(Color.white)
                .frame(width: 2, height: 18)
                .cornerRadius(1)

            Circle()
                .fill(Color.white)
                .frame(width: 3, height: 3)
        }
        .allowsHitTesting(false)
    }
}
