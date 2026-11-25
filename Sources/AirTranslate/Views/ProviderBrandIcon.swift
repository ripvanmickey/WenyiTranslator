import SwiftUI
import AppKit

/// Brand shapes are bundled locally, never fetched from the network at runtime.
struct ProviderBrandIcon: View {
    let provider: CredentialProvider?
    var fallback = "cpu"
    var size: CGFloat = 20
    var assetName: String? = nil
    var body: some View {
        Group {
            if let name = assetName ?? provider?.logoName,
               let root = Bundle.main.resourceURL,
               let image = NSImage(contentsOf: root.appendingPathComponent("ProviderLogos/\(name).png")) {
                Image(nsImage: image).resizable().renderingMode(.template).scaledToFit()
            } else { Image(systemName: fallback).resizable().scaledToFit() }
        }
        .foregroundStyle(provider?.logoColor ?? .primary)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

extension CredentialProvider {
    var logoName: String? {
        switch self {
        case .openAI: "openai"
        case .gemini: "googlegemini"
        case .meta: "meta"
        case .cloudflare: "cloudflare"
        case .grok: "xai"
        case .qwen: "qwen"
        case .indexOnline: "bilibili"
        default: nil
        }
    }
    var logoColor: Color {
        switch self {
        case .gemini, .meta: .blue
        case .cloudflare: .orange
        case .qwen: .purple
        case .indexOnline: .pink
        default: .primary
        }
    }
}
