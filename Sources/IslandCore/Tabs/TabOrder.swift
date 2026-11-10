/// Works out the order tabs are shown in from the user's saved order.
public enum TabOrder {
    /// The saved ids that still exist (each once, in the saved order), followed by any tab the saved order does not
    /// mention, in the default order. So a tab is never hidden by an old or hand-edited setting.
    public static func normalized(saved: [String], all: [String]) -> [String] {
        let known = Set(all)
        var seen = Set<String>()
        var result: [String] = []
        for id in saved where known.contains(id) && seen.insert(id).inserted {
            result.append(id)
        }
        for id in all where seen.insert(id).inserted {
            result.append(id)
        }
        return result
    }

    /// `order` with `id` moved `offset` places (negative is earlier), stopping at the ends. An unknown id changes nothing.
    public static func moved(_ order: [String], id: String, by offset: Int) -> [String] {
        guard let index = order.firstIndex(of: id) else { return order }
        let target = min(max(index + offset, 0), order.count - 1)
        guard target != index else { return order }
        var result = order
        result.remove(at: index)
        result.insert(id, at: target)
        return result
    }

    /// `id` moved to where `target` is now: dragging a row onto another row puts it in that row's place, and the rows in
    /// between shift by one. An unknown id or target, or the same row, changes nothing.
    public static func moved(_ order: [String], id: String, to target: String) -> [String] {
        guard id != target, let from = order.firstIndex(of: id), let to = order.firstIndex(of: target) else { return order }
        var result = order
        result.remove(at: from)
        result.insert(id, at: to)
        return result
    }

    /// `ordered` without the tabs in `hidden` (ids that are not in `ordered` are ignored). The island is never left with no
    /// tab: if `hidden` would remove every one (a hand-edited setting), all of them are shown.
    public static func shown(_ ordered: [String], hidden: [String]) -> [String] {
        let off = Set(hidden)
        let result = ordered.filter { !off.contains($0) }
        return result.isEmpty ? ordered : result
    }

    /// The list of switched-off tabs after `id` is switched on (`shown: true`) or off. The last tab that is on cannot be
    /// switched off, and an unknown id changes nothing. The result holds each known id once, in the order of `all`.
    public static func settingShown(_ shown: Bool, id: String, hidden: [String], all: [String]) -> [String] {
        guard all.contains(id) else { return hidden }
        var off = Set(hidden).intersection(all)
        if shown {
            off.remove(id)
        } else if !off.contains(id) {
            guard all.filter({ !off.contains($0) }).count > 1 else { return all.filter(off.contains) }
            off.insert(id)
        }
        return all.filter(off.contains)
    }
}
