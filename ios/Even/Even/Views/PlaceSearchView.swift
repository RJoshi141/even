import MapKit
import SwiftUI

struct PlaceSearchView: View {
    let title: String                 // "From" or "To"
    let allowsCurrentLocation: Bool
    let onPick: (Place) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [Place] = []
    @State private var searching = false
    @State private var locating = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    if allowsCurrentLocation {
                        Button {
                            Task { await useCurrentLocation() }
                        } label: {
                            Label(locating ? "Finding you…" : "Current location", systemImage: "location.fill")
                        }
                        .disabled(locating)
                    }
                    Section("Suggested") {
                        ForEach(Places.suggestions) { row($0) }
                    }
                } else {
                    ForEach(results) { row($0) }
                    if results.isEmpty && !searching {
                        Text("No matches in \(Coverage.description) yet")
                            .foregroundStyle(.secondary)
                    }
                }
                if let errorText {
                    Text(errorText).foregroundStyle(Color.slopeOver)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search places or addresses")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            // reruns on every keystroke; the old run gets cancelled, which doubles as a debounce
            .task(id: query) { await search() }
        }
    }

    private func row(_ place: Place) -> some View {
        Button {
            onPick(place)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).foregroundStyle(.primary)
                if let subtitle = place.subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { results = []; return }

        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = q
        request.region = Coverage.region
        request.regionPriority = .required   // only results inside the covered area
        request.resultTypes = [.pointOfInterest, .address]

        searching = true
        defer { searching = false }
        do {
            let response = try await MKLocalSearch(request: request).start()
            guard !Task.isCancelled else { return }
            results = response.mapItems.map { item in
                let c = item.placemark.coordinate
                return Place(name: item.name ?? q,
                             point: GeoPoint(lat: c.latitude, lon: c.longitude),
                             subtitle: item.placemark.title)
            }
        } catch {
            results = []
        }
    }

    private func useCurrentLocation() async {
        locating = true
        defer { locating = false }
        do {
            let location = try await LocationProvider.current()
            onPick(Place(name: "Current location",
                         point: GeoPoint(lat: location.coordinate.latitude, lon: location.coordinate.longitude)))
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
