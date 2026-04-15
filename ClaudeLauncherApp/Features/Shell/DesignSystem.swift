import SwiftUI

struct LauncherTheme {
    static let appBackground = Color(red: 247 / 255, green: 247 / 255, blue: 249 / 255)
    static let cardBackground = Color.white
    static let primaryText = Color(red: 17 / 255, green: 24 / 255, blue: 39 / 255)
    static let secondaryText = Color(red: 107 / 255, green: 114 / 255, blue: 128 / 255)
    static let tertiaryText = Color(red: 156 / 255, green: 163 / 255, blue: 175 / 255)
    static let border = Color(red: 229 / 255, green: 231 / 255, blue: 235 / 255)
    static let softFill = Color(red: 243 / 255, green: 244 / 255, blue: 246 / 255)
    static let blueTint = Color(red: 59 / 255, green: 130 / 255, blue: 246 / 255)
    static let blueSoft = Color(red: 239 / 255, green: 246 / 255, blue: 255 / 255)
    static let ctaBlack = Color(red: 15 / 255, green: 15 / 255, blue: 17 / 255)
}

extension Font {
    static let launcherTitle = Font.system(size: 23, weight: .semibold)
    static let launcherBody = Font.system(size: 14, weight: .regular)
    static let launcherBodyStrong = Font.system(size: 15, weight: .medium)
    static let launcherLabel = Font.system(size: 11, weight: .semibold)
    static let launcherMeta = Font.system(size: 12, weight: .medium)
    static let launcherMini = Font.system(size: 10, weight: .medium)
}

struct LauncherSurfaceCard<Content: View>: View {
    let cornerRadius: CGFloat
    @ViewBuilder var content: Content

    init(cornerRadius: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .background(LauncherTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(LauncherTheme.border.opacity(0.8), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
}

struct LauncherSectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.launcherLabel)
            .tracking(1.1)
            .foregroundStyle(LauncherTheme.tertiaryText)
    }
}

struct LauncherChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.launcherMini)
            .foregroundStyle(LauncherTheme.secondaryText)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(LauncherTheme.softFill)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(LauncherTheme.border.opacity(0.6), lineWidth: 1)
            )
    }
}

struct LauncherMacControls: View {
    var body: some View {
        HStack(spacing: 8) {
            macDot(Color(red: 1.0, green: 95 / 255, blue: 86 / 255))
            macDot(Color(red: 1.0, green: 189 / 255, blue: 46 / 255))
            macDot(Color(red: 39 / 255, green: 201 / 255, blue: 63 / 255))
        }
        .frame(width: 80, alignment: .leading)
    }

    private func macDot(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 12, height: 12)
            .overlay(Circle().stroke(.black.opacity(0.08), lineWidth: 1))
    }
}

struct LauncherTopBarButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(LauncherTheme.secondaryText)
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(configuration.isPressed ? LauncherTheme.softFill : Color.clear)
            )
    }
}

struct LauncherPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(configuration.isPressed ? LauncherTheme.ctaBlack.opacity(0.94) : LauncherTheme.ctaBlack)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(0.04), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .shadow(color: .black.opacity(0.12), radius: configuration.isPressed ? 4 : 12, x: 0, y: 6)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

struct LauncherGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.launcherMeta)
            .foregroundStyle(LauncherTheme.secondaryText)
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(configuration.isPressed ? LauncherTheme.softFill : Color.clear)
            )
    }
}

struct LauncherSegmentedControl<T: Hashable>: View {
    let items: [(T, String)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                let isActive = item.0 == selection
                Button {
                    selection = item.0
                } label: {
                    Text(item.1)
                        .font(.system(size: 12, weight: isActive ? .semibold : .medium))
                        .foregroundStyle(isActive ? LauncherTheme.primaryText : LauncherTheme.secondaryText)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isActive ? Color.white : Color.clear)
                                .shadow(color: .black.opacity(isActive ? 0.08 : 0), radius: 3, x: 0, y: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(LauncherTheme.border.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct LauncherTextFieldContainer<Content: View>: View {
    let cornerRadius: CGFloat
    let minHeight: CGFloat
    @ViewBuilder var content: Content

    init(cornerRadius: CGFloat = 12, minHeight: CGFloat = 44, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.minHeight = minHeight
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 12)
            .frame(minHeight: minHeight)
            .foregroundStyle(LauncherTheme.primaryText)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(LauncherTheme.border.opacity(0.82), lineWidth: 1)
            )
    }
}

struct LauncherPanelBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(LauncherTheme.appBackground)
    }
}

struct LauncherBottomBarBackground: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.94))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(LauncherTheme.border.opacity(0.8))
                    .frame(height: 1)
            }
            .ignoresSafeArea()
    }
}

extension View {
    func launcherPanelBackground() -> some View {
        modifier(LauncherPanelBackground())
    }
}
