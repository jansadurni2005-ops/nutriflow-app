import SwiftUI
import SwiftData
import Charts

struct AnalyticsView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var context

    enum Period: String, CaseIterable { case day = "Día", week = "Semana", month = "Mes" }

    @State private var period: Period = .week
    @State private var anchor = Calendar.current.startOfDay(for: Date())
    @State private var stats: [DayStats] = []
    @State private var previous: [DayStats] = []
    @State private var gamification: GamificationEngine.Summary?
    @State private var showPicker = false
    @State private var loading = true

    private var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 2
        return cal
    }

    private var range: (start: Date, days: Int) {
        switch period {
        case .day:
            return (anchor, 1)
        case .week:
            let start = calendar.dateInterval(of: .weekOfYear, for: anchor)?.start ?? anchor
            return (start, 7)
        case .month:
            let interval = calendar.dateInterval(of: .month, for: anchor)
            let start = interval?.start ?? anchor
            let days = calendar.range(of: .day, in: .month, for: anchor)?.count ?? 30
            return (start, days)
        }
    }

    private var rangeTitle: String {
        switch period {
        case .day: return anchor.formatted(.dateTime.weekday(.wide).day().month(.wide))
        case .week:
            let r = range
            let end = calendar.date(byAdding: .day, value: 6, to: r.start) ?? r.start
            return "\(r.start.formatted(.dateTime.day().month(.abbreviated))) – \(end.formatted(.dateTime.day().month(.abbreviated)))"
        case .month: return anchor.formatted(.dateTime.month(.wide).year())
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ScreenHeader(overline: "Rendimiento", title: "Analytics") {
                    Button { showPicker = true } label: {
                        Image(systemName: "calendar").font(.system(size: 16, weight: .bold)).foregroundStyle(Palette.textPrimary)
                            .frame(width: 40, height: 40).background(Circle().fill(Palette.card))
                    }
                    .accessibilityLabel("Elegir fecha")
                }

                Picker("Periodo", selection: $period) {
                    ForEach(Period.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                HStack {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text(rangeTitle.capitalized).font(.headline).foregroundStyle(Palette.textPrimary)
                    Spacer()
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }
                        .disabled(range.start > Date())
                }
                .font(.body.weight(.bold))
                .foregroundStyle(Palette.accent)
                .padding(.horizontal, 6)

                if loading && stats.isEmpty {
                    ProgressView().tint(Palette.accent).padding(40)
                } else {
                    switch period {
                    case .day:
                        if let day = stats.first { DayAnalytics(stats: day) }
                    case .week:
                        WeekAnalytics(stats: stats, previous: previous, goals: coordinator.settings.goals)
                    case .month:
                        MonthAnalytics(stats: stats, previous: previous, goals: coordinator.settings.goals, onSelectDay: { day in
                            anchor = day
                            period = .day
                        })
                    }
                }

                if let gamification {
                    ProgressSection(summary: gamification)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 140)
        }
        .scrollIndicators(.hidden)
        .screenBackground()
        .task(id: "\(period.rawValue)-\(anchor.timeIntervalSince1970)-\(coordinator.dataVersion)") { load() }
        .sheet(isPresented: $showPicker) {
            VStack(spacing: 16) {
                Text("CONSULTAR UN DÍA").overlineStyle(Palette.accent)
                DatePicker("Fecha", selection: Binding(get: { anchor }, set: { anchor = calendar.startOfDay(for: $0); period = .day }),
                           in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.graphical).tint(Palette.accent)
                Button("Ver día") { showPicker = false }.buttonStyle(PrimaryButtonStyle())
            }
            .padding(20)
            .presentationDetents([.large])
            .presentationBackground(Palette.background)
        }
    }

    private func shift(_ direction: Int) {
        let component: Calendar.Component = period == .day ? .day : period == .week ? .weekOfYear : .month
        if let next = calendar.date(byAdding: component, value: direction, to: anchor) {
            withAnimation(.easeInOut(duration: 0.25)) { anchor = calendar.startOfDay(for: next) }
        }
    }

    private func load() {
        loading = true
        let settings = coordinator.settings
        let tracking = coordinator.screenTime.automaticTrackingActive
        let r = range
        stats = DayDataService.stats(from: r.start, days: r.days, context: context, settings: settings, automaticTracking: tracking)
        let previousStart: Date
        switch period {
        case .day: previousStart = calendar.date(byAdding: .day, value: -1, to: r.start) ?? r.start
        case .week: previousStart = calendar.date(byAdding: .day, value: -7, to: r.start) ?? r.start
        case .month: previousStart = calendar.date(byAdding: .month, value: -1, to: r.start) ?? r.start
        }
        let previousDays = period == .month ? (calendar.range(of: .day, in: .month, for: previousStart)?.count ?? 30) : r.days
        previous = DayDataService.stats(from: previousStart, days: previousDays, context: context, settings: settings, automaticTracking: tracking)

        // Historial para rachas/XP: últimos 180 días hasta hoy.
        let today = calendar.startOfDay(for: Date())
        let historyStart = calendar.date(byAdding: .day, value: -179, to: today) ?? today
        let history = DayDataService.stats(from: historyStart, days: 180, context: context, settings: settings, automaticTracking: tracking)
        gamification = GamificationEngine.summary(history: history, goals: settings.goals)
        loading = false
    }
}

