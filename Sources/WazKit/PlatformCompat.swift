//
//  PlatformCompat.swift
//  WazKit
//
//  Modifiers that tvOS lacks: keyboard shortcuts, rounded-border text fields and the bar material.
//  On Apple TV they fall back to the system's own look (focus-driven fields, regular material).
//

import SwiftUI

extension View {
    /// Return triggers this button on Mac and iPad; Apple TV has no keyboard shortcuts.
    @ViewBuilder public func defaultActionShortcut() -> some View {
        #if os(tvOS)
        self
        #else
        keyboardShortcut(.defaultAction)
        #endif
    }

    /// Rounded-border text fields; Apple TV draws its own focusable fields.
    @ViewBuilder public func roundedFields() -> some View {
        #if os(tvOS)
        self
        #else
        textFieldStyle(.roundedBorder)
        #endif
    }

    /// Buttons whose label is artwork with text under it (tiles, the Play hero). On Apple TV `.plain` puts a
    /// white platter behind the whole label; `.borderless` lets the artwork (`tileFocusEffect`) lift on focus
    /// with the title left under it, as the TV app does.
    @ViewBuilder public func tileButtonStyle() -> some View {
        #if os(tvOS)
        buttonStyle(.borderless)
        #else
        buttonStyle(.plain)
        #endif
    }

    /// The part of a `tileButtonStyle` button that lifts and shines on Apple TV when focused.
    @ViewBuilder public func tileFocusEffect() -> some View {
        #if os(tvOS)
        hoverEffect(.highlight)
        #else
        self
        #endif
    }

    /// The toolbar-style backdrop; Apple TV has no bar material.
    @ViewBuilder public func barBackground() -> some View {
        #if os(tvOS)
        background(.regularMaterial)
        #else
        background(.bar)
        #endif
    }
}
