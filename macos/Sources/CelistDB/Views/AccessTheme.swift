import SwiftUI
import AppKit

/// Color palette replicating Microsoft Access — Office 365 "Colorful" theme
/// (dark maroon app strip) with the classic Access-blue navigation pane and
/// the familiar spreadsheet datasheet look.
enum AccessTheme {
    // MARK: - Brand
    /// Access's accent colour in the Colorful Office theme (dark maroon).
    static let appAccent = Color(hex: 0xA4373A)
    static let appAccentLight = Color(hex: 0xD05F63)
    static let appAccentDark = Color(hex: 0x7E2A2F)
    /// Classic Access blue used for links, highlights and record indicators.
    static let accessBlue = Color(hex: 0x2E6DA8)
    static let accessBlueDark = Color(hex: 0x1F4E79)

    // MARK: - Ribbon
    static let ribbonAppStripTop = Color(hex: 0xB24444)
    static let ribbonAppStripBottom = Color(hex: 0x8E2B2F)
    static let ribbonTabBar = Color(hex: 0xF9F9F9)
    static let ribbonGroupArea = Color(hex: 0xF3F3F3)
    static let ribbonGroupCaption = Color(hex: 0x6B6B6B)
    static let ribbonButtonHover = Color(hex: 0xD7E7FB)
    static let ribbonButtonActive = Color(hex: 0xC2D9F3)
    static let ribbonButtonBorder = Color(hex: 0xC9C9C9)
    static let ribbonSeparator = Color(hex: 0xD8D8D8)
    static let ribbonTabHover = Color(hex: 0xEFF2F6)

    // MARK: - Navigation Pane
    static let navHeaderGradientTop = Color(hex: 0x9DBFF0)
    static let navHeaderGradientBottom = Color(hex: 0x326FA3)
    static let navPaneBackground = Color(hex: 0xFFFFFF)
    static let navPaneBorder = Color(hex: 0xC8C8C8)
    static let navItemHover = Color(hex: 0xEAF3FF)
    static let navItemSelected = Color(hex: 0xD7E7FB)
    static let navItemSelectedText = Color(hex: 0x1F4E79)
    static let navGroupHeaderText = Color(hex: 0x3B3B3B)
    static let navItemText = Color(hex: 0x1F1F1F)

    // MARK: - Datasheet
    static let datasheetBackground = Color(hex: 0xFFFFFF)
    static let gridLine = Color(hex: 0xD9D9D9)
    static let headerBackgroundTop = Color(hex: 0xEFEFEF)
    static let headerBackgroundBottom = Color(hex: 0xE2E2E2)
    static let headerText = Color(hex: 0x262626)
    static let headerHover = Color(hex: 0xF7F7F7)
    static let alternateRow = Color(hex: 0xF4F8FD)
    static let cellText = Color(hex: 0x1F1F1F)
    static let nullText = Color(hex: 0x9C9C9C)
    static let rowHighlight = Color(hex: 0xE9F1FB)
    static let cellHighlight = Color(hex: 0xC8E0F7)
    static let cellHighlightBorder = Color(hex: 0x3B82C4)
    static let recordIndicator = Color(hex: 0x2E6DA8)
    static let recordNew = Color(hex: 0xA4373A)

    // MARK: - Document tabs
    static let tabBarBackground = Color(hex: 0xEDEDED)
    static let tabActive = Color(hex: 0xFFFFFF)
    static let tabInactive = Color(hex: 0xE4E4E4)
    static let tabBorder = Color(hex: 0xC8C8C8)
    static let tabUnderline = Color(hex: 0xA4373A)

    // MARK: - Status bar
    static let statusBar = Color(hex: 0xEFEFEF)
    static let statusBarBorder = Color(hex: 0xD1D1D1)
    static let statusBarText = Color(hex: 0x5A5A5A)

    // MARK: - Surfaces
    static let windowBackground = Color(hex: 0xF3F3F3)
    static let contentCard = Color(hex: 0xFFFFFF)
    static let fieldBorder = Color(hex: 0xC8C8C8)
    static let selectedTabArea = Color(hex: 0xFFFFFF)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// A subtle vertical gradient used for Access-style chrome bars.
struct AccessGradient: View {
    let top: Color
    let bottom: Color

    var body: some View {
        LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }
}