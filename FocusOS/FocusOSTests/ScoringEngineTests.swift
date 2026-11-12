import XCTest
@testable import FocusOS

final class ScoringEngineTests: XCTestCase {

    private let base = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 2, hour: 0))!

    private func at(_ hour: Double) -> Date { base.addingTimeInterval(hour * 3600) }

    // Ejemplo del enunciado: 6 h planificadas, 5 h 15 min efectivas, 45 min de distracciones.
    func testExampleDayReflectsDistractions() {
        let blocks = [
            BlockFacts(kind: .deepWork, start: at(7), end: at(10), status: .completed, actualStart: at(7),
                       workedSeconds: 2.75 * 3600, distractionSeconds: 15 * 60, hadSession: true),
            BlockFacts(kind: .work, start: at(10), end: at(13), status: .completed, actualStart: at(10),
                       workedSeconds: 2.5 * 3600, distractionSeconds: 30 * 60, hadSession: true)
        ]
        let r = ScoringEngine.evaluate(ScoreInput(blocks: blocks, now: at(14)))
        XCTAssertEqual(r.plannedSeconds, 6 * 3600, accuracy: 1)
        XCTAssertEqual(r.effectiveSeconds, 5.25 * 3600, accuracy: 1)
        XCTAssertEqual(r.distractionSeconds, 45 * 60, accuracy: 1)
        let concentration = r.components.first { $0.kind == .concentration }?.value
        XCTAssertEqual(concentration ?? 0, 5.25 / 6.0, accuracy: 0.001)
        let adherence = r.components.first { $0.kind == .adherence }?.value
        XCTAssertEqual(adherence ?? 0, 5.25 / 6.0, accuracy: 0.001)
        // 0.4*0.875 + 0.25*0.875 + 0.25*1 + 0.1*1 = 0.91875
        XCTAssertEqual(r.score ?? 0, 0.91875, accuracy: 0.0001)
        XCTAssertEqual(r.confidence, .complete)
    }

    func testNoDataMeansNoScore() {
        let r = ScoringEngine.evaluate(ScoreInput(blocks: [], now: at(10)))
        XCTAssertNil(r.score)
        XCTAssertEqual(r.confidence, .insufficient)
    }

    func testFutureBlocksDoNotCountYet() {
        let blocks = [BlockFacts(kind: .deepWork, start: at(15), end: at(17), status: .pending)]
        let r = ScoringEngine.evaluate(ScoreInput(blocks: blocks, now: at(9)))
        XCTAssertNil(r.score)
        XCTAssertEqual(r.plannedSeconds, 2 * 3600, accuracy: 1)
        XCTAssertEqual(r.plannedElapsedSeconds, 0, accuracy: 1)
    }

    func testBreaksAreNotPenalized() {
        let work = BlockFacts(kind: .deepWork, start: at(9), end: at(10), status: .completed, actualStart: at(9),
                              workedSeconds: 3600, hadSession: true)
        let rest = BlockFacts(kind: .breakTime, start: at(10), end: at(10.5), status: .completed)
        let withBreak = ScoringEngine.evaluate(ScoreInput(blocks: [work, rest], now: at(11)))
        let without = ScoringEngine.evaluate(ScoreInput(blocks: [work], now: at(11)))
        XCTAssertEqual(withBreak.score, without.score)
        XCTAssertEqual(withBreak.plannedSeconds, 3600, accuracy: 1)
    }

    func testCompletedMeetingCountsFullTimeWithoutPenalty() {
        let meeting = BlockFacts(kind: .meeting, start: at(9), end: at(10), status: .completed)
        let r = ScoringEngine.evaluate(ScoreInput(blocks: [meeting], now: at(11)))
        XCTAssertEqual(r.effectiveSeconds, 3600, accuracy: 1)
        XCTAssertEqual(r.components.first { $0.kind == .adherence }?.value ?? 0, 1, accuracy: 0.001)
        XCTAssertNil(r.components.first { $0.kind == .concentration }?.value, "Las reuniones no miden concentración")
    }

    func testMissingComponentsMakeScoreEstimated() {
        // Un bloque en curso sin vencer: no hay datos de tareas completadas.
        let block = BlockFacts(kind: .deepWork, start: at(9), end: at(11), status: .inProgress, actualStart: at(9),
                               workedSeconds: 3000, hadSession: true)
        let r = ScoringEngine.evaluate(ScoreInput(blocks: [block], now: at(10)))
        XCTAssertNotNil(r.score)
        XCTAssertEqual(r.confidence, .estimated)
        XCTAssertNil(r.components.first { $0.kind == .completion }?.value)
    }

    func testPunctualityCurve() {
        XCTAssertEqual(ScoringEngine.punctuality(delay: 60, grace: 120, zero: 1800), 1)
        XCTAssertEqual(ScoringEngine.punctuality(delay: 1800, grace: 120, zero: 1800), 0)
        XCTAssertEqual(ScoringEngine.punctuality(delay: 960, grace: 120, zero: 1800), 0.5, accuracy: 0.001)
    }

    func testDistractionLowersScore() {
        let clean = BlockFacts(kind: .deepWork, start: at(9), end: at(11), status: .completed, actualStart: at(9),
                               workedSeconds: 7200, hadSession: true)
        var distracted = clean
        distracted.workedSeconds = 7200 - 1200
        distracted.distractionSeconds = 1200
        let a = ScoringEngine.evaluate(ScoreInput(blocks: [clean], now: at(12)))
        let b = ScoringEngine.evaluate(ScoreInput(blocks: [distracted], now: at(12)))
        XCTAssertGreaterThan(a.score ?? 0, b.score ?? 0)
    }

    func testCustomWeightsAreNormalized() {
        let block = BlockFacts(kind: .work, start: at(9), end: at(10), status: .completed, actualStart: at(9.5),
                               workedSeconds: 1800, hadSession: true)
        var weights = ScoreWeights()
        weights.concentration = 0; weights.adherence = 0; weights.completion = 0; weights.punctuality = 2
        let r = ScoringEngine.evaluate(ScoreInput(blocks: [block], now: at(11), weights: weights))
        // Solo cuenta puntualidad: retraso 30 min → 0 %.
        XCTAssertEqual(r.score ?? -1, 0, accuracy: 0.0001)
    }
}

