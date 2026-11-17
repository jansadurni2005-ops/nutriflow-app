import WidgetKit
import SwiftUI

// MARK: - Timeline

struct FocusEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?

    /// Lo que se está haciendo ahora: sesión activa o bloque programado.
    var current: (title: String, kind: String, end: Date, colorHex: String, paused: Bool, pausedRemaining: TimeInterval)? {
        guard let snapshot else { return nil }
        if let title = snapshot.activeSessionTitle, let end = snapshot.activeSessionEnd {
            let block = snapshot.currentBlock(at: date)
            return (title, block?.kindLabel ?? "SESIÓN", end, block?.colorHex ?? "FF6500",
                    snapshot.activeSessionPaused, snapshot.activeSessionPausedRemaining)
        }
        if let block = snapshot.currentBlock(at: date) {
            return (block.title, block.kindLabel, block.end, block.colorHex, false, 0)
        }
        return nil
    }

    var next: WidgetSnapshot.BlockInfo? { snapshot?.nextBlock(after: date) }
}

struct FocusProvider: TimelineProvider {
    func placeholder(in context: Context) -> FocusEntry {
        FocusEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (FocusEntry) -> Void) {
        completion(FocusEntry(date: Date(), snapshot: context.isPreview ? .sample : (WidgetSnapshot.load() ?? .sample)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FocusEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetSnapshot.load()
        // Una entrada en cada cambio de bloque durante las próximas 12 h.
        var dates: Set<Date> = [now]
        let horizon = now.addingTimeInterval(12 * 3600)
        for block in snapshot?.blocks ?? [] {
            if block.start > now && block.start < horizon { dates.insert(block.start) }
            if block.end > now && block.end < horizon { dates.insert(block.end) }
        }
        if let end = snapshot?.activeSessionEnd, end > now, end < horizon { dates.insert(end) }
        let entries = dates.sorted().prefix(40).map { FocusEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: Array(entries), policy: .after(now.addingTimeInterval(30 * 60))))
    }
}

extension WidgetSnapshot {
    static var sample: WidgetSnapshot {
        let now = Date()
        return WidgetSnapshot(
            generatedAt: now,
            blocks: [
                .init(id: UUID(), title: "Preparar planes nutricionales", kindLabel: "TRABAJO PROFUNDO",
                      start: now.addingTimeInterval(-1800), end: now.addingTimeInterval(5075), colorHex: "FF6500"),
                .init(id: UUID(), title: "Responder mensajes", kindLabel: "TRABAJO",
                      start: now.addingTimeInterval(5075), end: now.addingTimeInterval(6875), colorHex: "4C8DFF")
            ],
            effectiveness: 0.92, effectivenessIsEstimated: false,
            activeSessionTitle: nil, activeSessionEnd: nil, activeSessionPaused: false, activeSessionPausedRemaining: 0)
    }
}

// MARK: - Vistas

/// Cuenta atrás segura: si el fin ya pasó muestra tiempo extra contando hacia arriba.
struct CountdownText: View {
    let end: Date
    let now: Date
    var paused = false
    var pausedRemaining: TimeInterval = 0

    var body: some View {
        if paused {
            Text(TimeFormat.compactClock(pausedRemaining))
        } else if end > now {
            Text(timerInterval: now...end, countsDown: true)
        } else {
            Text(end, style: .timer)
        }
    }
}

struct FocusStatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FocusEntry

    var body: some View {
        switch family {
        case .systemSmall: small
        case .systemMedium: medium
        case .accessoryRectangular: rectangular
        case .accessoryCircular: circular
        case .accessoryInline: inline
        default: medium
        }
    }

    private var effectiveness: Double? { entry.snapshot?.effectiveness }

