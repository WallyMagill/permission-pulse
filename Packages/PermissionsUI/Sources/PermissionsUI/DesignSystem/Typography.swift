import SwiftUI

/// Semantic type roles backed by Dynamic Type text styles so text scales with the
/// user's text-size setting. Apply with `.ppFont(_:)`. (Thread B)
public enum PPFont {
    case pageTitle
    case cardHeader
    case body
    case secondary
    case metadata
    case badge

    public var font: Font {
        switch self {
        case .pageTitle:  .system(.title2, weight: .semibold)
        case .cardHeader: .system(.headline)
        case .body:       .system(.body)
        case .secondary:  .system(.subheadline)
        case .metadata:   .system(.caption)
        case .badge:      .system(.caption2, weight: .semibold)
        }
    }
}

/// The maximum Dynamic Type size the fixed-width menu-bar dropdown allows, so it
/// scales modestly without breaking the 320pt layout. (Thread B hybrid policy)
public enum PPDynamicType {
    public static let dropdownMaximum: DynamicTypeSize = .xLarge

    /// Pure clamp used by the dropdown and unit-tested.
    public static func clampedForDropdown(_ requested: DynamicTypeSize) -> DynamicTypeSize {
        Swift.min(requested, dropdownMaximum)
    }
}

extension View {
    public func ppFont(_ role: PPFont) -> some View {
        font(role.font)
    }

    /// Uppercased, tracked, secondary section-label treatment (one definition,
    /// replacing the per-view inline cluster). (Thread B)
    public func ppSectionLabel() -> some View {
        ppFont(.metadata)
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }

    /// Clamp Dynamic Type for the fixed-width dropdown.
    public func ppDropdownDynamicTypeClamp() -> some View {
        dynamicTypeSize(...PPDynamicType.dropdownMaximum)
    }
}