// MARK: - Día

struct DayAnalytics: View {
    let stats: DayStats
    @Environment(\.modelContext) private var context
    @State private var blocks: [WorkBlock] = []
    @State private var distractions: [DistractionEvent] = []

    var body: some View {
        let r = stats.result
        VStack(spacing: 16) {
            if !stats.hasData {
                EmptyStateView(icon: "calendar", title: "Sin registros este día",
                               message: "No hubo bloques planificados ni sesiones. Los días vacíos no rompen tu racha.")
            } else {
                HStack(spacing: 18) {
                    RingGauge(value: r.score, lineWidth: 12, tint: Palette.scoreColor(r.score), dashed: r.confidence == .estimated) {
                        Text(TimeFormat.percent(r.score)).font(.metric(30, weight: .heavy)).foregroundStyle(Palette.textPrimary)
                    }
                    .frame(width: 120, height: 120)
                    VStack(alignment: .leading, spacing: 8) {
                        ConfidenceBadge(confidence: r.confidence)
                        ForEach(r.components) { c in
                            HStack {
                                Text(c.title).font(.caption).foregroundStyle(Palette.textSecondary).lineLimit(1)
                                Spacer()
                                Text(TimeFormat.percent(c.value)).font(.caption.weight(.bold).monospacedDigit()).foregroundStyle(Palette.textPrimary)
                            }
                        }
                    }
                }
                .card()

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    MetricTile(title: "Planificadas", value: TimeFormat.hours(r.plannedSeconds), icon: "calendar", tint: Palette.info)
                    MetricTile(title: "Efectivas", value: TimeFormat.hours(r.effectiveSeconds), icon: "bolt.fill", tint: Palette.accent)
                    MetricTile(title: "Distracciones", value: TimeFormat.duration(r.distractionSeconds), icon: "exclamationmark.triangle", tint: Palette.danger,
                               footnote: "\(stats.distractionCount) registros · \(stats.blockedAttempts) intentos bloqueados")
                    MetricTile(title: "Bloques", value: "\(r.blocksCompleted)/\(r.blocksTotal)", icon: "checkmark.circle", tint: Palette.success)
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Qué hiciste")
                    ForEach(blocks) { block in
                        HStack(spacing: 10) {
                            Image(systemName: block.status.icon).foregroundStyle(block.status.color)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(block.title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.textPrimary)
                                Text("\(TimeFormat.hhmm(block.start))–\(TimeFormat.hhmm(block.end))\(block.delaySeconds.map { $0 > 60 ? " · retraso \(TimeFormat.duration($0))" : "" } ?? "")")
                                    .font(.caption).foregroundStyle(Palette.textSecondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(TimeFormat.duration(ScoringEngine.effectiveWorked(for: BlockFacts(kind: block.kind, start: block.start, end: block.end, status: block.status, workedSeconds: block.workedSeconds))))
                                    .font(.metric(15)).foregroundStyle(Palette.textPrimary)
                                if block.workedIsManual { Text("manual").font(.caption2).foregroundStyle(Palette.textTertiary) }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .card()

                if !distractions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Distracciones")
                        ForEach(distractions) { d in
                            HStack {
                                Image(systemName: d.source == .shieldAttempt ? "lock.shield" : d.reason.icon)
                                    .foregroundStyle(d.isAuthorized ? Palette.info : Palette.danger)
                                Text(TimeFormat.hhmm(d.date)).font(.caption.monospacedDigit()).foregroundStyle(Palette.textSecondary)
                                Text(d.source == .manual ? d.reason.label : d.source.label + (d.isAuthorized ? " (autorizado)" : ""))
                                    .font(.subheadline).foregroundStyle(Palette.textPrimary)
                                Spacer()
                                if d.durationSeconds > 0 {
                                    Text(TimeFormat.duration(d.durationSeconds)).font(.caption.weight(.bold)).foregroundStyle(Palette.textSecondary)
                                }
                            }
                        }
                    }
                    .card()
                }
            }
        }
        .task(id: stats) {
            blocks = DayDataService.blocks(on: stats.day, context: context)
            let (start, end) = DayDataService.dayRange(stats.day)
            distractions = DayDataService.distractions(from: start, to: end, context: context)
        }
    }
}

// MARK: - Semana

struct WeekAnalytics: View {
    let stats: [DayStats]
    let previous: [DayStats]
    let goals: Goals

