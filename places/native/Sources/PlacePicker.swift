import CoreLocation
import MapKit
import NucleusUI
import SwiftUI
import TodoPluginKit

/// Search for a place (or use where you are), then set how close counts.
struct PlacePicker: View {
    @Binding var selection: TaskLocation?
    let host: any TodoHost
    @Environment(\.dismiss) private var dismiss
    @State private var search = PlaceSearch()
    @State private var place: TaskLocation?
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var resolving = false
    @FocusState private var searching: Bool

    init(selection: Binding<TaskLocation?>, host: any TodoHost) {
        _selection = selection
        self.host = host
        _place = State(initialValue: selection.wrappedValue)
        if let p = selection.wrappedValue {
            _camera = State(initialValue: .region(MKCoordinateRegion(center: p.coordinate, latitudinalMeters: p.radius * 8, longitudinalMeters: p.radius * 8)))
        }
    }

    var body: some View {
        NucleusSheetPage("Place", canConfirm: place != nil, onCancel: { dismiss() }, onConfirm: {
            selection = place
            if place?.remind == true { askForPermissions(host) }
            dismiss()
        }) {
            searchField.padding(.bottom, 16)
            if searching || (!search.query.isEmpty && place == nil) {
                results
            } else {
                map
                if let p = place { details(p) }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Nucleus.secondaryText)
            TextField("Search for a place or address", text: $search.query)
                .focused($searching)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if resolving { ProgressView().controlSize(.small) }
        }
        .font(.system(size: 16))
        .padding(.horizontal, 16)
        .frame(height: 50)
        .nucleusGlass(in: Capsule())
    }

    private var results: some View {
        NucleusSection {
            Button { useCurrentLocation() } label: {
                NucleusRow("Current location", icon: IconTile("location.fill", tint: .blue))
            }
            .buttonStyle(NucleusRowButtonStyle())
            ForEach(search.results, id: \.self) { result in
                Button { pick(result) } label: {
                    NucleusRow(verbatim: result.title, subtitle: result.subtitle.isEmpty ? nil : Text(verbatim: result.subtitle), icon: IconTile("mappin", tint: .teal))
                }
                .buttonStyle(NucleusRowButtonStyle())
            }
        }
    }

    private var map: some View {
        MapReader { proxy in
            Map(position: $camera) {
                if let p = place {
                    MapCircle(center: p.coordinate, radius: p.radius)
                        .foregroundStyle(NucleusTint.teal.color.opacity(0.2))
                        .stroke(NucleusTint.teal.color, lineWidth: 2)
                    Marker(p.name, systemImage: "mappin", coordinate: p.coordinate).tint(NucleusTint.teal.color)
                }
                UserAnnotation()
            }
            .onTapGesture { point in
                // Tapping the map moves the pin there.
                guard let coord = proxy.convert(point, from: .local) else { return }
                Haptics.tap()
                move(to: coord)
            }
        }
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: NucleusRadius.card, style: .continuous))
        .overlay(alignment: .bottom) {
            if place == nil {
                Text("Search above, or tap the map")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .nucleusGlass(in: Capsule())
                    .padding(12)
            }
        }
        .padding(.bottom, 24)
    }

    private func details(_ p: TaskLocation) -> some View {
        NucleusSection(footer: Text("iOS needs a radius of at least 100 m to notice you arriving or leaving reliably.")) {
            NucleusField("Name", text: Binding(get: { place?.name ?? "" }, set: { place?.name = $0 }), prompt: "Home")
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Radius").font(.system(size: 16))
                    Spacer()
                    Text(Measurement(value: p.radius, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road)))
                        .font(.system(size: 14).monospacedDigit())
                        .foregroundStyle(Nucleus.secondaryText)
                }
                Slider(value: Binding(get: { p.radius }, set: { place?.radius = $0.rounded() }), in: 100...2000, step: 50)
                    .tint(NucleusTint.teal.color)
            }
            .padding(16)
        }
    }

    private func pick(_ completion: MKLocalSearchCompletion) {
        searching = false
        resolving = true
        Task {
            defer { resolving = false }
            guard let item = try? await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start().mapItems.first else { return }
            let coord = item.placemark.coordinate
            withAnimation(NucleusMotion.ease) {
                place = TaskLocation(name: item.name ?? completion.title, address: completion.subtitle, latitude: coord.latitude,
                                     longitude: coord.longitude, radius: place?.radius ?? 150, trigger: place?.trigger ?? .arrive)
                camera = .region(MKCoordinateRegion(center: coord, latitudinalMeters: 1200, longitudinalMeters: 1200))
            }
            search.query = ""
        }
    }

    private func move(to coord: CLLocationCoordinate2D) {
        searching = false
        let keepName = place?.name
        withAnimation(NucleusMotion.quick) {
            place = TaskLocation(name: keepName ?? String(localized: "Pinned place"), latitude: coord.latitude, longitude: coord.longitude,
                                 radius: place?.radius ?? 150, trigger: place?.trigger ?? .arrive)
        }
        Task {
            if let mark = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: coord.latitude, longitude: coord.longitude)).first {
                place?.address = [mark.thoroughfare, mark.subThoroughfare, mark.locality].compactMap { $0 }.joined(separator: " ")
                if keepName == nil { place?.name = mark.name ?? place?.name ?? "" }
            }
        }
    }

    private func useCurrentLocation() {
        Locator.shared.requestPermission()
        resolving = true
        Task {
            defer { resolving = false }
            guard let here = await Locator.shared.currentLocation() else { return }
            withAnimation(NucleusMotion.ease) {
                camera = .region(MKCoordinateRegion(center: here.coordinate, latitudinalMeters: 1200, longitudinalMeters: 1200))
            }
            place = nil
            move(to: here.coordinate)
            search.query = ""
        }
    }
}

/// Search-as-you-type for places.
@MainActor
@Observable
final class PlaceSearch: NSObject, MKLocalSearchCompleterDelegate {
    var query = "" { didSet { completer.queryFragment = query } }
    private(set) var results: [MKLocalSearchCompletion] = []
    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        // The completer calls back on the main thread, where it was made.
        nonisolated(unsafe) let results = completer.results
        MainActor.assumeIsolated { self.results = Array(results.prefix(8)) }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {}
}
