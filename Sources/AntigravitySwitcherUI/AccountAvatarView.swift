import SwiftUI

struct AccountAvatarView: View {
    let name: String
    let avatarURL: URL?
    let size: CGFloat

    var body: some View {
        Group {
            if let avatarURL {
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.67, blue: 0.96), AGTheme.accent, .purple],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            // Chữ cái đầu tên
            Text(String(name.prefix(1)).uppercased())
                .font(.system(size: max(11, size * 0.38), weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
