import SwiftUI

/// Access-backstage-inspired welcome screen: a coloured left rail with the
/// celist.db brand and a right pane of database-creation cards.
struct WelcomeView: View {
    let onOpen: () -> Void
    let onCreate: () -> Void
    let onSample: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            leftRail
            rightPane
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AccessTheme.windowBackground)
    }

    // MARK: - Left rail

    private var leftRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "cylinder.split.1x2")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Text("celist.db")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AccessGradient(top: AccessTheme.ribbonAppStripTop, bottom: AccessTheme.ribbonAppStripBottom))

            VStack(alignment: .leading, spacing: 2) {
                Text("New")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: 0x94332f))
                    .padding(.leading, 14)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AccessTheme.navItemSelected)
                    .contentShape(Rectangle())
                    .onTapGesture { onCreate() }
                    .onHover { hovering in if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() } }

                Text("Open")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: 0x1F1F1F))
                    .padding(.leading, 14)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { onOpen() }
                    .onHover { hovering in if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
            }
            .padding(.top, 12)

            Spacer()

            Image(systemName: "externaldrive.fill.badge.plus")
                .font(.system(size: 120))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(AccessTheme.appAccent.opacity(0.9), AccessTheme.appAccentDark.opacity(0.35))
                .frame(maxWidth: .infinity)
                .padding(.bottom, 30)
        }
        .frame(width: 190)
    }

    // MARK: - Right pane

    private var rightPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("New")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Color(hex: 0x1F1F1F))

                Text("Start with a blank database, a ready-to-use sample, or open one you already have.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                HStack(alignment: .top, spacing: 16) {
                    templateCard(
                        icon: "doc.badge.plus",
                        accent: AccessTheme.appAccent,
                        title: "Blank Database",
                        subtitle: "Start from scratch and\ndesign your own tables."
                    ) { onCreate() }

                    templateCard(
                        icon: "sparkles",
                        accent: AccessTheme.accessBlue,
                        title: "Sample Database",
                        subtitle: "Customers, products, orders —\nlearn by exploring."
                    ) { onSample() }

                    templateCard(
                        icon: "folder",
                        accent: Color(hex: 0x5A8452),
                        title: "Open Existing",
                        subtitle: "Browse for a .db, .sqlite\nor .sqlite3 file on your Mac."
                    ) { onOpen() }
                }

                Spacer().frame(height: 20)

                Text("Tip: you can also use the ribbon's  File ▶ Open/New  commands at any time. No SQL needed for everyday work — power users can run raw SQL from the SQL Query screen.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }

    private func templateCard(
        icon: String,
        accent: Color,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        WelcomeTemplateCard(icon: icon, accent: accent, title: title, subtitle: subtitle, action: action)
    }
}

/// A single backstage "template" card.
private struct WelcomeTemplateCard: View {
    let icon: String
    let accent: Color
    let title: String
    let subtitle: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 30))
                    .foregroundStyle(accent)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x1F1F1F))
                    .multilineTextAlignment(.leading)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(2)
            }
            .padding(14)
            .frame(width: 190, height: 150, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hovering ? Color.white : Color(hex: 0xFAFAFA))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(hovering ? accent.opacity(0.7) : AccessTheme.fieldBorder, lineWidth: 1)
            )
            .shadow(color: hovering ? Color.black.opacity(0.12) : .clear, radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(title)
    }
}