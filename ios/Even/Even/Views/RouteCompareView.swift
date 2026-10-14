import SwiftUI

struct RouteCompareView: View {
    @State private var model = RouteViewModel()
    private var style: EvenStyle { StyleStore.shared.current }
    @State private var editing: Field?
    @State private var swaps = 0
    @State private var fitTrigger = 0
    @State private var popup: TripPanel?
    @State private var showProfiles = false

    enum Field: String, Identifiable {
        case origin, destination
        var id: String { rawValue }
    }

    var body: some View {
        RouteMapView(model: model, fitTrigger: fitTrigger) { coordinate in
            Task { await model.inspect(at: coordinate) }
        }
        .overlay(alignment: .topTrailing) { mapControls }
        .safeAreaInset(edge: .top) { placesCard }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomPanel }
        .task(id: model.requestKey) { await model.load() }
        .task { await model.prepareStart() }
        .overlay { popupLayer }
        .sheet(item: $editing) { field in
            PlaceSearchView(title: field == .origin ? "From" : "To",
                            allowsCurrentLocation: field == .origin) { place in
                if field == .origin { model.origin = place } else { model.destination = place }
            }
        }
        .animation(.snappy, value: model.tapped)
        .animation(.snappy, value: model.showLegend)
        // the active style's type and icon treatment, applied to everything below
        .symbolVariant(style.filledIcons ? .fill : .none)
        .symbolRenderingMode(style.hierarchicalIcons ? .hierarchical : .monochrome)
        .tint(style.accent)
    }

    // MARK: top: just from and to

    private var placesCard: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                placeRow(letter: "A", filled: false, place: model.origin) { editing = .origin }
                    .accessibilityLabel("From \(model.origin.name)")
                Divider().padding(.leading, 40)
                placeRow(letter: "B", filled: true, place: model.destination) { editing = .destination }
                    .accessibilityLabel("To \(model.destination.name)")
            }

            Button {
                withAnimation(.snappy) { model.swap() }
                swaps += 1
            } label: {
                Image(systemName: style.icons.swap)
                    .font(.even(.subheadline, .semibold))
                    .foregroundStyle(.secondary)
                    .symbolEffect(.bounce, value: swaps)
                    .frame(width: 44, height: 80)
            }
            .accessibilityLabel("Swap start and destination")
        }
        .background(Color.paper, in: .rect(cornerRadius: style.corner + 4))
        .overlay(RoundedRectangle(cornerRadius: style.corner + 4).stroke(Color.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        .padding(.horizontal, 12)
    }

    private func placeRow(letter: String, filled: Bool, place: Place, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                LetterPin(letter: letter, filled: filled, size: 20)
                Text(place.name)
                    .font(.even(.subheadline, .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, 12)
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Search for a place")
    }

    // MARK: right side: profile, legend, layers, fit

    private var mapControls: some View {
        HStack(alignment: .top, spacing: 8) {
            // one panel at a time, opening beside the controls
            if showProfiles {
                ProfilePanel(selection: $model.preset,
                             onPicked: { withAnimation(.snappy) { showProfiles = false } },
                             onSetUpAgain: { UserDefaults.standard.set(false, forKey: "onboarded") })
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if model.showLegend {
                LegendPanel(profile: model.response?.profile)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            VStack(spacing: 8) {
                VStack(spacing: 4) {
                    Button {
                        withAnimation(.snappy) {
                            showProfiles.toggle()
                            if showProfiles { model.showLegend = false }
                        }
                    } label: {
                        PresetIcon(preset: model.preset, size: 21)
                            .foregroundStyle(showProfiles ? Color.onHighlight : Color.primary)
                            .frame(width: 44, height: 44)
                            .background(showProfiles ? Color.highlight : .clear, in: .rect(cornerRadius: style.corner))
                    }
                    .accessibilityLabel("Mobility profile, \(model.preset.label)")
                    .accessibilityAddTraits(showProfiles ? .isSelected : [])

                    controlButton(style.icons.legend, "Legend", on: model.showLegend) {
                        withAnimation(.snappy) {
                            model.showLegend.toggle()
                            if model.showLegend { showProfiles = false }
                        }
                    }
                    controlButton(style.icons.layers, "Slope layer", on: model.slopeLayerOn) {
                        Task { await model.toggleSlopeLayer() }
                    }
                    controlButton(style.icons.fit, "Fit route on screen", on: false) {
                        fitTrigger += 1
                    }
                }
                .padding(4)
                .background(Color.paper, in: .rect(cornerRadius: style.corner + 4))
                .overlay(RoundedRectangle(cornerRadius: style.corner + 4).stroke(Color.hairline, lineWidth: 1))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)

                if model.slopeLayerOn, model.network?.tooLarge == true {
                    Text("Zoom in")
                        .font(.even(.caption2, .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.paper, in: Capsule())
                        .overlay(Capsule().stroke(Color.hairline, lineWidth: 1))
                }
            }
        }
        .padding(.trailing, 12)
        .padding(.top, 8)
    }

    private func controlIcon(_ icon: String, on: Bool) -> some View {
        Image(systemName: icon)
            .font(.system(size: 18, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(on ? Color.onHighlight : Color.primary)
            .frame(width: 44, height: 44)
            .background(on ? Color.highlight : .clear, in: .rect(cornerRadius: style.corner))
            .contentShape(Rectangle())
    }

    private func controlButton(_ icon: String, _ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { controlIcon(icon, on: on) }
            .accessibilityLabel(label)
            .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: bottom

    @ViewBuilder private var bottomPanel: some View {
        if model.tapped != nil {
            // tapped spot: a paper panel from the bottom edge
            InspectCard(info: model.inspected,
                        loading: model.inspecting,
                        profile: model.response?.profile,
                        onRouteFrom: { Task { await model.useTapped(asOrigin: true) } },
                        onRouteTo: { Task { await model.useTapped(asOrigin: false) } },
                        onClose: { model.closeInspect() },
                        originName: model.origin.name,
                        destinationName: model.destination.name)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    UnevenRoundedRectangle(topLeadingRadius: style.sheetCorner, topTrailingRadius: style.sheetCorner)
                        .fill(Color.paper)
                        .overlay(alignment: .top) { Rectangle().fill(Color.hairline).frame(height: 1) }
                        .shadow(color: .black.opacity(0.06), radius: 10, y: -2)
                        .ignoresSafeArea(edges: .bottom)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            // routes: cards floating over the map, the map stays full screen
            Group {
                switch model.state {
                case .loading:
                    floating {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Finding the gentlest way…").font(.even(.subheadline)).foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                        }
                    }
                case .failed(let message):
                    floating {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.warning)
                            Text(message).font(.even(.subheadline)).foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            Button("Retry") { Task { await model.load() } }
                                .font(.even(.subheadline, .semibold))
                        }
                    }
                case .loaded(let r):
                    if let route = r.routes.first(where: { $0.kind == .fitsProfile }) {
                        TripCard(route: route, profile: r.profile,
                                 destinationName: model.destination.name) { panel in
                            withAnimation(.snappy(duration: 0.25)) { popup = panel }
                        }
                    }
                }
            }
            .padding(.bottom, 8)
            .transition(.opacity)
        }
    }

    // trip info / directions, centered over a dimmed map
    @ViewBuilder private var popupLayer: some View {
        if let panel = popup, let r = model.response {
            GeometryReader { geo in
                ZStack {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .onTapGesture { closePopup() }
                        .accessibilityHidden(true)
                    TripPopup(panel: panel, response: r,
                              originName: model.origin.name, destinationName: model.destination.name,
                              maxHeight: geo.size.height * 0.78, onClose: closePopup)
                        .padding(.horizontal, 16)
                        .transition(.scale(scale: 0.96).combined(with: .opacity))
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .transition(.opacity)
            .zIndex(10)
        }
    }

    private func closePopup() {
        withAnimation(.snappy(duration: 0.2)) { popup = nil }
    }

    private func floating<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(14)
            .background(Color.paper, in: .rect(cornerRadius: style.corner + 4))
            .overlay(RoundedRectangle(cornerRadius: style.corner + 4).stroke(Color.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
            .padding(.horizontal, 12)
    }
}

#Preview {
    RouteCompareView()
}
