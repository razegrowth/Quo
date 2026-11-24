import Foundation

/// A named section of ordinary tabs in one space's tab layout.
/// Its tabs remain ordinary tabs; their own group IDs describe membership.
struct TabGroup: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var collapsed: Bool
    /// The extension that made it to work in — an agent driving pages
    /// through Chrome's debugger, as Claude's and ChatGPT's do — by its id,
    /// for its icon and its look in the column (AgentGroups.swift). Nil for
    /// a group of your own.
    var agent: String? = nil
    /// The group it is inside, for a group in a group (as Dia nests them),
    /// or nil at the top. A row's groups are kept in tree order: each group,
    /// then the groups inside it, so the flat row of tabs, the strip and an
    /// extension's list of groups read them in the order the column shows.
    var parent: UUID? = nil

    /// How many levels deep groups go, the top one counted: Dia's eight.
    static let deepest = 8
}

extension TabGroup {
    private enum Keys: String, CodingKey { case id, name, collapsed, agent, parent }

    /// A group saved without its folded state is an open one.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        collapsed = (try? c.decodeIfPresent(Bool.self, forKey: .collapsed)) ?? false
        agent = try? c.decodeIfPresent(String.self, forKey: .agent)
        parent = try? c.decodeIfPresent(UUID.self, forKey: .parent)
    }
}

/// Groups in groups, read from a row's list of them.
extension Array where Element == TabGroup {
    func group(_ id: UUID?) -> TabGroup? {
        guard let id else { return nil }
        return first { $0.id == id }
    }

    /// How deep a group is: 0 at the top.
    func depth(of id: UUID) -> Int {
        var depth = 0
        var at = group(id)?.parent
        while let parent = at, depth < TabGroup.deepest {
            depth += 1
            at = group(parent)?.parent
        }
        return depth
    }

    /// The groups it is inside, nearest first.
    func ancestors(of id: UUID) -> [UUID] {
        var found: [UUID] = []
        var at = group(id)?.parent
        while let parent = at, !found.contains(parent), found.count < TabGroup.deepest {
            found.append(parent)
            at = group(parent)?.parent
        }
        return found
    }

    /// The group and every group inside it, at any depth, in tree order.
    func subtree(of id: UUID) -> [UUID] {
        var found = [id]
        var index = 0
        while index < found.count {
            let here = found[index]
            found += filter { $0.parent == here && !found.contains($0.id) }.map(\.id)
            index += 1
        }
        return filter { found.contains($0.id) }.map(\.id)
    }

    /// How many levels a group and what's inside it take, itself counted.
    func height(of id: UUID) -> Int {
        let inside = subtree(of: id)
        let top = depth(of: id)
        return (inside.map { depth(of: $0) }.max() ?? top) - top + 1
    }

    /// Folded away inside a folded group: not drawn at all.
    func hiddenByFold(_ id: UUID) -> Bool {
        ancestors(of: id).contains { group($0)?.collapsed == true }
    }

    /// The groups drawn, each with how deep it is, in the order drawn.
    func shown() -> [(group: TabGroup, depth: Int)] {
        filter { !hiddenByFold($0.id) }.map { ($0, depth(of: $0.id)) }
    }

    /// The list put in tree order, each level in the order it had: a group,
    /// then the groups inside it. A parent that isn't here, one that would
    /// make a loop, or a level past the eighth puts the group at the top.
    func treeOrdered() -> [TabGroup] {
        let ids = Set(map(\.id))
        var fixed = self
        for index in fixed.indices {
            guard let parent = fixed[index].parent else { continue }
            if !ids.contains(parent) || parent == fixed[index].id {
                fixed[index].parent = nil
                continue
            }
            // A loop: walking up comes back to this group.
            var seen: Set<UUID> = [fixed[index].id]
            var at: UUID? = parent
            while let step = at, !seen.contains(step) {
                seen.insert(step)
                at = fixed.first { $0.id == step }?.parent
            }
            if at != nil { fixed[index].parent = nil }
        }
        var ordered: [TabGroup] = []
        func place(_ parent: UUID?, depth: Int) {
            for group in fixed where group.parent == parent {
                ordered.append(group)
                if depth + 1 < TabGroup.deepest { place(group.id, depth: depth + 1) }
            }
        }
        place(nil, depth: 0)
        // Anything a level too deep came loose above: put it, and what's
        // inside it, at the end.
        for group in fixed where !ordered.contains(where: { $0.id == group.id }) {
            var loose = group
            loose.parent = nil
            ordered.append(loose)
        }
        return ordered
    }
}

extension TabGroup {
    /// The number an extension knows the group by, as Chrome numbers its
    /// groups. Taken from the identifier, so it stays the same for as long
    /// as the group lasts, across launches too, with nothing to keep.
    static func number(_ id: UUID) -> Int {
        let u = id.uuid
        let n = Int(u.0 & 0x7F) << 24 | Int(u.1) << 16 | Int(u.2) << 8 | Int(u.3)
        return n == 0 ? 1 : n
    }
}
