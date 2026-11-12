import SwiftUI
import SwiftData

/// Importar eventos (Calendario de iOS / Google Calendar añadido en Ajustes) como bloques.
struct CalendarImportView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State var day: Date
    @State private var selectedCalendars: Set<String> = []
    @State private var selectedEvents: Set<String> = []
    @State private var kind: BlockKind = .meeting
    @State private var category: BlockCategory = .clients
    @State private var refreshToken = 0

    private var service: CalendarImportService { coordinator.calendarService }

    var body: some View {
        NavigationStack {
            Group {
                if !service.hasReadAccess {
                    accessView
                } else {
                    importList
                }
            }
            .background(Palette.background)
            .navigationTitle("Importar calendario")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } } }
        }
    }

    private var accessView: some View {
        VStack(spacing: 18) {
            EmptyStateView(icon: "calendar.badge.plus", title: "Acceso de solo lectura",
                           message: "FOCUS OS leerá tus eventos para convertirlos en bloques. Nunca modificará ni creará eventos en tu calendario.\n\nPara Google Calendar: Ajustes de iOS › Calendario › Cuentas › Añadir cuenta › Google.")
            if service.status == .denied || service.status == .restricted {
                Text("El acceso está denegado. Actívalo en Ajustes › FOCUS OS › Calendarios.")
                    .font(.footnote).foregroundStyle(Palette.warning).multilineTextAlignment(.center)
                Button("Abrir Ajustes") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(SecondaryButtonStyle())
            } else {
                Button("Permitir acceso a calendarios") {
                    Task { await service.requestAccess(); refreshToken += 1 }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            if let error = service.lastError {
                Text(error).font(.caption).foregroundStyle(Palette.danger)
            }
            Spacer()
        }
        .padding(16)
    }

    private var importList: some View {
        let calendars = service.calendars()
        let events = service.events(on: day, calendarIDs: selectedCalendars, context: context)
        let importable = events.filter { selectedEvents.contains($0.id) && !$0.alreadyImported }

        return Form {
            Section("Día") {
                DatePicker("Fecha", selection: $day, displayedComponents: .date)
            }
            .listRowBackground(Palette.card)

            Section("Calendarios") {
                ForEach(calendars) { cal in
                    Button {
                        if selectedCalendars.contains(cal.id) { selectedCalendars.remove(cal.id) } else { selectedCalendars.insert(cal.id) }
                    } label: {
                        HStack {
                            Circle().fill(Color(hex: cal.colorHex)).frame(width: 10, height: 10)
                            VStack(alignment: .leading) {
                                Text(cal.title).foregroundStyle(Palette.textPrimary)
                                Text(cal.source).font(.caption).foregroundStyle(Palette.textTertiary)
                            }
                            Spacer()
                            Image(systemName: selectedCalendars.isEmpty || selectedCalendars.contains(cal.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(Palette.accent)
                        }
                    }
                }
                Text(selectedCalendars.isEmpty ? "Mostrando todos los calendarios." : "\(selectedCalendars.count) seleccionados.")
                    .font(.caption).foregroundStyle(Palette.textTertiary)
            }
            .listRowBackground(Palette.card)

            Section("Eventos") {
                if events.isEmpty {
                    Text("No hay eventos con hora este día.").foregroundStyle(Palette.textTertiary)
                }
                ForEach(events) { event in
                    Button {
                        guard !event.alreadyImported else { return }
                        if selectedEvents.contains(event.id) { selectedEvents.remove(event.id) } else { selectedEvents.insert(event.id) }
                    } label: {
                        HStack {
                            Image(systemName: event.alreadyImported ? "checkmark.seal.fill"
                                  : selectedEvents.contains(event.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(event.alreadyImported ? Palette.success : Palette.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.title).foregroundStyle(Palette.textPrimary)
                                Text("\(TimeFormat.hhmm(event.start))–\(TimeFormat.hhmm(event.end)) · \(event.calendarTitle)")
                                    .font(.caption).foregroundStyle(Palette.textSecondary)
                            }
                            Spacer()
                            if event.alreadyImported {
                                Text("Ya importado").font(.caption2).foregroundStyle(Palette.textTertiary)
                            }
                        }
                    }
                }
            }
            .listRowBackground(Palette.card)

            Section("Convertir en") {
                Picker("Tipo", selection: $kind) {
                    ForEach(BlockKind.allCases) { Text($0.label).tag($0) }
                }
                Picker("Categoría", selection: $category) {
                    ForEach(BlockCategory.allCases) { Text($0.label).tag($0) }
                }
            }
            .listRowBackground(Palette.card)

            Section {
                Button("Importar \(importable.count) evento\(importable.count == 1 ? "" : "s")") {
                    let n = service.importEvents(importable, kind: kind, category: category, context: context)
                    coordinator.didChangeData()
                    coordinator.showToast("\(n) bloques creados desde tu calendario.", style: .success)
                    dismiss()
                }
                .disabled(importable.isEmpty)
                .fontWeight(.bold)
            } footer: {
                Text("Los eventos ya importados no se duplican. Tu calendario no se modifica.")
            }
            .listRowBackground(Palette.card)
        }
        .scrollContentBackground(.hidden)
        .id(refreshToken)
    }
}
