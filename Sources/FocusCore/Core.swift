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
    public init() {}
    public mutating func press(_ time: Double) { if start == nil { start = time; fired = false } }
    public mutating func cancel() { start = nil; fired = false }
    public func progress(_ time: Double) -> Double { start.map { min(1, max(0, (time - $0) / 3)) } ?? 0 }
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
