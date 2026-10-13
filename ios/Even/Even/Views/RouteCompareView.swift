import SwiftUI

struct RouteCompareView: View {
    @State private var model = RouteViewModel()
    @State private var editing: Field?

    enum Field: String, Identifiable {
        case origin, destination
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                content
            }
            .navigationTitle("Route options")
            .navigationBarTitleDisplayMode(.inline)
        }
        // reloads whenever origin, destination or profile changes
        .task(id: model.requestKey) { await model.load() }
        .sheet(item: $editing) { field in
            PlaceSearchView(title: field == .origin ? "From" : "To",
                            allowsCurrentLocation: field == .origin) { place in
                if field == .origin { model.origin = place } else { model.destination = place }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            // from / to, like a maps app
            HStack(spacing: 8) {
                VStack(spacing: 0) {
                    placeRow(icon: "circle", tint: .secondary, place: model.origin, bold: false) {
                        editing = .origin
                    }
                    .accessibilityLabel("From \(model.origin.name)")

                    Divider().padding(.leading, 44)

                    placeRow(icon: "mappin.circle.fill", tint: Color.evenTeal, place: model.destination, bold: true) {
                        editing = .destination
                    }
                    .accessibilityLabel("To \(model.destination.name)")
                }
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))

                Button {
                    model.swap()
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Swap start and destination")
            }

            // mobility profile as a chip, limits shown once the server confirms them
            Menu {
                Picker("Profile", selection: $model.preset) {
                    ForEach(Preset.allCases) { Text($0.label).tag($0) }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "figure.roll")
                    Text(profileText)
                    Image(systemName: "chevron.down").font(.caption2)
                }
                .font(.subheadline)
                .foregroundStyle(Color.evenTeal)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.evenTeal.opacity(0.1), in: Capsule())
            }
            .accessibilityLabel("Mobility profile, \(profileText)")
            .accessibilityHint("Change your mobility profile")
        }
        .padding(.horizontal)
        .padding(.bottom, 10)
    }

    private func placeRow(icon: String, tint: Color, place: Place, bold: Bool,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                    .frame(width: 20)
                Text(place.name)
                    .fontWeight(bold ? .semibold : .regular)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Search for a place")
    }

    private var profileText: String {
        if case .loaded(let r) = model.state {
            return "\(model.preset.label) · up \(Int(r.profile.maxUphill))% · down \(Int(r.profile.maxDownhill))%"
        }
        return model.preset.label
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .loading:
            ProgressView("Finding routes…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't load routes", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await model.load() } }
            }
        case .loaded(let response):
            loaded(response)
        }
    }

    private func loaded(_ response: RouteResponse) -> some View {
        VStack(spacing: 0) {
            RouteMapView(response: response, selected: model.selected,
                         origin: model.origin, destination: model.destination)
                .id(model.requestKey) // fresh camera fit for each new request

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(response.routes) { route in
                        // when both are the same path, one card is enough
                        if !(response.identical && route.kind == .shortest) {
                            RouteCard(route: route, profile: response.profile,
                                      isSelected: model.selected == route.kind) {
                                model.selected = route.kind
                            }
                        }
                    }
                    if response.identical {
                        Text("The shortest route already fits your profile.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .frame(maxHeight: 380)
        }
    }
}

#Preview {
    RouteCompareView()
}
