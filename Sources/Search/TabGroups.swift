import SwiftUI
import AppKit

/// Unshifted heading and member frames in the layout's named coordinate space.
struct GroupDropFrame: Equatable {
    let group: UUID
    var tab: UUID? = nil
    let rect: CGRect
}

struct GroupDropTarget: Equatable {
    let group: UUID
    var member: UUID? = nil
    var after = false
}

struct GroupDropFrames: PreferenceKey {
    static var defaultValue: [UUID: GroupDropFrame] = [:]

    static func reduce(value: inout [UUID: GroupDropFrame], nextValue: () -> [UUID: GroupDropFrame]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }

    static func resolve(_ point: CGPoint, frames: [UUID: GroupDropFrame],
                        groups: [TabGroup], excluding source: UUID, vertical: Bool) -> GroupDropTarget? {
        // Model group order gives overlapping regions a deterministic priority.
        for group in groups {
            let heading = frames[group.id]?.rect
            let members = frames.values.filter { $0.group == group.id && $0.tab != nil && $0.tab != source }
                .sorted { vertical ? $0.rect.minY < $1.rect.minY : $0.rect.minX < $1.rect.minX }
            let extent = members.reduce(heading ?? .null) { $0.union($1.rect) }
            guard extent.contains(point) else { continue }
            if heading?.contains(point) == true || group.collapsed || members.isEmpty {
                return GroupDropTarget(group: group.id)
            }
            let position = vertical ? point.y : point.x
            if let next = members.first(where: { position < (vertical ? $0.rect.midY : $0.rect.midX) }) {
                return GroupDropTarget(group: group.id, member: next.tab)
            }
            return GroupDropTarget(group: group.id, member: members.last?.tab, after: true)
        }
        return nil
    }
}

/// Where each tab in no group is drawn, in the row's space, for where a tab
/// carried out of its group lands among them (#1009). Written as the rows
/// are laid out and read once, when the tab is let go: a box rather than a
/// preference, so a row that moves redraws nothing (see ColumnFrames).
final class LooseFrames {
    var rects: [UUID: CGRect] = [:]
}

/// A tab of a group let go outside every group: in front of the tab in no
/// group it lands before, or after them all.
struct LooseDrop: Equatable {
    var before: UUID? = nil
}

extension GroupDropFrames {
    /// Where a tab carried out of its group lands, or nil when it stays:
    /// let go anywhere along its own group's run, its own place included
    /// (a hand that barely moved leaves nothing), level with another
    /// group's, or off to the side of the row. `loose` is the tabs in no
    /// group, by where they are drawn.
    static func leaving(_ point: CGPoint, frames: [UUID: GroupDropFrame], loose: [UUID: CGRect],
                        groups: [TabGroup], source: UUID, vertical: Bool) -> LooseDrop? {
        guard frames[source]?.tab == source else { return nil }
        let drawn = frames.values.map(\.rect) + Array(loose.values)
        let row = drawn.reduce(CGRect.null) { $0.union($1) }
        guard !row.isNull,
              vertical ? (row.minX...row.maxX).contains(point.x) : (row.minY...row.maxY).contains(point.y)
        else { return nil }
        let position = vertical ? point.y : point.x
        for group in groups {
            let run = frames.values.filter { $0.group == group.id }.reduce(CGRect.null) { $0.union($1.rect) }
            if !run.isNull, (vertical ? run.minY...run.maxY : run.minX...run.maxX).contains(position) { return nil }
        }
        let next = loose.filter { position < (vertical ? $0.value.midY : $0.value.midX) }
            .min { vertical ? $0.value.minY < $1.value.minY : $0.value.minX < $1.value.minX }
        return LooseDrop(before: next?.key)
    }
}

/// A quiet name above the tabs it contains, in either layout. An agent's
/// group (AgentGroups.swift) wears the agent's icon and colours.
struct GroupHeading: View {
    @Environment(\.greys) private var greys
    @Environment(\.tabShortcutNumbers) private var shortcutNumbers
    @ObservedObject var browser: Browser
    @ObservedObject private var activity = AgentActivity.shared
    let group: TabGroup
    var horizontal = false
    var dragSpace: String? = nil
    /// In the column of icons (SideIcons.swift): the name's first letter in
    /// a short heading, the name itself in its tooltip.
    var compact = false

