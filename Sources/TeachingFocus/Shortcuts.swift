import AppKit
import Carbon
import FocusCore

final class ShortcutRouter {
    private var handler: EventHandlerRef?
    private var refs: [EventHotKeyRef] = []
    private var pressedIDs: Set<UInt32> = []
    var onAction: ((String) -> Void)?
    private(set) var error: String?
    init() {
        var types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)), EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        let result = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            let router = Unmanaged<ShortcutRouter>.fromOpaque(context).takeUnretainedValue()
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard status == noErr, identifier.signature == 0x54464F43 else { return OSStatus(eventNotHandledErr) }
            if GetEventKind(event) == UInt32(kEventHotKeyReleased) { router.pressedIDs.remove(identifier.id); return noErr }
            guard router.pressedIDs.insert(identifier.id).inserted else { return noErr }
            let action = identifier.id == 1 ? "freezeKey" : "spotKey"
            DispatchQueue.main.async { router.onAction?(action) }
            return noErr
        }, types.count, &types, Unmanaged.passUnretained(self).toOpaque(), &handler)
        if result != noErr { error = "無法建立快捷鍵監聽（\(result)）。" }
    }
    func unregister() { for ref in refs { UnregisterEventHotKey(ref) }; refs.removeAll(); pressedIDs.removeAll() }
    func register(_ bindings: [String: Shortcut]) -> String? {
        unregister()
        guard handler != nil else { return error ?? "無法建立快捷鍵監聽。" }
        for (index, action) in ["freezeKey", "spotKey"].enumerated() {
            guard let binding = bindings[action] else { continue }
            var modifiers: UInt32 = 0
            if binding.modifiers & Shortcut.control != 0 { modifiers |= UInt32(controlKey) }
            if binding.modifiers & Shortcut.option != 0 { modifiers |= UInt32(optionKey) }
            if binding.modifiers & Shortcut.shift != 0 { modifiers |= UInt32(shiftKey) }
            if binding.modifiers & Shortcut.command != 0 { modifiers |= UInt32(cmdKey) }
            var reference: EventHotKeyRef?
            let code = RegisterEventHotKey(UInt32(binding.key), modifiers, EventHotKeyID(signature: 0x54464F43, id: UInt32(index + 1)), GetApplicationEventTarget(), 0, &reference)
            guard code == noErr, let reference else {
                unregister()
                error = "\(action == "freezeKey" ? "凍結" : "聚光燈")快捷鍵註冊失敗，可能被其他程式占用（\(code)）。請換一組。"
                return error
            }
            refs.append(reference)
        }
        error = nil; return nil
    }
    deinit { unregister(); if let handler { RemoveEventHandler(handler) } }
}

final class RecorderPanel: NSPanel {
    var onClose: (() -> Void)?
    override func close() { let callback = onClose; onClose = nil; super.close(); callback?() }
}

final class RecorderField: NSView {
    var onKey: ((NSEvent) -> Void)?
    var onFlags: ((NSEvent) -> Void)?
    var text = "請按下想使用的快捷鍵…" { didSet { needsDisplay = true } }
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }
    override func keyDown(with event: NSEvent) { onKey?(event) }
    override func flagsChanged(with event: NSEvent) { onFlags?(event) }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        onKey?(event); return true
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10).fill()
        NSColor.controlAccentColor.setStroke()
        let frame = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10); frame.lineWidth = 2; frame.stroke()
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 22, weight: .medium), .foregroundColor: NSColor.labelColor]
        let label = text as NSString; let size = label.size(withAttributes: attrs)
        label.draw(at: NSPoint(x: (bounds.width-size.width)/2, y: (bounds.height-size.height)/2), withAttributes: attrs)
    }
}

