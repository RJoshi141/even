import SwiftUI

/// First launch, three questions: what Even is, how you get around, where you start.
/// Neo-brutalist: grid paper, ink outlines, hard shadows, blue as the loud color.
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
        .padding(.horizontal, 22)
        .background(GridPaper())
    }

    // pages slide the way you're going; Reduce Motion gets a plain fade
    private var slide: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity))
    }

    private func go(_ next: Page) {
        forward = next.rawValue > page.rawValue // set first so the old page leaves the right way
        DispatchQueue.main.async {
            withAnimation(.smooth(duration: 0.45)) { page = next }
        }
    }

    // MARK: top

    private var topBar: some View {
        HStack {
            if page == .welcome {
                Wordmark(size: 24)
            } else {
                Button {
                    go(Page(rawValue: page.rawValue - 1) ?? .welcome)
                } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Color.primary)
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(BrutalButtonStyle(fill: .paper, shadow: 3))
                .accessibilityLabel("Back")
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(Page.allCases, id: \.self) { p in
                    Rectangle()
                        .fill(p == page ? Color.brand : (p.rawValue < page.rawValue ? Color.line : Color.paper))
                        .frame(width: p == page ? 26 : 12, height: 12)
                        .overlay(Rectangle().stroke(Color.line, lineWidth: 2))
                }
            }
            .animation(.smooth(duration: 0.35), value: page)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(page.rawValue + 1) of \(Page.allCases.count)")
        }
        .frame(height: 56)
    }

    // MARK: bottom: the main action always sits here

    private var bottomBar: some View {
        VStack(spacing: 14) {
            switch page {
            case .welcome:
                primary("Get started") { go(.profile) }
            case .profile:
                primary("Continue") { go(.location) }
            case .location:
                primary(askingLocation ? "Asking…" : "Use my location", icon: "location.fill") { askForLocation() }
                    .disabled(askingLocation)
                Button {
                    useLocation = false
                    onFinish(choice)
                } label: {
                    Text("Not now").shout(.subheadline)
                        .foregroundStyle(Color.primary)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(BrutalButtonStyle(fill: .paper))
            }
        }
        .padding(.top, 14)
        .padding(.trailing, 4) // room for the hard shadow
        .padding(.bottom, 12)
        .animation(.smooth(duration: 0.3), value: page)
    }

    private func primary(_ title: String, icon: String = "arrow.right", action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).shout(.headline)
                Spacer()
                Image(systemName: icon).font(.system(size: 16, weight: .heavy))
            }
            .foregroundStyle(Color.onBrand)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 58)
        }
        .buttonStyle(BrutalButtonStyle(fill: .brand, shadow: 5))
    }

    private func askForLocation() {
        askingLocation = true
        Task {
            // only asks now, after the person chose it; if they decline we just carry on
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
            VStack(alignment: .leading, spacing: -4) {
                OutlineText(text: "DIRECTIONS", font: .evenFixed(46, .bold), tracking: -1.5)
                OutlineText(text: "THAT KNOW", font: .evenFixed(46, .bold), tracking: -1.5)
                Text("THE HILLS.")
                    .font(.evenFixed(46, .bold))
                    .tracking(-1.5)
                    .foregroundStyle(Color.brand)
            }
            .minimumScaleFactor(0.7)
            .lineLimit(1)
            .padding(.top, 10)
            .reveal(0.05)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Directions that know the hills.")
            .accessibilityAddTraits(.isHeader)

            Text("Step-free routes around steep blocks, missing curb ramps and stairs, planned for how you get around.")
                .font(.even(.body))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
                .reveal(0.15)

            // the map card with a tilted stat card over its corner
            ZStack(alignment: .topTrailing) {
                RouteIllustration()
                    .frame(height: 190)
                    .brutal()
                    .rotationEffect(.degrees(-1.5))
                    .padding(.top, 26)
                    .padding(.trailing, 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Every block").shout(.caption2)
                    Text("CHECKED").font(.evenFixed(28, .bold)).tracking(-0.5)
                    Text("for slope and curbs").font(.even(.caption))
                }
                .foregroundStyle(Color.onBrand)
                .padding(12)
                .brutal(fill: .brand, shadow: 4)
                .rotationEffect(.degrees(4))
            }
            .padding(.top, 22)
            .reveal(0.25)

            // what Even watches for, as tilted chips
            HStack(spacing: 10) {
                chip("arrow.up.right", "Steep hills", -2)
                chip("figure.roll", "Curb ramps", 1.5)
                chip("stairs", "Stairs", -1)
            }
            .padding(.top, 24)
            .reveal(0.35)

            Spacer(minLength: 8)
        }
    }

    private func chip(_ icon: String, _ text: String, _ tilt: Double) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(Color.brand)
            Text(text).shout(.caption2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .brutal(shadow: 2)
        .rotationEffect(.degrees(tilt))
    }
}

