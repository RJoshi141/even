import SwiftUI

/// Start page on first launch, the map after that.
struct RootView: View {
    @AppStorage("onboarded") private var onboarded = false
    @AppStorage("preset") private var presetRaw = Preset.manualWheelchair.rawValue

    var body: some View {
        let style = StyleStore.shared.current
        Group {
            if onboarded {
                RouteCompareView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                OnboardingView { preset in
                    presetRaw = preset.rawValue
                    withAnimation(.smooth(duration: 0.6)) { onboarded = true }
                }
                .transition(.opacity.combined(with: .scale(scale: 1.02)))
            }
        }
        .font(.even(.body))
        .tint(style.accent)
    }
}

#Preview {
    RootView()
}
