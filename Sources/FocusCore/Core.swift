import Foundation
import CoreGraphics
public struct DoubleTap {
    private var down: Double?
    private var last: Double?
    private var blocked = false
    public init() {}
    public mutating func cancel() { down = nil; last = nil; blocked = false }
    public mutating func update(pressed: Bool, clean: Bool, time: Double) -> Bool {
        guard clean else { down = nil; last = nil; blocked = pressed; return false }
        if blocked { if !pressed { blocked = false }; return false }
        if pressed { if down == nil { down = time }; return false }
        guard let start = down else { return false }
        down = nil
        guard time - start <= 0.35 else { last = nil; return false }
        if let previous = last, time - previous <= 0.35 { last = nil; return true }
        last = time; return false
    }
}
public struct Hold {
    public private(set) var start: Double?
    private var fired = false
    private var duration = 3.0
    public init() {}
    public mutating func press(_ time: Double, duration: Double = 3) { if start == nil { start = time; fired = false; self.duration = duration.isFinite ? min(10, max(0.5, duration)) : 3 } }
    public mutating func cancel() { start = nil; fired = false }
    public func progress(_ time: Double) -> Double { start.map { min(1, max(0, (time - $0) / duration)) } ?? 0 }
    public mutating func tick(_ time: Double) -> Bool {
        if start != nil && !fired && progress(time) >= 1 { fired = true; return true }; return false
    }
}
public struct History<T> {
    public private(set) var items: [T] = []
    public private(set) var future: [T] = []
    public init() {}
    public mutating func add(_ value: T) { items.append(value); future.removeAll() }
    public mutating func undo() { if let value = items.popLast() { future.append(value) } }
    public mutating func redo() { if let value = future.popLast() { items.append(value) } }
    public mutating func clear() { items.removeAll(); future.removeAll() }
}
public func localPoint(_ point: CGPoint, frame: CGRect) -> CGPoint { CGPoint(x: point.x - frame.minX, y: point.y - frame.minY) }

public struct SpotlightEntrance {
    private var started: Double?
    public init() {}
    public mutating func begin(_ time: Double) { started = time }
    public mutating func reset() { started = nil }
    public func sample(_ time: Double, reducedMotion: Bool = false) -> (scale: Double, opacity: Double, animating: Bool) {
        guard !reducedMotion, let started else { return (1, 1, false) }
        let progress = min(1, max(0, (time - started) / 0.25))
        let eased = 1 - pow(1 - progress, 3)
        return (1 + 0.65 * (1 - eased), eased, progress < 1)
    }
}
