import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct QuoWidgets: WidgetBundle {
    var body: some Widget {
        ListenLiveActivity()
    }
}

/// Listen to Page while Quo is away: on the Lock Screen, what's being read
/// and buttons to pause and stop; in the Dynamic Island, a waveform that
/// stills when paused, opening out to the same.
struct ListenLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ListenAttributes.self) { context in
            LockScreen(context: context)
                .activityBackgroundTint(Color(white: 0.09))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Wave(paused: context.state.paused).frame(width: 34, height: 34)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        Text(progress(context)).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Controls(paused: context.state.paused).padding(.top, 4)
                }
            } compactLeading: {
                Wave(paused: context.state.paused).frame(width: 20, height: 16)
            } compactTrailing: {
                Image(systemName: context.state.paused ? "pause.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 12, weight: .semibold))
            } minimal: {
                Wave(paused: context.state.paused).frame(width: 18, height: 14)
            }
        }
    }
}

private func progress(_ context: ActivityViewContext<ListenAttributes>) -> String {
    let where_ = "\(context.attributes.site) \u{00B7} \(context.state.part) of \(max(1, context.state.parts))"
    return context.state.paused ? "Paused \u{00B7} " + where_ : where_
}

private struct LockScreen: View {
    let context: ActivityViewContext<ListenAttributes>

    var body: some View {
        HStack(spacing: 14) {
            Wave(paused: context.state.paused).frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(context.attributes.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(progress(context))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 0)
            Controls(paused: context.state.paused)
        }
        .padding(16)
    }
}

private struct Controls: View {
    let paused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Button(intent: PauseListening()) {
                Image(systemName: paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.16), in: Circle())
            }
            .buttonStyle(.plain)
            Button(intent: StopListening()) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.16), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
    }
}

/// Five bars, as a voice's level; still when paused.
private struct Wave: View {
    let paused: Bool
    private let heights: [CGFloat] = [0.45, 0.8, 1.0, 0.65, 0.35]

    var body: some View {
        GeometryReader { space in
            HStack(alignment: .center, spacing: space.size.width * 0.08) {
                ForEach(heights.indices, id: \.self) { index in
                    Capsule()
                        .frame(height: space.size.height * (paused ? 0.25 : heights[index]))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(.white)
    }
}