    private struct BarPoint: Identifiable {
        var id: String { "\(day.timeIntervalSince1970)-\(series)" }
        var day: Date
        var series: String
        var hours: Double
    }

    var body: some View {
        let effective = stats.reduce(0) { $0 + $1.result.effectiveSeconds }
        let prevEffective = previous.reduce(0) { $0 + $1.result.effectiveSeconds }
        let scored = stats.compactMap(\.result.score)
        let prevScored = previous.compactMap(\.result.score)
        let avg = scored.isEmpty ? nil : scored.reduce(0, +) / Double(scored.count)
        let prevAvg = prevScored.isEmpty ? nil : prevScored.reduce(0, +) / Double(prevScored.count)
        let withScore = stats.filter { $0.result.score != nil }
        let best = withScore.max { ($0.result.score ?? 0) < ($1.result.score ?? 0) }
        let worst = withScore.min { ($0.result.score ?? 0) < ($1.result.score ?? 0) }
        let points = stats.flatMap { s in
            [BarPoint(day: s.day, series: "Planificadas", hours: s.result.plannedSeconds / 3600),
             BarPoint(day: s.day, series: "Efectivas", hours: s.result.effectiveSeconds / 3600)]
        }

        VStack(spacing: 16) {
            HStack(spacing: 10) {
                MetricTile(title: "Horas efectivas", value: TimeFormat.hours(effective), icon: "bolt.fill", tint: Palette.accent,
                           footnote: delta(effective / 3600, prevEffective / 3600, unit: " h"))
                MetricTile(title: "Efectividad media", value: TimeFormat.percent(avg), icon: "scope", tint: Palette.success,
                           footnote: avg.flatMap { a in prevAvg.map { delta(a * 100, $0 * 100, unit: " pts") } } ?? "sin comparativa")
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("HORAS POR DÍA").overlineStyle()
                    Spacer()
                    Text("Objetivo \(Int(goals.weeklyEffectiveHours)) h/sem").font(.caption).foregroundStyle(Palette.textTertiary)
                }
                Chart(points) { p in
                    BarMark(x: .value("Día", p.day, unit: .day), y: .value("Horas", p.hours))
                        .foregroundStyle(by: .value("Serie", p.series))
                        .position(by: .value("Serie", p.series))
                        .cornerRadius(5)
                }
                .chartForegroundStyleScale(["Planificadas": Color.white.opacity(0.18), "Efectivas": Palette.accent])
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.narrow)).foregroundStyle(Palette.textSecondary)
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine().foregroundStyle(Palette.stroke)
                        AxisValueLabel().foregroundStyle(Palette.textTertiary)
                    }
                }
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: 200)
                ProgressBar(value: effective / 3600 / max(1, goals.weeklyEffectiveHours))
                Text("\(TimeFormat.hours(effective)) de \(Int(goals.weeklyEffectiveHours)) h objetivo")
                    .font(.caption).foregroundStyle(Palette.textSecondary)
            }
            .card()

            VStack(alignment: .leading, spacing: 12) {
                Text("EFECTIVIDAD DIARIA").overlineStyle()
                Chart {
                    ForEach(stats.filter { $0.result.score != nil }) { s in
                        LineMark(x: .value("Día", s.day, unit: .day), y: .value("Efectividad", (s.result.score ?? 0) * 100))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(Palette.accent)
                        PointMark(x: .value("Día", s.day, unit: .day), y: .value("Efectividad", (s.result.score ?? 0) * 100))
                            .foregroundStyle(s.result.confidence == .complete ? Palette.accent : Palette.warning)
                    }
                    RuleMark(y: .value("Objetivo", goals.targetEffectiveness * 100))
                        .foregroundStyle(Palette.textTertiary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                .chartYScale(domain: 0...100)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.narrow)).foregroundStyle(Palette.textSecondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(values: [0, 50, 100]) { _ in
                        AxisGridLine().foregroundStyle(Palette.stroke)
                        AxisValueLabel().foregroundStyle(Palette.textTertiary)
                    }
                }
                .frame(height: 160)
                if scored.isEmpty {
                    Text("Sin días con datos esta semana.").font(.caption).foregroundStyle(Palette.textTertiary)
                }
            }
            .card()

            HStack(spacing: 10) {
                MetricTile(title: "Día más productivo",
                           value: best.map { $0.day.formatted(.dateTime.weekday(.abbreviated)).capitalized } ?? "—",
                           icon: "arrow.up.right", tint: Palette.success,
                           footnote: best.flatMap(\.result.score).map { TimeFormat.percent($0) })
                MetricTile(title: "Día menos productivo",
                           value: worst.map { $0.day.formatted(.dateTime.weekday(.abbreviated)).capitalized } ?? "—",
                           icon: "arrow.down.right", tint: Palette.danger,
                           footnote: worst.flatMap(\.result.score).map { TimeFormat.percent($0) })
            }

            let distraction = stats.reduce(0) { $0 + $1.result.distractionSeconds }
            let prevDistraction = previous.reduce(0) { $0 + $1.result.distractionSeconds }
            let planned = stats.reduce(0) { $0 + $1.result.plannedSeconds }
            HStack(spacing: 10) {
                MetricTile(title: "Distracciones", value: TimeFormat.duration(distraction), icon: "exclamationmark.triangle", tint: Palette.danger,
                           footnote: delta(distraction / 60, prevDistraction / 60, unit: " min", lowerIsBetter: true))
                MetricTile(title: "Cumplimiento plan", value: planned > 0 ? TimeFormat.percent(min(1, effective / planned)) : "—",
                           icon: "calendar.badge.checkmark", tint: Palette.info,
                           footnote: "objetivo \(TimeFormat.percent(goals.weeklyPlanAdherence))")
            }
        }
    }

    private func delta(_ current: Double, _ previous: Double, unit: String, lowerIsBetter: Bool = false) -> String {
        guard previous > 0 || current > 0 else { return "sin datos previos" }
        let diff = current - previous
        let sign = diff >= 0 ? "+" : "−"
        let value = abs(diff).formatted(.number.precision(.fractionLength(abs(diff) < 10 ? 1 : 0)))
        return "\(sign)\(value)\(unit) vs semana anterior"
    }
}

