import Foundation

public enum IslandMode: Equatable {
    case collapsed, expanded
}

public enum ExpansionEvent: Equatable {
    case pointerEntered, pointerExited, collapseDelayElapsed, clicked
}

public enum ExpansionEffect: Equatable {
    case none
    case scheduleCollapse(after: TimeInterval)
    case cancelCollapse
}

/// Decides when the island opens and closes. The caller runs the returned effect (a cancellable timer).
public struct ExpansionStateMachine {
    public var hoverOpens: Bool
    public var collapseDelay: TimeInterval
    public private(set) var mode: IslandMode = .collapsed
    /// While pinned the island stays open whatever the pointer does.
    public private(set) var isPinned = false
    /// True while Mission Control is on screen: the island stays closed and does not react to hover or clicks.
    public private(set) var isSuspended = false
    private var pointerInside = false

    public init(hoverOpens: Bool, collapseDelay: TimeInterval) {
        self.hoverOpens = hoverOpens
        self.collapseDelay = collapseDelay
    }

    public mutating func handle(_ event: ExpansionEvent) -> ExpansionEffect {
        switch event {
        case .pointerEntered:
            pointerInside = true
            if isSuspended { return .none }
            if mode == .expanded { return .cancelCollapse }
            guard hoverOpens else { return .none }
            mode = .expanded
            return .cancelCollapse
        case .pointerExited:
            pointerInside = false
            return mode == .expanded && !isPinned ? .scheduleCollapse(after: collapseDelay) : .none
        case .collapseDelayElapsed:
            // A stale timer must not close the island while the pointer is back inside.
            if mode == .expanded && !pointerInside && !isPinned { mode = .collapsed }
            return .none
        case .clicked:
            pointerInside = true
            guard mode == .collapsed, !isSuspended else { return .none }
            mode = .expanded
            return .cancelCollapse
        }
    }

    /// Pinning opens the island and keeps it open. Unpinning lets it close again: at once if the pointer is away
    /// (after the usual delay), or when the pointer leaves if it is still over the island.
    public mutating func setPinned(_ pinned: Bool) -> ExpansionEffect {
        guard pinned != isPinned || pinned else { return .none }
        isPinned = pinned
        if pinned {
            // Pinned while Mission Control is up: remembered, and the island opens when Mission Control goes away.
            guard !isSuspended else { return .none }
            mode = .expanded
            return .cancelCollapse
        }
        return mode == .expanded && !pointerInside ? .scheduleCollapse(after: collapseDelay) : .none
    }

    /// Mission Control came or went. Suspending closes an open island at once (pinned or not, the pin is remembered);
    /// an unpinned island stays closed afterwards until the pointer enters or clicks again, a pinned one reopens.
    public mutating func setSuspended(_ suspended: Bool) -> ExpansionEffect {
        guard suspended != isSuspended else { return .none }
        isSuspended = suspended
        if suspended {
            guard mode == .expanded else { return .none }
            mode = .collapsed
            return .cancelCollapse
        }
        if isPinned {
            mode = .expanded
            return .cancelCollapse
        }
        return .none
    }
}