    private var ring: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.08), lineWidth: 6)
            Circle()
                .trim(from: 0, to: effectiveness ?? 0)
                .stroke(Palette.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(effectiveness.map { "\(Int(($0 * 100).rounded()))" } ?? "—")
                    .font(.system(size: 20, weight: .heavy).width(.condensed).monospacedDigit())
                    .foregroundStyle(.white)
                Text(entry.snapshot?.effectivenessIsEstimated == true ? "EST." : "%")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Palette.textTertiary)
            }
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.current?.kind ?? "FOCUS OS")
                    .font(.system(size: 9, weight: .bold).width(.expanded))
                    .foregroundStyle(Palette.accent).lineLimit(1)
                Spacer()
                ring.frame(width: 38, height: 38)
            }
            Spacer(minLength: 0)
            if let current = entry.current {
                CountdownText(end: current.end, now: entry.date, paused: current.paused, pausedRemaining: current.pausedRemaining)
                    .font(.system(size: 26, weight: .heavy).width(.condensed).monospacedDigit())
                    .foregroundStyle(.white)
                Text(current.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.textSecondary).lineLimit(2)
            } else if let next = entry.next {
                Text("Siguiente").font(.caption2).foregroundStyle(Palette.textTertiary)
                Text(next.title).font(.system(size: 14, weight: .bold)).foregroundStyle(.white).lineLimit(2)
                Text(TimeFormat.hhmm(next.start)).font(.system(size: 18, weight: .heavy).width(.condensed)).foregroundStyle(Palette.accent)
            } else {
                Text("Sin bloques").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                Text("Planifica tu jornada").font(.caption2).foregroundStyle(Palette.textTertiary)
            }
        }
    }

    private var medium: some View {
        HStack(spacing: 16) {
            VStack(spacing: 6) {
                ring.frame(width: 76, height: 76)
                Text("EFECTIVIDAD").font(.system(size: 8, weight: .bold).width(.expanded)).foregroundStyle(Palette.textTertiary)
            }
            VStack(alignment: .leading, spacing: 5) {
                if let current = entry.current {
                    Text(current.kind).font(.system(size: 9, weight: .bold).width(.expanded)).foregroundStyle(Color(hex: current.colorHex))
                    Text(current.title).font(.system(size: 15, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        CountdownText(end: current.end, now: entry.date, paused: current.paused, pausedRemaining: current.pausedRemaining)
                            .font(.system(size: 28, weight: .heavy).width(.condensed).monospacedDigit())
                            .foregroundStyle(.white)
                        Text(current.paused ? "en pausa" : "restantes").font(.caption2).foregroundStyle(Palette.textTertiary)
                    }
                } else {
                    Text("SIN BLOQUE EN CURSO").font(.system(size: 9, weight: .bold).width(.expanded)).foregroundStyle(Palette.textTertiary)
                }
                Spacer(minLength: 0)
                if let next = entry.next {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2).fill(Color(hex: next.colorHex)).frame(width: 3, height: 22)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Próxima · \(TimeFormat.hhmm(next.start))").font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                            Text(next.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.textSecondary).lineLimit(1)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let current = entry.current {
                Text(current.title).font(.headline).lineLimit(1)
                CountdownText(end: current.end, now: entry.date, paused: current.paused, pausedRemaining: current.pausedRemaining)
                    .font(.system(size: 20, weight: .bold).monospacedDigit())
                Text("Efectividad \(TimeFormat.percent(effectiveness))").font(.caption2)
            } else if let next = entry.next {
                Text("Siguiente \(TimeFormat.hhmm(next.start))").font(.caption)
                Text(next.title).font(.headline).lineLimit(2)
            } else {
                Text("FOCUS OS").font(.headline)
                Text("Efectividad \(TimeFormat.percent(effectiveness))").font(.caption)
            }
        }
    }

    private var circular: some View {
        Gauge(value: effectiveness ?? 0) {
            Text("EF")
        } currentValueLabel: {
            Text(effectiveness.map { "\(Int(($0 * 100).rounded()))" } ?? "—")
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }

    private var inline: some View {
        if let current = entry.current {
            return Text("\(current.title) · \(TimeFormat.hhmm(current.end))")
        }
        return Text("Efectividad \(TimeFormat.percent(effectiveness))")
    }
}

struct FocusStatusWidget: Widget {
    let kind = "FocusStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FocusProvider()) { entry in
            FocusStatusWidgetView(entry: entry)
                .containerBackground(for: .widget) { Palette.background }
        }
        .configurationDisplayName("FOCUS OS")
        .description("Bloque actual, tiempo restante, efectividad y próxima tarea.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}
