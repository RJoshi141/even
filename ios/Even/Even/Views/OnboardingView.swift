import SwiftUI

/// First launch, three questions: what Even is, how you get around, where you start.
struct OnboardingView: View {
    let onFinish: (Preset) -> Void

    fileprivate enum Page: Int, CaseIterable { case welcome, profile, location }

    @State private var page: Page = .welcome
    @State private var forward = true
    @State private var choice: Preset = .manualWheelchair
    @State private var askingLocation = false
    @AppStorage("useLocationStart") private var useLocation = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            topBar

            ZStack {
                switch page {
                case .welcome: WelcomePage().transition(slide)
                case .profile: ProfilePage(choice: $choice).transition(slide)
                case .location: LocationPage().transition(slide)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            bottomBar
        }
        .padding(.horizontal, 24)
        .background(Color.paper.ignoresSafeArea())
        .sensoryFeedback(.impact(weight: .light), trigger: page)
    }

    // pages slide the way you're going; Reduce Motion gets a plain fade
    private var slide: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity))
    }

    private func go(_ next: Page) {
        // set the direction first so the outgoing page leaves the right way
        forward = next.rawValue > page.rawValue
        DispatchQueue.main.async {
            withAnimation(.smooth(duration: 0.45)) { page = next }
        }
    }

    // MARK: top: wordmark or back, plus progress

    private var topBar: some View {
        HStack {
            if page == .welcome {
                Wordmark(size: 22)
            } else {
                Button {
                    go(Page(rawValue: page.rawValue - 1) ?? .welcome)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .frame(width: 44, height: 44, alignment: .leading)
                }
                .accessibilityLabel("Back")
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(Page.allCases, id: \.self) { p in
                    Capsule()
                        .fill(p.rawValue <= page.rawValue ? Color.ink : Color.hairline)
                        .frame(width: p == page ? 22 : 8, height: 8)
                }
            }
            .animation(.smooth(duration: 0.35), value: page)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(page.rawValue + 1) of \(Page.allCases.count)")
        }
        .frame(height: 52)
    }

    // MARK: bottom: the main action always sits here

    private var bottomBar: some View {
        VStack(spacing: 4) {
            switch page {
            case .welcome:
                primary("Get started") { go(.profile) }
            case .profile:
                primary("Continue") { go(.location) }
            case .location:
                primary(askingLocation ? "Asking for permission…" : "Use my location",
                        icon: "location.fill") { askForLocation() }
                    .disabled(askingLocation)
                Button("Not now") {
                    useLocation = false
                    onFinish(choice)
                }
                .font(.even(.subheadline, .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
        .animation(.smooth(duration: 0.3), value: page)
    }

    private func primary(_ title: String, icon: String = "arrow.right", action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.even(.headline))
                    .contentTransition(.opacity)
                Spacer()
                Image(systemName: icon).font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(Color.onBrand)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Color.brand, in: .rect(cornerRadius: StyleStore.shared.current.corner + 4))
        }
        .buttonStyle(PressableStyle())
    }

    private func askForLocation() {
        askingLocation = true
        Task {
            // only asks here, after the person chose it; if they decline we just carry on
            let ok = (try? await LocationProvider.current(timeout: .seconds(10))) != nil
            useLocation = ok
            askingLocation = false
            onFinish(choice)
        }
    }
}

// MARK: - page 1: what Even does

private struct WelcomePage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RouteIllustration()
                .frame(height: 300)
                .padding(.top, 12)
                .reveal(0.05)

            Spacer(minLength: 28)

            Text("Directions that know the hills.")
                .font(.even(.largeTitle, .bold))
                .tracking(-1)
                .fixedSize(horizontal: false, vertical: true)
                .reveal(0.2)
            Text("Step-free routes around steep blocks, missing curb ramps and stairs, planned for how you get around.")
                .font(.even(.body))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
                .reveal(0.3)

            Spacer(minLength: 12)
        }
    }
}

// MARK: - page 2: how you get around