// MARK: - Mes

struct MonthAnalytics: View {
    let stats: [DayStats]
    let previous: [DayStats]
    let goals: Goals
    var onSelectDay: (Date) -> Void

    private struct CategorySlice: Identifiable {
        var id: String { category.rawValue }
        var category: BlockCategory
        var hours: Double
    }

    var body: some View {
        let total = stats.reduce(0) { $0 + $1.result.effectiveSeconds }
        let prevTotal = previous.reduce(0) { $0 + $1.result.effectiveSeconds }
        let daysWithData = stats.filter(\.hasData)
        let goalDays = daysWithData.filter { ($0.result.score ?? 0) >= goals.targetEffectiveness }.count
        let slices = categorySlices()

        VStack(spacing: 16) {
            HStack(spacing: 10) {
                MetricTile(title: "Horas acumuladas", value: TimeFormat.hours(total), icon: "hourglass", tint: Palette.accent,
                           footnote: prevTotal > 0 ? "mes anterior \(TimeFormat.hours(prevTotal))" : nil)
                MetricTile(title: "Días en objetivo", value: "\(goalDays)/\(daysWithData.count)", icon: "target", tint: Palette.success,
                           footnote: "≥ \(TimeFormat.percent(goals.targetEffectiveness)) efectividad")
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("MAPA DE CALOR").overlineStyle()
                HeatmapCalendar(stats: stats, onSelect: onSelectDay)
                HStack(spacing: 6) {
                    Text("Menos").font(.caption2).foregroundStyle(Palette.textTertiary)
                    ForEach([0.0, 0.35, 0.6, 0.8, 1.0], id: \.self) { v in
                        RoundedRectangle(cornerRadius: 3).fill(HeatmapCalendar.color(for: v)).frame(width: 14, height: 14)
                    }
                    Text("Más").font(.caption2).foregroundStyle(Palette.textTertiary)
                    Spacer()
                    Text("Toca un día para verlo").font(.caption2).foregroundStyle(Palette.textTertiary)
                }
            }
            .card()

            VStack(alignment: .leading, spacing: 12) {
                Text("EVOLUCIÓN DE LA CONCENTRACIÓN").overlineStyle()
                let concentration = stats.compactMap { s -> (Date, Double)? in
                    guard let v = s.result.components.first(where: { $0.kind == .concentration })?.value else { return nil }
                    return (s.day, v * 100)
                }
                if concentration.isEmpty {
                    Text("Sin sesiones registradas este mes.").font(.caption).foregroundStyle(Palette.textTertiary)
                } else {
                    Chart(concentration, id: \.0) { point in
                        AreaMark(x: .value("Día", point.0, unit: .day), y: .value("Concentración", point.1))
                            .foregroundStyle(LinearGradient(colors: [Palette.accent.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.catmullRom)
                        LineMark(x: .value("Día", point.0, unit: .day), y: .value("Concentración", point.1))
                            .foregroundStyle(Palette.accent)
                            .interpolationMethod(.catmullRom)
                    }
                    .chartYScale(domain: 0...100)
                    .chartYAxis {
                        AxisMarks(values: [0, 50, 100]) { _ in
                            AxisGridLine().foregroundStyle(Palette.stroke)
                            AxisValueLabel().foregroundStyle(Palette.textTertiary)
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                            AxisValueLabel(format: .dateTime.day()).foregroundStyle(Palette.textSecondary)
                        }
                    }
                    .frame(height: 160)
                }
            }
            .card()

            VStack(alignment: .leading, spacing: 12) {
                Text("HORAS POR CATEGORÍA").overlineStyle()
                if slices.isEmpty {
                    Text("Aún no hay horas registradas.").font(.caption).foregroundStyle(Palette.textTertiary)
                } else {
                    HStack(spacing: 16) {
                        Chart(slices) { slice in
                            SectorMark(angle: .value("Horas", slice.hours), innerRadius: .ratio(0.62), angularInset: 2)
                                .foregroundStyle(Self.color(for: slice.category))
                                .cornerRadius(4)
                        }
                        .frame(width: 130, height: 130)
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(slices) { slice in
                                HStack(spacing: 6) {
                                    Circle().fill(Self.color(for: slice.category)).frame(width: 8, height: 8)
                                    Text(slice.category.label).font(.caption).foregroundStyle(Palette.textSecondary)
                                    Spacer()
                                    Text(TimeFormat.hours(slice.hours * 3600)).font(.caption.weight(.bold).monospacedDigit()).foregroundStyle(Palette.textPrimary)
                                }
                            }
                        }
                    }
                }
            }
            .card()

            trendCard
        }
    }

    private func categorySlices() -> [CategorySlice] {
        var categories: [BlockCategory: Double] = [:]
        for s in stats {
            for (key, value) in s.categorySeconds { categories[key, default: 0] += value }
        }
        return categories.filter { $0.value > 60 }
            .map { CategorySlice(category: $0.key, hours: $0.value / 3600) }
            .sorted { $0.hours > $1.hours }
    }

    private var trendCard: some View {
        // Tendencia: media de efectividad de la primera vs. la segunda mitad del mes.
        let scored = stats.filter { $0.result.score != nil }
        let half = scored.count / 2
        let first = scored.prefix(half).compactMap(\.result.score)
        let second = scored.suffix(scored.count - half).compactMap(\.result.score)
        let a = first.isEmpty ? nil : first.reduce(0, +) / Double(first.count)
        let b = second.isEmpty ? nil : second.reduce(0, +) / Double(second.count)
        let text: String
        let icon: String
        if let a, let b, scored.count >= 4 {
            let diff = (b - a) * 100
            if diff > 2 { text = "Tendencia al alza: +\(Int(diff.rounded())) puntos en la segunda mitad del mes."; icon = "arrow.up.forward.circle.fill" }
            else if diff < -2 { text = "Tendencia a la baja: \(Int(diff.rounded())) puntos en la segunda mitad del mes."; icon = "arrow.down.forward.circle.fill" }
            else { text = "Rendimiento estable a lo largo del mes."; icon = "equal.circle.fill" }
        } else {
            text = "Se necesitan al menos 4 días con datos para calcular la tendencia."; icon = "chart.line.uptrend.xyaxis"
        }
        return HStack(spacing: 12) {
            Image(systemName: icon).font(.title2).foregroundStyle(Palette.accent)
            Text(text).font(.subheadline).foregroundStyle(Palette.textSecondary)
            Spacer()
        }
        .card()
    }

    static func color(for category: BlockCategory) -> Color {
        switch category {
        case .planning: return Color(hex: "8E8E93")
        case .clients: return Color(hex: "35D07F")
        case .content: return Color(hex: "BF5AF2")
        case .communication: return Color(hex: "4C8DFF")
        case .business: return Palette.accent
        case .learning: return Color(hex: "FFD60A")
        case .personal: return Color(hex: "30D5C8")
        case .other: return Color(hex: "5E5E5E")
        }
    }
}

/// Calendario mensual coloreado por efectividad.
struct HeatmapCalendar: View {
    let stats: [DayStats]
    var onSelect: (Date) -> Void

