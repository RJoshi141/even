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
        VStack(alignment: .leading, spacing: 4) {
            Label(model.origin.name, systemImage: "circle")
                .font(.subheadline)
            Picker("Destination", selection: $model.destination) {
                ForEach(Places.destinations) { Text($0.name).tag($0) }
            }
            Picker("Profile", selection: $model.preset) {
                ForEach(Preset.allCases) { Text($0.label).tag($0) }
            }
        }
        .pickerStyle(.menu)
        .padding(.horizontal)
        .padding(.bottom, 8)
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
