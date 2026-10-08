import CoreLocation
import NucleusPlugins
import NucleusUI
import SwiftUI
import TodoPluginKit
import UserNotifications

/// Places: a place on a task, and a reminder when you arrive there or leave.
public struct PlacesPlugin: Plugin {
    public let manifest: PluginManifest

    public init() {
        manifest = (try? PluginManifest.load(from: Bundle.module)) ?? PluginManifest(
            id: "places", name: "Places", version: "1.0.0", target: ["todo"]
        )
    }

    public func register(with registrar: PluginRegistrar) {
        registrar.contribute(to: .editorSections, id: "places", PlaceEditorSection() as any TaskEditorSection)
        registrar.contribute(to: .taskDetails, id: "places", PlaceDetail() as any TaskDetail)
        registrar.contribute(to: .smartLists, id: "places", SmartListDefinition(
            title: "Places", icon: "mappin.and.ellipse", tint: .teal,
            emptyMessage: "Give a task a place to be reminded when you get there.",
            contains: { !$0.done && $0.location != nil }
        ))
        registrar.contribute(to: .reminderSources, id: "places", PlaceReminders() as any ReminderSource)
        registrar.contribute(to: .notificationSettings, id: "places", PlaceSettings() as any SettingsRows)
    }
}

struct PlaceEditorSection: TaskEditorSection {
    @MainActor
    func view(_ context: TaskEditorContext) -> AnyView {
        AnyView(PlaceSection(location: context.location, host: context.host))
    }
}

struct PlaceDetail: TaskDetail {
    func chip(for task: PluginTask) -> TaskChip? { task.location.map { TaskChip(icon: "mappin", text: $0.name) } }
    func shareLine(for task: PluginTask) -> String? { task.location.map { "📍 \($0.name)" } }
    func searchText(for task: PluginTask) -> String? { task.location?.name }
}

struct PlaceReminders: ReminderSource {
    /// iOS watches 20 regions per app.
    static let maxPlaces = 14

    @MainActor
    func reminders(for tasks: [PluginTask], host: any TodoHost) -> [PluginReminder] {
        let locator = Locator.shared
        locator.host = host
        guard locator.allowed else { return [] }
        return tasks.compactMap { t -> PluginReminder? in
            guard let place = t.location, place.remind else { return nil }
            let region = CLCircularRegion(center: place.coordinate, radius: max(100, place.radius), identifier: "task.\(t.id)")
            region.notifyOnEntry = place.trigger == .arrive
            region.notifyOnExit = place.trigger == .leave
            let body = place.trigger == .arrive ? String(localized: "You're at \(place.name).") : String(localized: "You left \(place.name).")
            return PluginReminder(taskID: t.id, kind: "place", body: body, trigger: UNLocationNotificationTrigger(region: region, repeats: true))
        }
        .prefix(Self.maxPlaces).map { $0 }
    }
}

struct PlaceSettings: SettingsRows {
    @MainActor
    func view(host: any TodoHost) -> AnyView {
        AnyView(PlaceSettingsRows(host: host))
    }
}

/// Asks for location, or points to iOS Settings when it was refused.
private struct PlaceSettingsRows: View {
    let host: any TodoHost
    @Environment(\.openURL) private var openURL

    var body: some View {
        let locator = Locator.shared
        if locator.status == .notDetermined {
            Button { locator.host = host; locator.requestPermission() } label: {
                NucleusRow("Allow place reminders", icon: IconTile("location.fill", tint: .blue)) { Chevron() }
            }
            .buttonStyle(NucleusRowButtonStyle())
        } else if !locator.allowed {
            Button { openURL(URL(string: UIApplication.openSettingsURLString)!) } label: {
                NucleusRow("Place reminders are off", subtitle: Text("Allow location in iOS Settings"), icon: IconTile("location.slash.fill", tint: .slate)) {
                    Image(systemName: "arrow.up.right").foregroundStyle(Nucleus.secondaryText)
                }
            }
            .buttonStyle(NucleusRowButtonStyle())
        }
    }
}