    static func color(for value: Double?) -> Color {
        guard let value else { return Color.white.opacity(0.04) }
        if value <= 0 { return Color.white.opacity(0.08) }
        return Palette.accent.opacity(0.15 + 0.85 * min(1, value))
    }

    var body: some View {
        let cal = Calendar.current
        let leading = ((cal.component(.weekday, from: stats.first?.day ?? Date()) + 5) % 7)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(["L", "M", "X", "J", "V", "S", "D"], id: \.self) {
                    Text($0).font(.caption2.weight(.bold)).foregroundStyle(Palette.textTertiary).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(0..<leading, id: \.self) { _ in Color.clear.frame(height: 34) }
                ForEach(stats) { s in
                    let future = s.day > Date()
                    Button { if !future { onSelect(s.day) } } label: {
                        Text(s.day.formatted(.dateTime.day()))
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(future ? Palette.textTertiary : Palette.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Self.color(for: s.hasData ? (s.result.score ?? 0) : nil)))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(cal.isDateInToday(s.day) ? Palette.accent : .clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .disabled(future)
                }
            }
        }
    }
}

// MARK: - Progreso (gamificación)

struct ProgressSection: View {
    let summary: GamificationEngine.Summary
    @State private var showAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Progreso", actionTitle: showAll ? "Ver menos" : "Ver logros") { withAnimation { showAll.toggle() } }

