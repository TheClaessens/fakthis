import SwiftUI
import AppKit

extension Color {
    /// The window's own ground, under and around the three columns: the front door's canvas, the
    /// Draft's fixed footer, the gutter, the signal panel, a Material chip, a conversation turn,
    /// the focused sibling. The columns themselves are `controlBackgroundColor`, and everything
    /// that has to read as a step off one of them is drawn in this.
    ///
    /// The front door is the one place it is the ground rather than the step: there are no
    /// columns before Generate, so the canvas is the window and the composer is a card on it.
    ///
    /// In light appearance that is exactly `windowBackgroundColor` — grey against the columns'
    /// white — and this is that colour unchanged. In dark appearance AppKit gives
    /// `windowBackgroundColor`, `controlBackgroundColor` and `textBackgroundColor` the *same*
    /// near-black, so a design that layers one on the other goes flat: the front door's composer,
    /// the footer, the signal panel and the focused sibling all disappear into their ground. Dark
    /// takes a value of its own, a step lighter than the columns, which is the direction dark
    /// appearance raises things in.
    static let windowGround = Color(
        nsColor: NSColor(name: "windowGround") { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(white: 0.19, alpha: 1)
                : .windowBackgroundColor
        }
    )
}