func shortcutLabel(_ binding: Shortcut) -> String {
    var prefix = ""
    if binding.modifiers & Shortcut.control != 0 { prefix += "⌃ " }
    if binding.modifiers & Shortcut.option != 0 { prefix += "⌥ " }
    if binding.modifiers & Shortcut.shift != 0 { prefix += "⇧ " }
    if binding.modifiers & Shortcut.command != 0 { prefix += "⌘ " }
    let names: [UInt16: String] = [0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",24:"=",25:"9",26:"7",27:"-",28:"8",29:"0",30:"]",31:"O",32:"U",33:"[",34:"I",35:"P",36:"Return",37:"L",38:"J",39:"'",40:"K",41:";",42:"\\",43:",",44:"/",45:"N",46:"M",47:".",48:"Tab",49:"Space",50:"`",51:"Delete",65:"Keypad .",67:"Keypad *",69:"Keypad +",75:"Keypad /",76:"Enter",78:"Keypad -",81:"Keypad =",82:"Keypad 0",83:"Keypad 1",84:"Keypad 2",85:"Keypad 3",86:"Keypad 4",87:"Keypad 5",88:"Keypad 6",89:"Keypad 7",91:"Keypad 8",92:"Keypad 9",64:"F17",79:"F18",80:"F19",90:"F20",105:"F13",107:"F14",113:"F15",106:"F16",96:"F5",97:"F6",98:"F7",99:"F3",100:"F8",101:"F9",103:"F11",109:"F10",111:"F12",115:"Home",116:"Page Up",117:"Forward Delete",118:"F4",119:"End",120:"F2",121:"Page Down",122:"F1",123:"←",124:"→",125:"↓",126:"↑"]
    return prefix + (names[binding.key] ?? "Key \(binding.key)")
}

extension Controller {
    func binding(_ key: String) -> Shortcut {
        let fallback = key == "freezeKey" ? 2.0 : 1.0
        let code = UInt16(clamping: Int(number(key, fallback)))
        let modifiers = UInt64(max(0, number(key + "Modifiers", Double(Shortcut.control | Shortcut.option))))
        return Shortcut(key: code, modifiers: modifiers)
    }
    func savedBindings() -> [String: Shortcut] { ["freezeKey": binding("freezeKey"), "spotKey": binding("spotKey")] }
    func registerSavedShortcuts() {
        guard !paused && recordingAction == nil else { return }
        _ = shortcutRouter?.register(savedBindings())
        for (key, label) in shortcutLabels { label.stringValue = shortcutLabel(binding(key)) }
    }
    @objc func startRecording(_ sender: NSButton) {
        guard let action = sender.identifier?.rawValue else { return }
        beginRecording(action)
    }
    func beginRecording(_ action: String) {
        recorderPanel?.close()
        end(); hold.cancel(); escape.reset(); doubleTap.cancel()
        shortcutRouter?.unregister()
        recordingAction = action; recordingCandidate = nil
        let panel = RecorderPanel(contentRect: NSRect(x:0,y:0,width:490,height:245), styleMask:[.titled,.closable], backing:.buffered, defer:false)
        panel.title = action == "freezeKey" ? "錄製凍結快捷鍵" : "錄製聚光燈快捷鍵"
        panel.level = .init(rawValue:Int(CGWindowLevelForKey(.screenSaverWindow))+3)
        panel.isReleasedWhenClosed = false
        let field = RecorderField(frame: NSRect(x:20,y:130,width:450,height:64))
        field.onKey = { [weak self] event in self?.recordKey(event) }
        field.onFlags = { [weak self] event in
            guard self?.recordingCandidate == nil else { return }
            let symbols = shortcutLabel(Shortcut(key:0,modifiers:UInt64(event.modifierFlags.rawValue))).dropLast()
            self?.recorderField?.text = symbols.isEmpty ? "請按下想使用的快捷鍵…" : String(symbols) + "…"
        }
        let message = NSTextField(wrappingLabelWithString:"請按下修飾鍵＋按鍵，例如 Control＋Option＋F。按 Esc 取消；錄製時不會觸發教學功能。")
        message.frame = NSRect(x:20,y:65,width:450,height:52)
        let save = button("儲存", #selector(saveRecording)); save.isEnabled = false; save.frame=NSRect(x:360,y:18,width:110,height:32)
        let cancel = button("取消", #selector(cancelRecording)); cancel.frame=NSRect(x:240,y:18,width:110,height:32)
        for view in [field,message,save,cancel] as [NSView] { panel.contentView?.addSubview(view) }
        panel.onClose = { [weak self] in
            guard let self else { return }
            self.recordingAction=nil; self.recordingCandidate=nil; self.recorderPanel=nil; self.recorderField=nil; self.recorderMessage=nil; self.recorderSaveButton=nil
            self.doubleTap.cancel(); self.hold.cancel(); self.escape.reset(); self.registerSavedShortcuts(); self.refreshStatus()
            self.settings?.makeKeyAndOrderFront(nil)
        }
        recorderPanel=panel; recorderField=field; recorderMessage=message; recorderSaveButton=save
        if !testMode { panel.center(); NSApp.activate(ignoringOtherApps:true); panel.makeKeyAndOrderFront(nil) }; panel.makeFirstResponder(field)
    }
    func recordKey(_ event:NSEvent) {
        guard let action=recordingAction, !event.isARepeat else { return }
        if event.keyCode == 53 { cancelRecording(); return }
        let candidate=Shortcut(key:event.keyCode,modifiers:UInt64(event.modifierFlags.rawValue))
        recorderField?.text=shortcutLabel(candidate)
        if let error=candidate.validationError(other:binding(action == "freezeKey" ? "spotKey":"freezeKey")) {
            recordingCandidate=nil; recorderSaveButton?.isEnabled=false; recorderMessage?.stringValue=error; return
        }
        recordingCandidate=candidate; recorderSaveButton?.isEnabled=true
        recorderMessage?.stringValue="已錄製。按「儲存」套用，或繼續按鍵重新錄製。"
    }
    @objc func saveRecording() {
        guard let action=recordingAction, let candidate=recordingCandidate else { return }
        if let error=candidate.validationError(other:binding(action == "freezeKey" ? "spotKey":"freezeKey")) { recorderMessage?.stringValue=error; return }
        guard let shortcutRouter else { recorderMessage?.stringValue="快捷鍵監聽尚未建立。"; return }
        var bindings=savedBindings(); bindings[action]=candidate
        // Check OS registration before changing stored settings. During recording old bindings are unregistered.
        if let error=shortcutRouter.register(bindings) { recorderMessage?.stringValue=error; return }
        preferences.set(Double(candidate.key),forKey:action)
        preferences.set(Double(candidate.modifiers),forKey:action + "Modifiers")
        if paused { shortcutRouter.unregister() }
        recorderPanel?.close()
    }
    @objc func cancelRecording() { recorderPanel?.close() }
}