    @State private var draft = ""
    @State private var hovering = false
    @State private var dropping = false
    @FocusState private var focused: Bool

    private var editing: Bool { browser.editingGroupID == group.id }

    /// Its height in the column, a little under a tab's; with Roomy's taller
    /// tabs, taller too, so a heading doesn't look squeezed between them.
    static func height(_ prefs: Preferences) -> CGFloat { prefs.roomyTabs ? 32 : 24 }
    /// The name's size, beside a tab's title.
    private static func type(_ prefs: Preferences) -> CGFloat { prefs.roomyTabs ? 13.5 : 12.5 }

    /// The agent at work in one of its tabs.
    private var working: Bool {
        group.agent != nil && browser.visibleTabs(in: group).contains { activity.working.contains($0.id) }
    }
    /// And in the column of icons.
    static let compactHeight: CGFloat = 18

    /// Measured once a name: the row asks for every heading's on every redraw.
    private static var measured: [String: CGFloat] = [:]
    private static let font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
    static func width(for name: String, numbered: Bool = false, agent: Bool = false) -> CGFloat {
        let text: CGFloat
        if let known = measured[name] {
            text = known
        } else {
            text = ceil((name as NSString).size(withAttributes: [.font: font]).width)
            if measured.count > 500 { measured.removeAll() }
            measured[name] = text
        }
        return text + 20 + (numbered ? 23 : 0) + (agent ? 21 : 0)
    }

    var body: some View {
        if compact { short } else { long }
    }

