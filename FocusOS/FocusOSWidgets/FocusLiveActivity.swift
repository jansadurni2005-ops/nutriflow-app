import ActivityKit
import WidgetKit
import SwiftUI

/// Live Activity: temporizador en la pantalla de bloqueo y en la Dynamic Island.
struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            LockScreenFocusView(state: context.state, objective: context.attributes.objective,
                                tint: Color(hex: context.attributes.colorHex))
                .activityBackgroundTint(Palette.background)
                .activitySystemActionForegroundColor(Palette.accent)
        } dynamicIsland: { context in
            let state = context.state
            let tint = Color(hex: context.attributes.colorHex)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.kindLabel).font(.system(size: 9, weight: .bold).width(.expanded)).foregroundStyle(tint)
                        Text(state.statusLabel).font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    LiveCountdown(state: state)
                        .font(.system(size: 24, weight: .heavy).width(.condensed).monospacedDigit())
                        .foregroundStyle(state.isPaused ? Palette.warning : .white)
                        .frame(maxWidth: 110, alignment: .trailing)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(state.title).font(.headline).lineLimit(1)
                        if !context.attributes.objective.isEmpty {
                            Text(context.attributes.objective).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        if !state.isPaused && state.plannedEnd > Date() {
                            ProgressView(timerInterval: state.focusStartReference...max(state.plannedEnd, state.focusStartReference.addingTimeInterval(1)),
                                         countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                                .tint(tint)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: state.isPaused ? "pause.fill" : "scope").foregroundStyle(tint)
            } compactTrailing: {
                LiveCountdown(state: state)
                    .monospacedDigit()
                    .frame(maxWidth: 52)
                    .foregroundStyle(state.isPaused ? Palette.warning : .white)
            } minimal: {
                Image(systemName: state.isPaused ? "pause.fill" : "scope").foregroundStyle(tint)
            }
            .keylineTint(tint)
        }
    }
}

struct LiveCountdown: View {
    let state: FocusActivityAttributes.ContentState

    var body: some View {
        if state.isPaused {
            Text(TimeFormat.compactClock(state.pausedRemaining))
        } else if state.plannedEnd > Date() {
            Text(timerInterval: Date()...state.plannedEnd, countsDown: true)
        } else {
            Text(state.plannedEnd, style: .timer)
        }
    }
}

struct LockScreenFocusView: View {
    let state: FocusActivityAttributes.ContentState
    let objective: String
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "scope").foregroundStyle(Palette.accent)
                    Text(state.kindLabel).font(.system(size: 10, weight: .bold).width(.expanded)).foregroundStyle(Palette.accent)
                    if state.isPaused {
                        Text(state.statusLabel.uppercased()).font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.warning)
                    }
                }
                Text(state.title).font(.headline).foregroundStyle(.white).lineLimit(1)
                if !objective.isEmpty {
                    Text(objective).font(.caption).foregroundStyle(Palette.textSecondary).lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                LiveCountdown(state: state)
                    .font(.system(size: 34, weight: .heavy).width(.condensed).monospacedDigit())
                    .foregroundStyle(state.isPaused ? Palette.warning : .white)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 140, alignment: .trailing)
                Text(state.plannedEnd > Date() ? "restantes" : "tiempo extra").font(.caption2).foregroundStyle(Palette.textTertiary)
            }
        }
        .padding(16)
    }
}
