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

    /// The toolbar-style backdrop; Apple TV has no bar material.
    @ViewBuilder public func barBackground() -> some View {
        #if os(tvOS)
        background(.regularMaterial)
        #else
        background(.bar)
        #endif
    }
}
