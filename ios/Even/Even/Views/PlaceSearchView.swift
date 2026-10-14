import MapKit
import SwiftUI
import UIKit

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
    @State private var showSettings = false
    @Environment(\.openURL) private var openURL

    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            searchField
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if query.isEmpty {
                        if allowsCurrentLocation { currentLocationButton }
                        if let errorText { errorCard(errorText) }
                        Text("Suggested").shout(.caption).foregroundStyle(.secondary)
                        list(Places.suggestions)
                    } else if !results.isEmpty {
                        list(results)
                    } else if !searching {
                        Text("No matches in \(Coverage.description) yet")
                            .font(.even(.subheadline))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
                .padding(.top, 2)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .padding(.top, 20)
        .background(GridPaper().ignoresSafeArea())
        .presentationBackground(Color.paper)
        // reruns on every keystroke; the old run gets cancelled, which doubles as a debounce
        .task(id: query) { await search() }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title == "From" ? "START" : "GOING")
                    .font(.evenFixed(34, .bold)).tracking(-1)
                Text(title == "From" ? "FROM?" : "TO?")
                    .font(.evenFixed(34, .bold)).tracking(-1)
                    .foregroundStyle(Color.brand)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.primary)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(BrutalButtonStyle(shadow: 3))
            .accessibilityLabel("Cancel")
        }
        .padding(.horizontal, 20)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .bold))
            TextField("Search places or addresses", text: $query)
                .font(.even(.body))
                .focused($fieldFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if searching {
                ProgressView().controlSize(.small)
            } else if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .brutal(fill: fieldFocused ? .white : .paper, shadow: fieldFocused ? 4 : 2)
        .animation(.snappy(duration: 0.15), value: fieldFocused)
        .padding(.horizontal, 20)
        .onTapGesture { fieldFocused = true }
    }

    private var currentLocationButton: some View {
        Button {
            Task { await useCurrentLocation() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: locating ? "location" : "location.fill")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 36, height: 36)
                    .background(Color.white, in: Circle())
                    .overlay(Circle().stroke(Color.ink, lineWidth: 2))
                    .foregroundStyle(Color.brand)
                Text(locating ? "Finding you…" : "Use my location").shout(.subheadline)
                Spacer()
                Image(systemName: "arrow.right").font(.system(size: 15, weight: .bold))
            }
            .foregroundStyle(Color.onBrand)
            .padding(.horizontal, 14)
            .frame(height: 60)
        }
        .buttonStyle(BrutalButtonStyle(fill: .brand))
        .disabled(locating)
    }

    private func errorCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text).font(.even(.subheadline))
            if showSettings {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Text("Open Settings").shout(.caption).foregroundStyle(Color.ink)
                        .padding(.horizontal, 12).frame(height: 36)
                }
                .buttonStyle(BrutalButtonStyle(shadow: 2))
            }
        }
        .foregroundStyle(Color.white)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .brutal(fill: .warning, shadow: 3)
    }

    private func list(_ places: [Place]) -> some View {
        VStack(spacing: 0) {
            ForEach(places) { row($0) }
        }
    }

    private func row(_ place: Place) -> some View {
        Button {
            onPick(place)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "mappin")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.ink)
                    .frame(width: 30, height: 30)
                    .background(Color.white, in: Circle())
                    .overlay(Circle().stroke(Color.ink, lineWidth: 1.5))
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name)
                        .font(.even(.body, .semibold))
                        .foregroundStyle(Color.primary)
                    if let subtitle = place.subtitle {
                        Text(subtitle).font(.even(.caption)).foregroundStyle(.secondary)
                    }
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 12)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
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
                let c = item.location.coordinate
                return Place(name: item.name ?? q,
                             point: GeoPoint(lat: c.latitude, lon: c.longitude),
                             subtitle: item.address?.shortAddress ?? item.address?.fullAddress)
            }
        } catch {
            results = []
        }
    }

    private func useCurrentLocation() async {
        locating = true
        errorText = nil
        showSettings = false
        defer { locating = false }
        do {
            let location = try await LocationProvider.current()
            // check before routing, so the user hears why instead of seeing a failed route
            guard Coverage.contains(location.coordinate) else {
                errorText = "You're outside the area Even covers so far (\(Coverage.description) in San Francisco). Pick a starting point there for now."
                return
            }
            onPick(Place(name: "Current location",
                         point: GeoPoint(lat: location.coordinate.latitude, lon: location.coordinate.longitude)))
            dismiss()
        } catch let error as LocationProvider.LocationError {
            errorText = error.localizedDescription
            showSettings = error == .denied
        } catch {
            errorText = error.localizedDescription
        }
    }
}
