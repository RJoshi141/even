import SwiftUI

struct RouteCompareView: View {
    @State private var model = RouteViewModel()
    private var style: EvenStyle { StyleStore.shared.current }
    @State private var editing: Field?
    @State private var swaps = 0
    @State private var fitTrigger = 0
    @State private var expanded = false

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
        .sheet(item: $editing) { field in
            PlaceSearchView(title: field == .origin ? "From" : "To",
                            allowsCurrentLocation: field == .origin) { place in
                if field == .origin { model.origin = place } else { model.destination = place }
            }
        }
        .animation(.snappy, value: model.tapped)
        .animation(.snappy, value: model.showLegend)
        // the active style's type and icon treatment, applied to everything below
        .fontDesign(style.fontDesign)
        .fontWidth(style.fontWidth)
        .symbolVariant(style.filledIcons ? .fill : .none)
        .symbolRenderingMode(style.hierarchicalIcons ? .hierarchical : .monochrome)
        .tint(style.accent)
    }

    // MARK: top: just from and to

    private var placesCard: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                placeRow(letter: "A", fill: .ink, place: model.origin) { editing = .origin }
                    .accessibilityLabel("From \(model.origin.name)")
                Divider().padding(.leading, 40)
                placeRow(letter: "B", fill: .brand, place: model.destination) { editing = .destination }
                    .accessibilityLabel("To \(model.destination.name)")
            }

            Button {
                withAnimation(.snappy) { model.swap() }
                swaps += 1
            } label: {
                Image(systemName: style.icons.swap)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .symbolEffect(.bounce, value: swaps)
                    .frame(width: 44, height: 80)
            }
            .accessibilityLabel("Swap start and destination")
        }
        .background(.regularMaterial, in: .rect(cornerRadius: style.corner + 4))
        .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
        .padding(.horizontal, 12)
    }

    private func placeRow(letter: String, fill: Color, place: Place, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(letter)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(fill, in: .rect(cornerRadius: style.pin == .circle ? 9 : 4))
                Text(place.name)
                    .font(.subheadline.weight(.medium))
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
            if model.showLegend {
                LegendPanel(profile: model.response?.profile)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            VStack(spacing: 8) {
                VStack(spacing: 0) {
                    Menu {
                        Picker("Profile", selection: $model.preset) {
                            ForEach(Preset.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                        }
                    } label: {
                        controlIcon(model.preset.symbol, on: false)
                    }
                    .accessibilityLabel("Mobility profile, \(model.preset.label)")

                    Divider().frame(width: 24)
                    controlButton(style.icons.legend, "Legend", on: model.showLegend) {
                        model.showLegend.toggle()
                    }
                    Divider().frame(width: 24)
                    controlButton(style.icons.layers, "Slope layer", on: model.slopeLayerOn) {
                        Task { await model.toggleSlopeLayer() }
                    }
                    Divider().frame(width: 24)
                    controlButton(style.icons.fit, "Fit route on screen", on: false) {
                        fitTrigger += 1
                    }
                    Divider().frame(width: 24)
                    styleMenu
                }
                .background(.regularMaterial, in: .rect(cornerRadius: style.corner))
                .shadow(color: .black.opacity(0.1), radius: 6, y: 2)

                if model.slopeLayerOn, model.network?.tooLarge == true {
                    Text("Zoom in")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.regularMaterial, in: Capsule())
                }
            }
        }
        .padding(.trailing, 12)
        .padding(.top, 8)
    }

    private func controlIcon(_ icon: String, on: Bool) -> some View {
        Image(systemName: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(on ? Color.brand : Color.primary)
            .frame(width: 40, height: 40)
            .background(on ? Color.brand.opacity(0.15) : .clear, in: .rect(cornerRadius: max(style.corner - 3, 4)))
            .padding(2)
    }

    // Style Lab: try every look on the real map
    private var styleMenu: some View {
        Menu {
            Picker("Style", selection: Binding(
                get: { StyleStore.shared.current.id },
                set: { id in
                    if let s = EvenStyle.all.first(where: { $0.id == id }) {
                        withAnimation(.snappy) { StyleStore.shared.current = s }
                    }
                })) {
                ForEach(EvenStyle.all) { s in
                    Text("\(s.name)  ·  \(s.blurb)").tag(s.id)
                }
            }
        } label: {
            controlIcon("paintpalette", on: false)
        }
        .accessibilityLabel("Style, \(style.name)")
    }

    private func controlButton(_ icon: String, _ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { controlIcon(icon, on: on) }
            .accessibilityLabel(label)
            .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: bottom

    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.tapped != nil {
                InspectCard(info: model.inspected,
                            loading: model.inspecting,
                            profile: model.response?.profile,
                            onRouteFrom: { Task { await model.useTapped(asOrigin: true) } },
                            onRouteTo: { Task { await model.useTapped(asOrigin: false) } },
                            onClose: { model.closeInspect() })
                    .transition(.opacity)
            } else {
                switch model.state {
                case .loading:
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Finding the gentlest way…").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                case .failed(let message):
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.berry)
                        Text(message).font(.subheadline).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Button("Retry") { Task { await model.load() } }
                            .font(.subheadline.weight(.semibold))
                    }
                case .loaded(let r):
                    ComparePanel(response: r, selected: $model.selected, expanded: $expanded,
                                 destinationName: model.destination.name)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: style.sheetCorner, topTrailingRadius: style.sheetCorner)
                .fill(Color(uiColor: .systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 12, y: -2)
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

#Preview {
    RouteCompareView()
}