// MARK: - page 2: how you get around

private struct ProfilePage: View {
    @Binding var choice: Preset

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: -4) {
                OutlineText(text: "HOW DO YOU", font: .evenFixed(40, .bold), tracking: -1.2)
                Text("GET AROUND?")
                    .font(.evenFixed(40, .bold))
                    .tracking(-1.2)
                    .foregroundStyle(Color.brand)
            }
            .minimumScaleFactor(0.7)
            .lineLimit(1)
            .padding(.top, 6)
            .reveal(0)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("How do you get around?")
            .accessibilityAddTraits(.isHeader)

            Text("Even shapes every route around this. Change it anytime.")
                .font(.even(.body))
                .foregroundStyle(.secondary)
                .padding(.top, 10)
                .reveal(0.08)

            VStack(spacing: 12) {
                ForEach(Array(Preset.allCases.enumerated()), id: \.element) { i, preset in
                    row(preset).reveal(0.14 + Double(i) * 0.05)
                }
            }
            .padding(.top, 20)
            .padding(.trailing, 4)

            limits
                .padding(.top, 22)
                .reveal(0.4)

            Spacer(minLength: 0)
        }
    }

    private func row(_ preset: Preset) -> some View {
        let isOn = choice == preset
        return Button {
            withAnimation(.smooth(duration: 0.2)) { choice = preset }
        } label: {
            HStack(spacing: 12) {
                PresetIcon(preset: preset, size: 22)
                    .foregroundStyle(isOn ? Color.brand : Color.primary)
                    .frame(width: 40, height: 40)
                    .background(isOn ? Color.white : Color.paper)
                    .overlay(Rectangle().stroke(Color.line, lineWidth: 2))
                VStack(alignment: .leading, spacing: 1) {
                    Text(preset.label).shout(.subheadline)
                    Text(preset.blurb).font(.even(.footnote)).opacity(0.8)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.primary)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(BrutalButtonStyle(fill: isOn ? .brandSoft : .paper, shadow: isOn ? 4 : 3))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(preset.label). \(preset.limits)")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    // what the choice means, as a tilted card that updates when you tap
    private var limits: some View {
        let l = choice.numbers
        return HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Your limits").shout(.caption2)
                HStack(spacing: 14) {
                    Text("↑\(l.up)%").contentTransition(.numericText())
                    Text("↓\(l.down)%").contentTransition(.numericText())
                }
                .font(.evenFixed(30, .bold))
                .monospacedDigit()
            }
            Spacer(minLength: 0)
            Text(l.ramps ? "No steps\nRamps at every curb" : "No steps\nAny curb")
                .shout(.caption2)
                .multilineTextAlignment(.trailing)
        }
        .foregroundStyle(Color.onBrand)
        .padding(14)
        .brutal(fill: .brand, shadow: 4)
        .rotationEffect(.degrees(-1.5))
        .padding(.horizontal, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your limits: \(choice.limits)")
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
            VStack(alignment: .leading, spacing: -4) {
                OutlineText(text: "START FROM", font: .evenFixed(40, .bold), tracking: -1.2)
                Text("WHERE YOU ARE?")
                    .font(.evenFixed(40, .bold))
                    .tracking(-1.2)
                    .foregroundStyle(Color.brand)
            }
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .padding(.top, 6)
            .reveal(0)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Start from where you are?")
            .accessibilityAddTraits(.isHeader)

            Text("Even can use your location as point A, so you only choose where you're going. It's used to plan your route, only while the app is open.")
                .font(.even(.body))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
                .reveal(0.1)

            LocationIllustration()
                .frame(height: 230)
                .brutal()
                .rotationEffect(.degrees(1.5))
                .padding(.top, 30)
                .padding(.trailing, 4)
                .reveal(0.2)

            Spacer(minLength: 8)
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
            let a = CGPoint(x: w * 0.16, y: h * 0.76)
            let b = CGPoint(x: w * 0.84, y: h * 0.24)
            let around = Path { p in
                p.move(to: a)
                p.addLine(to: CGPoint(x: w * 0.84, y: h * 0.76))
                p.addLine(to: b)
            }

            ZStack {
                MapGrid()

                Ellipse()
                    .fill(Color.slopeModerate.opacity(0.25))
                    .frame(width: w * 0.42, height: h * 0.5)
                    .position(x: w * 0.5, y: h * 0.47)
                Image(systemName: "mountain.2.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.slopeModerate)
                    .position(x: w * 0.5, y: h * 0.47)

                Path { p in p.move(to: a); p.addLine(to: b) }
                    .stroke(Color.ink.opacity(0.55), style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [2, 9]))
                    .opacity(shortcut ? 1 : 0)

                around
                    .trim(from: 0, to: progress)
                    .stroke(Color.ink, style: StrokeStyle(lineWidth: style.routeWidth + 5, lineCap: .round, lineJoin: .round))
                around
                    .trim(from: 0, to: progress)
                    .stroke(Color.slopeEasy, style: StrokeStyle(lineWidth: style.routeWidth, lineCap: .round, lineJoin: .round))

                LetterPin(letter: "A", filled: false, size: 30)
                    .scaleEffect(pins ? 1 : 0.4).opacity(pins ? 1 : 0)
                    .position(a)
                LetterPin(letter: "B", size: 30)
                    .scaleEffect(pins ? 1 : 0.4).opacity(pins ? 1 : 0)
                    .position(b)
            }
        }
        .onAppear {
            if reduceMotion {
                shortcut = true; progress = 1; pins = true
                return
            }
            withAnimation(.spring(duration: 0.5, bounce: 0.3).delay(0.2)) { pins = true }
            withAnimation(.easeOut(duration: 0.4).delay(0.5)) { shortcut = true }
            withAnimation(.easeInOut(duration: 1.4).delay(0.9)) { progress = 1 }
        }
        .accessibilityHidden(true)
    }
}

/// Point A with a pulse, on the map card.
private struct LocationIllustration: View {
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            MapGrid()
            Circle()
                .stroke(Color.brand, lineWidth: 3)
                .frame(width: 140, height: 140)
                .scaleEffect(pulse ? 1 : 0.4)
                .opacity(pulse ? 0 : 1)
            LetterPin(letter: "A", filled: false, size: 44)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) { pulse = true }
        }
        .accessibilityHidden(true)
    }
}

/// A tiny street grid inside the bordered cards.
private struct MapGrid: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                Rectangle().fill(Color.paperDeep)
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
            }
            .clipped()
        }
    }
}

// MARK: - pieces

struct Wordmark: View {
    var size: CGFloat = 22
    var dot: Color = .brand

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: size * 0.06) {
            Text("even")
                .font(.evenFixed(size, .bold))
                .tracking(-size * 0.04)
            Rectangle()
                .fill(dot)
                .frame(width: size * 0.24, height: size * 0.24)
                .padding(.bottom, size * 0.14)
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
