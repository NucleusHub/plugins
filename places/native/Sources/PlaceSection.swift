import MapKit
import NucleusUI
import SwiftUI
import TodoPluginKit

/// The task editor's Place section.
struct PlaceSection: View {
    @Binding var location: TaskLocation?
    let host: any TodoHost
    @State private var picking = false

    var body: some View {
        NucleusSection("Place", footer: location == nil ? Text("Get reminded when you arrive somewhere, or leave it.") : nil) {
            if let place = location {
                PlacePreview(place: place)
                    .frame(height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(12)
                    .onTapGesture { picking = true }
                NucleusRow(verbatim: place.name, subtitle: place.address.isEmpty ? nil : Text(verbatim: place.address), icon: IconTile("mappin", tint: .teal))
                NucleusSegmented(selection: Binding(get: { place.trigger }, set: { location?.trigger = $0 }),
                                 items: [(TaskLocation.Trigger.arrive, LocalizedStringKey("When I arrive")), (.leave, LocalizedStringKey("When I leave"))], fill: true)
                    .padding(12)
                Toggle(isOn: Binding(get: { place.remind }, set: { on in
                    location?.remind = on
                    if on { askForPermissions(host) }
                })) {
                    Label { Text("Remind me there") } icon: { IconTile("location.fill", tint: .blue) }.font(.system(size: 16))
                }
                .tint(Color(hex: 0x34C759))
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                Button { withAnimation(NucleusMotion.quick) { location = nil } } label: {
                    NucleusRow("Remove place", titleColor: Nucleus.danger)
                }
                .buttonStyle(NucleusRowButtonStyle())
            } else {
                Button { picking = true } label: {
                    NucleusRow("Add a place", icon: IconTile("mappin.and.ellipse", tint: .teal)) { Chevron() }
                }
                .buttonStyle(NucleusRowButtonStyle())
            }
        }
        .sheet(isPresented: $picking) {
            PlacePicker(selection: $location, host: host).presentationDragIndicator(.visible)
        }
    }
}

/// A place reminder needs both notifications and location.
@MainActor
func askForPermissions(_ host: any TodoHost) {
    Locator.shared.host = host
    Task {
        await host.requestNotifications()
        Locator.shared.requestPermission()
    }
}

/// A small map of the place with its reminder radius.
struct PlacePreview: View {
    let place: TaskLocation

    var body: some View {
        Map(initialPosition: .region(MKCoordinateRegion(center: place.coordinate, latitudinalMeters: place.radius * 6, longitudinalMeters: place.radius * 6)),
            interactionModes: []) {
            MapCircle(center: place.coordinate, radius: place.radius)
                .foregroundStyle(NucleusTint.teal.color.opacity(0.2))
                .stroke(NucleusTint.teal.color, lineWidth: 1.5)
            Marker(place.name, systemImage: "mappin", coordinate: place.coordinate).tint(NucleusTint.teal.color)
        }
        .id(place)
    }
}
