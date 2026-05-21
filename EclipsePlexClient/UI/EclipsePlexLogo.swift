//
//  EclipsePlexLogo.swift
//  EclipsePlexClient
//

import SwiftUI

enum EclipsePlexBranding {
    static let productName = PlexHTTPConstants.productName
}

/// In-app branding mark (`AppLogo` asset). Not the app icon.
struct EclipsePlexLogo: View {
    enum Style {
        /// Home welcome header.
        case hero
        /// Browse sidebar / sheet header.
        case sidebar
        /// Small inline mark (e.g. settings sections).
        case compact

        var size: CGFloat {
            switch self {
            case .hero: 88
            case .sidebar: 56
            case .compact: 36
            }
        }
    }

    var style: Style = .hero

    var body: some View {
        Image("AppLogo")
            .resizable()
            .scaledToFit()
            .frame(width: style.size, height: style.size)
            .accessibilityHidden(true)
    }
}

/// Logo plus product name for headers (Home, Browse sidebar, Downloads).
struct EclipsePlexBrandingHeader: View {
    enum Layout {
        case hero
        case sidebar
        case compact

        fileprivate var logoStyle: EclipsePlexLogo.Style {
            switch self {
            case .hero: .hero
            case .sidebar: .sidebar
            case .compact: .compact
            }
        }

        fileprivate var titleFont: Font {
            switch self {
            case .hero: .largeTitle.weight(.bold)
            case .sidebar: .title3.weight(.semibold)
            case .compact: .subheadline.weight(.semibold)
            }
        }

        fileprivate var spacing: CGFloat {
            switch self {
            case .hero: 16
            case .sidebar: 8
            case .compact: 6
            }
        }

        fileprivate var usesHorizontalLayout: Bool {
            self == .hero
        }
    }

    var layout: Layout = .hero
    var subtitle: String?

    var body: some View {
        Group {
            if layout.usesHorizontalLayout {
                HStack(alignment: .center, spacing: layout.spacing) {
                    EclipsePlexLogo(style: layout.logoStyle)
                    titleBlock
                }
            } else {
                VStack(spacing: layout.spacing) {
                    EclipsePlexLogo(style: layout.logoStyle)
                    titleBlock
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var titleBlock: some View {
        VStack(alignment: layout.usesHorizontalLayout ? .leading : .center, spacing: 4) {
            Text(EclipsePlexBranding.productName)
                .font(layout.titleFont)
                .multilineTextAlignment(layout.usesHorizontalLayout ? .leading : .center)
            if let subtitle {
                Text(subtitle)
                    .font(layout == .hero ? .title2 : .caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(layout.usesHorizontalLayout ? .leading : .center)
            }
        }
    }

    private var accessibilityText: String {
        if let subtitle {
            return "\(EclipsePlexBranding.productName), \(subtitle)"
        }
        return EclipsePlexBranding.productName
    }
}

#Preview("Hero") {
    EclipsePlexBrandingHeader(layout: .hero, subtitle: "Welcome")
        .padding()
}

#Preview("Sidebar") {
    EclipsePlexBrandingHeader(layout: .sidebar)
        .padding()
}
