import Foundation

public struct Shortcut: Equatable {
    public static let shift: UInt64 = 1 << 17
    public static let control: UInt64 = 1 << 18
    public static let option: UInt64 = 1 << 19
    public static let command: UInt64 = 1 << 20
    public static let modifierMask = shift | control | option | command
    public let key: UInt16
    public let modifiers: UInt64
    public init(key: UInt16, modifiers: UInt64) { self.key = key; self.modifiers = modifiers & Self.modifierMask }
    public func validationError(other: Shortcut? = nil) -> String? {
        if key == 53 { return "Esc 保留給取消錄製與結束講解。" }
        if [54,55,56,57,58,59,60,61,62,63].contains(Int(key)) { return "請再按一個字母、數字或功能鍵。" }
        if modifiers == 0 { return "請搭配 Control、Option、Command 或 Shift。" }
        if modifiers == Self.shift { return "請加入 Control、Option 或 Command，避免影響一般打字。" }
        if modifiers == Self.command && [12,13,48,49].contains(Int(key)) { return "此組合保留給常用系統操作，請換一組。" }
        if self == other { return "與另一項功能的快捷鍵重複，請換一組。" }
        return nil
    }
}

public struct EscapeCapture {
    public private(set) var consumed = false
    public init() {}
    public mutating func keyDown(lessonActive: Bool) -> Bool {
        if !lessonActive && !consumed { return false }
        consumed = true; return true
    }
    public mutating func keyUp() -> Bool { let result = consumed; consumed = false; return result }
    public mutating func reset() { consumed = false }
}
