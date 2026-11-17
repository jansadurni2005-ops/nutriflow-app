import Foundation
import CoreGraphics
import Observation
import EventKit
import SwiftData

/// Importación de calendario (incluido Google Calendar) mediante EventKit.
///
/// Para Google Calendar: añade tu cuenta de Google en Ajustes de iOS › Calendario › Cuentas.
/// iOS sincroniza esos eventos y EventKit los expone a FOCUS OS sin OAuth adicional.
/// FOCUS OS solo LEE eventos: nunca crea, modifica ni borra nada en tu calendario.
/// Los eventos importados guardan su identificador para no duplicarse.
@MainActor
@Observable
final class CalendarImportService {
    static let shared = CalendarImportService()

    private let store = EKEventStore()
    private(set) var status: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    var lastError: String?

    var hasReadAccess: Bool {
        status == .fullAccess
    }

    func refreshStatus() {
        status = EKEventStore.authorizationStatus(for: .event)
    }

    func requestAccess() async {
        do {
            _ = try await store.requestFullAccessToEvents()
        } catch {
            lastError = error.localizedDescription
        }
        refreshStatus()
    }

    struct CalendarInfo: Identifiable, Hashable {
        var id: String
        var title: String
        var source: String
        var colorHex: String
    }

    func calendars() -> [CalendarInfo] {
        guard hasReadAccess else { return [] }
        return store.calendars(for: .event).map {
            CalendarInfo(id: $0.calendarIdentifier, title: $0.title, source: $0.source.title,
                         colorHex: Self.hex(from: $0.cgColor))
        }
        .sorted { ($0.source, $0.title) < ($1.source, $1.title) }
    }

    struct EventCandidate: Identifiable, Hashable {
        var id: String          // eventIdentifier + fecha de inicio (eventos recurrentes)
        var title: String
        var start: Date
        var end: Date
        var calendarTitle: String
        var colorHex: String
        var alreadyImported: Bool
    }

    func events(on day: Date, calendarIDs: Set<String>, context: ModelContext) -> [EventCandidate] {
        guard hasReadAccess else { return [] }
        let (start, end) = DayDataService.dayRange(day)
        let cals = store.calendars(for: .event).filter { calendarIDs.isEmpty || calendarIDs.contains($0.calendarIdentifier) }
        guard !cals.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: cals)
        let existing = Set(DayDataService.blocks(on: day, context: context).compactMap(\.externalEventID))
        return store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .map { event in
                let key = Self.externalKey(for: event)
                return EventCandidate(id: key, title: event.title ?? "Evento", start: event.startDate,
                                      end: event.endDate, calendarTitle: event.calendar.title,
                                      colorHex: Self.hex(from: event.calendar.cgColor),
                                      alreadyImported: existing.contains(key))
            }
            .sorted { $0.start < $1.start }
    }

    /// Crea bloques locales a partir de eventos. No toca el calendario de origen.
    @discardableResult
    func importEvents(_ events: [EventCandidate], kind: BlockKind, category: BlockCategory, context: ModelContext) -> Int {
        var created = 0
        for event in events where !event.alreadyImported {
            let block = WorkBlock(title: event.title, start: event.start, end: event.end, kind: kind,
                                  category: category, colorHex: event.colorHex)
            block.externalEventID = event.id
            block.notes = "Importado de \(event.calendarTitle)"
            context.insert(block)
            created += 1
        }
        try? context.save()
        return created
    }

    private static func externalKey(for event: EKEvent) -> String {
        "\(event.eventIdentifier ?? event.calendarItemIdentifier)@\(Int(event.startDate.timeIntervalSince1970))"
    }

    private static func hex(from cgColor: CGColor?) -> String {
        guard let comps = cgColor?.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)?.components,
              comps.count >= 3 else { return "4C8DFF" }
        return String(format: "%02X%02X%02X", Int(comps[0] * 255), Int(comps[1] * 255), Int(comps[2] * 255))
    }
}
