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
}