    /// The column of icons' heading: the letter, a fold mark beside it.
    private var short: some View {
        HStack(spacing: 2) {
            if let agent = group.agent {
                AgentGlyph(agent: agent, size: 11)
            } else {
                Text(group.name.first.map { String($0).uppercased() } ?? "•")
                    .font(.system(size: 9.5, weight: .semibold))
            }
            Image(systemName: "chevron.down")
                .font(.system(size: 6.5, weight: .bold))
                .rotationEffect(.degrees(group.collapsed ? -90 : 0))
        }
        .foregroundStyle(hovering ? Palette.ink.opacity(0.7) : Palette.muted)
        .frame(maxWidth: .infinity)
        .frame(height: Self.compactHeight)
        .background {
            if group.agent != nil {
                AgentGroupGround(working: working, hovering: hovering, dropping: dropping, radius: 6)
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(dropping ? greys.wash : (hovering ? greys.hover : greys.tile))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onTapGesture { browser.toggleTabGroup(group.id) }
        .modifier(GroupHeadingShared(browser: browser, group: group, dragSpace: dragSpace, dropping: $dropping))
        .onHover { hovering = $0 }
        .help(group.collapsed ? "\(group.name) — folded" : group.name)
        .accessibilityLabel(group.name)
        // Rename Group: no room for the name here, so it is typed beside.
        .popover(isPresented: Binding(get: { editing }, set: { if !$0 { browser.editingGroupID = nil } }),
                 arrowEdge: browser.prefs.sidePosition == .right ? .leading : .trailing) {
            TextField("Group name", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5, weight: .medium))
                .frame(width: 160)
                .padding(10)
                .focused($focused)
                .onSubmit(commit)
                .onExitCommand { browser.editingGroupID = nil }
                .onAppear {
                    draft = group.name
                    DispatchQueue.main.async { focused = true }
                }
                .onChange(of: group.name) { old, new in
                    if draft == old { draft = new }
                }
        }
    }

    private var long: some View {
        let size = horizontal ? 12.5 : Self.type(browser.prefs)
        let agent = group.agent
        return HStack(spacing: agent != nil ? 7 : 8) {
            if let agent {
                AgentGlyph(agent: agent, size: horizontal || !browser.prefs.roomyTabs ? 14 : 16)
                    .help(AgentGlyph.name(of: agent).map { "Made by \($0)" } ?? "Made by an extension")
            }
            if editing {
                TextField("Group name", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: size, weight: .medium))
                    .frame(width: horizontal ? max(60, Self.width(for: group.name) - 20) : nil)
                    .focused($focused)
                    .onSubmit(commit)
                    .onExitCommand { browser.editingGroupID = nil }
            } else {
                Text(group.name)
                    .font(.system(size: size, weight: agent != nil ? .semibold : .medium))
                    .foregroundStyle(agent != nil ? Palette.ink.opacity(0.8) : Palette.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if !horizontal { Spacer(minLength: 0) }
            if working, !editing, !horizontal { AgentWorkingDots().transition(.opacity) }
            if !editing, group.collapsed {
                if let number = shortcutNumbers[group.id] {
                    TabShortcutNumber(number: number)
                } else if horizontal, browser.prefs.showsTabShortcuts {
                    Color.clear.frame(width: 15, height: 15)
                }
            }
            if !editing && !horizontal {
                Image(systemName: "chevron.down")
                    .font(.system(size: browser.prefs.roomyTabs ? 10 : 9, weight: .medium))
                    .rotationEffect(.degrees(group.collapsed ? -90 : 0))
                    // A folded group says so; an open one shows its tabs.
                    .opacity(hovering ? 1 : group.collapsed ? 0.55 : 0)
            }
        }
        .foregroundStyle(Palette.muted)
        .padding(.horizontal, 10)
        .frame(height: horizontal ? 28 : Self.height(browser.prefs))
        .frame(maxWidth: horizontal ? nil : .infinity, alignment: .leading)
        .fixedSize(horizontal: horizontal, vertical: false)
        .animation(.easeOut(duration: 0.2), value: working)
        .background {
            if agent != nil {
                AgentGroupGround(working: working, hovering: hovering, dropping: dropping)
            } else {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(dropping ? greys.wash : (hovering ? greys.hover : .clear))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onTapGesture { if !editing { browser.toggleTabGroup(group.id) } }
        .modifier(GroupHeadingShared(browser: browser, group: group, dragSpace: dragSpace, dropping: $dropping))
        .onHover { hovering = $0 }
        .onChange(of: editing) { _, now in
            if now {
                draft = group.name
                DispatchQueue.main.async { focused = true }
            }
        }
        // Named by Apple Intelligence while the name is up to be typed:
        // the new name, unless you've started typing your own.
        .onChange(of: group.name) { old, new in
            if editing, draft == old { draft = new }
        }
        .onAppear {
            if editing {
                draft = group.name
                DispatchQueue.main.async { focused = true }
            }
        }
    }

    private func commit() {
        browser.renameTabGroup(group.id, to: draft)
        browser.editingGroupID = nil
    }
}

/// What both headings answer to: their place for a drop, a tab or a
/// group let go on them, being picked up, and their menu.
private struct GroupHeadingShared: ViewModifier {
    @ObservedObject var browser: Browser
    let group: TabGroup
    let dragSpace: String?
    @Binding var dropping: Bool

    func body(content: Content) -> some View {
        content
            .background {
                if let dragSpace {
                    GeometryReader { geometry in
                        Color.clear.preference(key: GroupDropFrames.self,
                                               value: [group.id: GroupDropFrame(group: group.id, rect: geometry.frame(in: .named(dragSpace)))])
                    }
                }
            }
            .onDrop(of: [.text], isTargeted: $dropping) { providers in
                guard let provider = providers.first(where: { $0.canLoadObject(ofClass: String.self) }) else { return false }
                _ = provider.loadObject(ofClass: String.self) { value, _ in
                    guard let value else { return }
                    DispatchQueue.main.async {
                        if value.hasPrefix("search-group:"),
                           let id = UUID(uuidString: String(value.dropFirst("search-group:".count))),
                           let index = browser.tabGroups.firstIndex(where: { $0.id == group.id }) {
                            browser.moveTabGroup(id, to: index)
                        }
                    }
                }
                return true
            }
            .onDrag { NSItemProvider(object: "search-group:\(group.id.uuidString)" as NSString) }
            .contextMenu {
                Button("Rename Group") { browser.editingGroupID = group.id }
                Button(group.collapsed ? "Expand Group" : "Collapse Group") { browser.toggleTabGroup(group.id) }
                // The whole group into another space, still a group there: Arc's
                // folders came in wherever Arc had them.
                if browser.prefs.usesSpaces, browser.spaces.count > 1 {
                    Menu("Move Group to Space") {
                        ForEach(browser.spaces.filter { $0.id != browser.spaceID }) { space in
                            Button {
                                browser.move(group: group.id, toSpace: space.id)
                            } label: {
                                Label(space.name, systemImage: space.symbol)
                            }
                        }
                    }
                }
                Divider()
                Button("Ungroup Tabs") { browser.removeTabGroup(group.id) }
                Button("Close Group") { browser.closeTabGroup(group.id) }
            }
    }
}