            HStack(spacing: 16) {
                ZStack {
                    RingGauge(value: summary.levelProgress, lineWidth: 6) {
                        VStack(spacing: 0) {
                            Text("\(summary.level)").font(.metric(26, weight: .heavy)).foregroundStyle(Palette.textPrimary)
                            Text("NIVEL").font(.system(size: 8, weight: .bold).width(.expanded)).foregroundStyle(Palette.textTertiary)
                        }
                    }
                }
                .frame(width: 74, height: 74)
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.levelTitle).font(.title3.weight(.bold)).foregroundStyle(Palette.textPrimary)
                    Text("\(summary.totalXP) XP · \(summary.xpForNextLevel - summary.xpIntoLevel) para el nivel \(summary.level + 1)")
                        .font(.caption).foregroundStyle(Palette.textSecondary)
                    Text("+\(summary.todayXP) XP hoy").font(.caption.weight(.bold)).foregroundStyle(Palette.accent)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                MetricTile(title: "Racha actual", value: "\(summary.currentStreak) días", icon: "flame.fill", tint: Palette.accent)
                MetricTile(title: "Mejor racha", value: "\(summary.bestStreak) días", icon: "trophy.fill", tint: Palette.warning)
            }

            let list = showAll ? summary.achievements : Array(summary.achievements.sorted { $0.progress > $1.progress }.prefix(3))
            VStack(spacing: 10) {
                ForEach(list) { a in
                    HStack(spacing: 12) {
                        Image(systemName: a.icon)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(a.unlocked ? .black : Palette.textTertiary)
                            .frame(width: 40, height: 40)
                            .background(RoundedRectangle(cornerRadius: 12).fill(a.unlocked ? Palette.accent : Palette.cardElevated))
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(a.title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.textPrimary)
                                Spacer()
                                Text(a.progressLabel).font(.caption2.monospacedDigit()).foregroundStyle(Palette.textTertiary)
                            }
                            Text(a.detail).font(.caption).foregroundStyle(Palette.textSecondary).lineLimit(2)
                            ProgressBar(value: a.progress, tint: a.unlocked ? Palette.success : Palette.accent, height: 4)
                        }
                    }
                }
            }
        }
        .card()
    }
}
