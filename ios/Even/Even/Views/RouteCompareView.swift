import SwiftUI

struct RouteCompareView: View {
    @State private var model = RouteViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                content
            }
            .navigationTitle("Route options")
            .navigationBarTitleDisplayMode(.inline)
        }
        // reloads whenever destination or profile changes
        .task(id: model.requestKey) { await model.load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            // from / to, like a maps app
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "circle")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    Text(model.origin.name)
                    Spacer()
                }
                .padding(12)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("From \(model.origin.name)")

                Divider().padding(.leading, 44)

                Menu {
                    Picker("Destination", selection: $model.destination) {
                        ForEach(Places.destinations) { Text($0.name).tag($0) }
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(Color.evenTeal)
                            .frame(width: 20)
                        Text(model.destination.name)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("To \(model.destination.name)")
                .accessibilityHint("Choose a destination")
            }
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))

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
