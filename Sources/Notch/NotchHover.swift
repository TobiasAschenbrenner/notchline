import Foundation

struct NotchHover {
    private var enteredAt: TimeInterval?
    private var leftAt: TimeInterval?

    mutating func expansion(inside: Bool, expanded: Bool, dragging: Bool, now: TimeInterval) -> Bool? {
        if dragging {
            reset()
            return nil
        }
        if inside {
            leftAt = nil
            guard !expanded else { enteredAt = nil; return nil }
            let start = enteredAt ?? now
            enteredAt = start
            return now - start >= 0.085 ? true : nil
        }
        enteredAt = nil
        guard expanded else { leftAt = nil; return nil }
        let start = leftAt ?? now
        leftAt = start
        return now - start >= 0.14 ? false : nil
    }

    mutating func reset() {
        enteredAt = nil
        leftAt = nil
    }
}