private struct ProfilePage: View {
    @Binding var choice: Preset

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("How do you get around?")
                .font(.even(.largeTitle, .bold))
                .tracking(-1)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .reveal(0)
            Text("Even shapes every route around this. You can change it anytime.")
                .font(.even(.body))
                .foregroundStyle(.secondary)
                .padding(.top, 10)
                .reveal(0.08)

            VStack(spacing: 8) {
                ForEach(Array(Preset.allCases.enumerated()), id: \.element) { i, preset in
                    row(preset).reveal(0.14 + Double(i) * 0.05)
                }
            }
            .padding(.top, 24)
            .sensoryFeedback(.selection, trigger: choice)

            limits
                .padding(.top, 16)
                .reveal(0.4)

            Spacer(minLength: 0)
        }
    }

    private func row(_ preset: Preset) -> some View {
        let isOn = choice == preset
        let corner = StyleStore.shared.current.corner
        return Button {
            withAnimation(.smooth(duration: 0.25)) { choice = preset }
        } label: {
            HStack(spacing: 14) {
                PresetIcon(preset: preset, size: 24)
                    .foregroundStyle(isOn ? Color.ink : Color.primary)
                    .frame(width: 44, height: 44)
                    .background(isOn ? Color.white : Color.paperDeep, in: .rect(cornerRadius: corner))
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.label).font(.even(.headline))
                    Text(preset.blurb)
                        .font(.even(.subheadline))
                        .opacity(0.7)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isOn ? Color.white : Color.hairline)
            }
            .foregroundStyle(isOn ? Color.onHighlight : Color.primary)
            .padding(12)
            .background(isOn ? Color.highlight : Color.paper, in: .rect(cornerRadius: corner + 4))
            .overlay(RoundedRectangle(cornerRadius: corner + 4).stroke(isOn ? Color.clear : Color.hairline, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(preset.label). \(preset.limits)")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    // what the choice means, as numbers that update when you tap
    private var limits: some View {
        let l = choice.numbers
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "What this means")
            HStack(spacing: 8) {
                fact("↑ \(l.up)%", "Max uphill")
                fact("↓ \(l.down)%", "Max downhill")
                fact(l.ramps ? "Ramps" : "Any curb", l.ramps ? "No steps" : "Avoids steps")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("What this means: \(choice.limits)")
    }

    private func fact(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.even(.title3, .bold))
                .monospacedDigit()
                .contentTransition(.numericText())
            SectionLabel(text: label)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.paperDeep, in: .rect(cornerRadius: StyleStore.shared.current.corner))
    }
}

private extension Preset {
    // mirrors PRESETS in api/models.py
    var numbers: (up: Int, down: Int, ramps: Bool) {
        switch self {
        case .manualWheelchair: (5, 8, true)
        case .powerWheelchair: (8, 8, true)
        case .walker: (8, 5, true)
        case .stroller: (12, 8, false)
        }
    }
}

// MARK: - page 3: where you start

private struct LocationPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LocationIllustration()
                .frame(height: 260)
                .padding(.top, 12)
                .reveal(0.05)

            Spacer(minLength: 28)

            Text("Start from where you are?")
                .font(.even(.largeTitle, .bold))
                .tracking(-1)
                .fixedSize(horizontal: false, vertical: true)
                .reveal(0.15)
            Text("Even can use your location as point A, so you only choose where you're going. It's used to plan your route, only while the app is open.")
                .font(.even(.body))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
                .reveal(0.25)

            Spacer(minLength: 12)
        }
    }
}

// MARK: - illustrations

/// A hill, the straight shortcut over it, then the Even route drawing itself around.
private struct RouteIllustration: View {
    @State private var shortcut = false
    @State private var progress: CGFloat = 0
    @State private var pins = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let style = StyleStore.shared.current
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let a = CGPoint(x: w * 0.18, y: h * 0.76)
            let b = CGPoint(x: w * 0.82, y: h * 0.24)
            let around = Path { p in
                p.move(to: a)
                p.addLine(to: CGPoint(x: w * 0.82, y: h * 0.76))
                p.addLine(to: b)
            }