final class GamificationTests: XCTestCase {

    private func day(_ offset: Int, score: Double?, effective: Double = 3600) -> DayStats {
        let date = Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: Date()))!
        var result = ScoreResult.empty
        result.score = score
        result.confidence = score == nil ? .insufficient : .complete
        result.effectiveSeconds = score == nil ? 0 : effective
        result.blocksTotal = score == nil ? 0 : 2
        return DayStats(day: date, result: result, categorySeconds: [:], distractionCount: 0, blockedAttempts: 0)
    }

    func testEmptyDaysDoNotBreakStreak() {
        let goals = Goals()
        let history = [day(-4, score: 0.95), day(-3, score: nil), day(-2, score: 0.92), day(-1, score: 0.91), day(0, score: nil)]
        let streak = GamificationEngine.streaks(history, goals: goals)
        XCTAssertEqual(streak.current, 3)
        XCTAssertEqual(streak.best, 3)
    }

    func testBadDayBreaksStreak() {
        let goals = Goals()
        let history = [day(-3, score: 0.95), day(-2, score: 0.5), day(-1, score: 0.93), day(0, score: 0.4)]
        let streak = GamificationEngine.streaks(history, goals: goals)
        XCTAssertEqual(streak.current, 1, "Hoy aún no rompe la racha")
        XCTAssertEqual(streak.best, 1)
    }

    func testLevelsGrow() {
        XCTAssertEqual(GamificationEngine.xpRequired(forLevel: 1), 0)
        XCTAssertLessThan(GamificationEngine.xpRequired(forLevel: 2), GamificationEngine.xpRequired(forLevel: 3))
    }
}