            ZStack {
                MapGrid()

                // the hill
                Ellipse()
                    .fill(Color.slopeModerate.opacity(0.2))
                    .frame(width: w * 0.44, height: h * 0.48)
                    .position(x: w * 0.5, y: h * 0.47)
                Image(systemName: "mountain.2.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.slopeModerate)
                    .position(x: w * 0.5, y: h * 0.47)

                // the shortcut: straight over the hill, ruled out
                Path { p in p.move(to: a); p.addLine(to: b) }
                    .stroke(Color.slopeOver.opacity(0.6), style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [2, 9]))
                    .opacity(shortcut ? 1 : 0)

                // the Even route: around it
                around
                    .trim(from: 0, to: progress)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: style.routeWidth + 5, lineCap: .round, lineJoin: .round))
                around
                    .trim(from: 0, to: progress)
                    .stroke(Color.slopeEasy, style: StrokeStyle(lineWidth: style.routeWidth, lineCap: .round, lineJoin: .round))

                LetterPin(letter: "A", filled: false, size: 34)
                    .scaleEffect(pins ? 1 : 0.4)
                    .opacity(pins ? 1 : 0)
                    .position(a)
                LetterPin(letter: "B", size: 34)
                    .scaleEffect(pins ? 1 : 0.4)
                    .opacity(pins ? 1 : 0)
                    .position(b)
            }
        }
        .onAppear {
            if reduceMotion {
                shortcut = true; progress = 1; pins = true
                return
            }
            withAnimation(.spring(duration: 0.5, bounce: 0.3).delay(0.15)) { pins = true }
            withAnimation(.easeOut(duration: 0.4).delay(0.45)) { shortcut = true }
            withAnimation(.easeInOut(duration: 1.4).delay(0.85)) { progress = 1 }
        }
        .accessibilityHidden(true)
    }
}

/// Point A with a gentle pulse, on the same map card.
private struct LocationIllustration: View {
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            MapGrid()
            Circle()
                .fill(Color.brand.opacity(0.12))
                .frame(width: 150, height: 150)
                .scaleEffect(pulse ? 1 : 0.5)
                .opacity(pulse ? 0 : 1)
            Circle()
                .fill(Color.brand.opacity(0.12))
                .frame(width: 70, height: 70)
            LetterPin(letter: "A", filled: false, size: 40)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) { pulse = true }
        }
        .accessibilityHidden(true)
    }
}

/// The paper map card both illustrations sit on.
private struct MapGrid: View {
    var body: some View {
        let corner = StyleStore.shared.current.corner + 8
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                RoundedRectangle(cornerRadius: corner).fill(Color.paperDeep)
                Path { p in
                    for i in 1..<5 {
                        let x = w * CGFloat(i) / 5
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: h))
                    }
                    for j in 1..<4 {
                        let y = h * CGFloat(j) / 4
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: w, y: y))
                    }
                }
                .stroke(Color.paper, lineWidth: 8)
                RoundedRectangle(cornerRadius: corner).stroke(Color.hairline, lineWidth: 1)
            }
            .clipShape(.rect(cornerRadius: corner))
        }
    }
}

// MARK: - pieces

struct Wordmark: View {
    var size: CGFloat = 22

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: size * 0.06) {
            Text("even")
                .font(.evenFixed(size, .bold))
                .tracking(-size * 0.04)
            Circle()
                .fill(Color.brand)
                .frame(width: size * 0.22, height: size * 0.22)
                .padding(.bottom, size * 0.16)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Even")
        .accessibilityAddTraits(.isHeader)
    }
}

/// content rises in after a short delay; Reduce Motion just fades
private struct Reveal: ViewModifier {
    let delay: Double
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .onAppear {
                withAnimation(.smooth(duration: 0.55).delay(reduceMotion ? 0 : delay)) { shown = true }
            }
    }
}

private extension View {
    func reveal(_ delay: Double) -> some View { modifier(Reveal(delay: delay)) }
}
