import AppKit
import ScreenCaptureKit
import CoreMedia
import FocusCore

let palette: [NSColor] = [.systemRed, .systemBlue, .systemGreen, .black, .white]
let clockNow: () -> Double = { ProcessInfo.processInfo.systemUptime }
struct Stroke { var points: [CGPoint]; var color: NSColor; var width: CGFloat; var tool: Int; var born: Double }
final class Overlay: NSWindow { override var canBecomeKey: Bool { true } }
final class Canvas: NSView {
    weak var owner: Controller?
    var snapshot: CGImage?
    var history = History<Stroke>()
    var live: Stroke?
    var lasers: [Stroke] = []
    var ripples: [(CGPoint, Double)] = []
    var spotlight = false
    var cursor = CGPoint.zero
    override var acceptsFirstResponder: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        guard let owner else { return }
        NSColor.clear.setFill(); bounds.fill(using: .copy)
        if let snapshot { NSGraphicsContext.current?.cgContext.draw(snapshot, in: bounds) }
        for stroke in history.items { drawStroke(stroke, alpha: 1) }
        if let live { drawStroke(live, alpha: 1) }
        for stroke in lasers { drawStroke(stroke, alpha: max(0, 1 - (clockNow() - stroke.born))) }
        if spotlight {
            let radius = owner.number("radius", 120)
            let hole = NSRect(x: cursor.x-radius, y: cursor.y-radius, width: radius*2, height: radius*2)
            let shade = NSBezierPath(rect: bounds); shade.appendOval(in: hole); shade.windingRule = .evenOdd
            NSColor.black.withAlphaComponent(owner.number("dim", 0.6)).setFill(); shade.fill()
            if owner.bool("border", true) {
                NSGraphicsContext.saveGraphicsState()
                let shadow = NSShadow(); shadow.shadowColor = owner.borderColor; shadow.shadowBlurRadius = owner.number("glow", 12); shadow.set()
                owner.borderColor.setStroke(); let ring = NSBezierPath(ovalIn: hole); ring.lineWidth = owner.number("borderWidth", 3); ring.stroke()
                NSGraphicsContext.restoreGraphicsState()
            }
        } else if owner.bool("halo", false) {
            NSColor.systemYellow.withAlphaComponent(0.3).setFill(); NSBezierPath(ovalIn: NSRect(x: cursor.x-20,y:cursor.y-20,width:40,height:40)).fill()
        }
        for (point, born) in ripples {
            let age = clockNow() - born; let r = 12 + age * 65
            NSColor.systemCyan.withAlphaComponent(max(0, 1-age/0.6)).setStroke()
            let path = NSBezierPath(ovalIn: NSRect(x:point.x-r,y:point.y-r,width:r*2,height:r*2)); path.lineWidth=3; path.stroke()
        }
        if owner.hold.start != nil {
            let p = owner.hold.progress(clockNow()); let center = CGPoint(x: bounds.midX, y: 75)
            NSColor.black.withAlphaComponent(0.8).setFill(); NSBezierPath(roundedRect: NSRect(x: center.x-170,y:25,width:340,height:100), xRadius:16,yRadius:16).fill()
            let ring = NSBezierPath(); ring.appendArc(withCenter:center, radius:22, startAngle:90, endAngle:90-CGFloat(p)*360, clockwise:true); ring.lineWidth=5; NSColor.systemCyan.setStroke(); ring.stroke()
            ("持續按住 Esc 以結束講解" as NSString).draw(at: CGPoint(x:center.x-100,y:35), withAttributes:[.font:NSFont.systemFont(ofSize:16),.foregroundColor:NSColor.white])
        }
    }
    func drawStroke(_ s: Stroke, alpha: Double) {
        guard let first=s.points.first, let last=s.points.last else { return }
        s.color.withAlphaComponent(alpha).setStroke(); let path=NSBezierPath(); path.lineWidth=s.width; path.lineCapStyle = .round; path.lineJoinStyle = .round
        let box=NSRect(x:min(first.x,last.x),y:min(first.y,last.y),width:abs(last.x-first.x),height:abs(last.y-first.y))
        switch s.tool {
        case 3: path.appendRect(box)
        case 4: path.appendOval(in:box)
        case 1,2:
            path.move(to:first); path.line(to:last)
            if s.tool==2 { let angle=atan2(last.y-first.y,last.x-first.x); let length=max(15,s.width*4); for delta in [-0.5,0.5] { path.move(to:last); path.line(to:CGPoint(x:last.x-length*cos(angle+delta),y:last.y-length*sin(angle+delta))) } }
        default:
            path.move(to:first); for point in s.points.dropFirst() { path.line(to:point) }
            if s.points.count==1 { path.line(to:CGPoint(x:first.x+0.1,y:first.y)) }
        }
        path.stroke()
    }
    override func mouseDown(with event: NSEvent) {
        guard snapshot != nil, let owner else { return }
        live=Stroke(points:[convert(event.locationInWindow,from:nil)],color:palette[owner.colorIndex],width:owner.number("penWidth",4),tool:owner.tool,born:clockNow()); needsDisplay=true
    }
    override func mouseDragged(with event:NSEvent) { live?.points.append(convert(event.locationInWindow,from:nil)); needsDisplay=true }
    override func mouseUp(with event:NSEvent) {
        if var stroke=live { stroke.points.append(convert(event.locationInWindow,from:nil)); stroke.born=clockNow(); if stroke.tool==5 { lasers.append(stroke) } else { history.add(stroke) } }; live=nil; needsDisplay=true
    }
}

final class Capture: NSObject, SCStreamOutput {
    var stream: SCStream?
    private var completion: ((Result<CGImage,Error>)->Void)?
    private let lock=NSLock()
    private var cancelled=false
    func isCancelled() -> Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func finish(_ result: Result<CGImage,Error>) {
        lock.lock(); let callback=completion; completion=nil; cancelled=true; lock.unlock()
        guard let callback else { return }
        DispatchQueue.main.async { self.stream?.stopCapture(completionHandler:nil); self.stream=nil; callback(result) }
    }
    func start(displayID: CGDirectDisplayID, completion: @escaping(Result<CGImage,Error>)->Void) {
        self.completion=completion
        Task {
            do {
                let content=try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:true)
                guard let display=content.displays.first(where:{$0.displayID==displayID}) else { throw NSError(domain:"找不到螢幕",code:1) }
                let excluded=content.applications.filter{$0.processID==ProcessInfo.processInfo.processIdentifier}
                let filter=SCContentFilter(display:display,excludingApplications:excluded,exceptingWindows:[])
                let config=SCStreamConfiguration(); config.width=CGDisplayCopyDisplayMode(displayID)?.pixelWidth ?? CGDisplayPixelsWide(displayID); config.height=CGDisplayCopyDisplayMode(displayID)?.pixelHeight ?? CGDisplayPixelsHigh(displayID); config.showsCursor=false; config.capturesAudio=false; config.queueDepth=3; config.pixelFormat=kCVPixelFormatType_32BGRA
                let stream=SCStream(filter:filter,configuration:config,delegate:nil); self.stream=stream
                try stream.addStreamOutput(self,type:.screen,sampleHandlerQueue:DispatchQueue(label:"focus.capture"))
                let cancelled=self.isCancelled()
                if cancelled { self.stream=nil; return }
                try await stream.startCapture()
                let stop=self.isCancelled()
                if stop { try? await stream.stopCapture() }
            } catch { self.finish(.failure(error)) }
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+5) { self.finish(.failure(NSError(domain:"擷取逾時，請檢查螢幕錄製權限",code:2))) }
    }
    func stream(_ stream:SCStream,didOutputSampleBuffer sampleBuffer:CMSampleBuffer,of type:SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments=CMSampleBufferGetSampleAttachmentsArray(sampleBuffer,createIfNecessary:false) as? [[SCStreamFrameInfo:Any]],
              let raw=attachments.first?[.status] as? Int, raw==SCFrameStatus.complete.rawValue,
              let buffer=sampleBuffer.imageBuffer else { return }
        let ci=CIImage(cvPixelBuffer:buffer)
        if let image=CIContext().createCGImage(ci,from:ci.extent) { finish(.success(image)) }
    }
}

final class Controller: NSObject, NSApplicationDelegate {
    var status: NSStatusItem!
    var windows: [Overlay]=[]
    var toolbar:NSPanel?
    var settings:NSWindow?
    var timer:Timer?
    var tap:CFMachPort?
    var tapSource:CFRunLoopSource?
    var doubleTap=DoubleTap()
    var hold=Hold()
    var capturing=false
    var generation=0
    var capture:Capture?
    var spot=false
    var tool=0
    var colorIndex=0
    var frozen:Canvas? { windows.compactMap{$0.contentView as? Canvas}.first{$0.snapshot != nil} }
    var previousApp:NSRunningApplication?
    var active:Bool { spot || frozen != nil || bool("halo",false) }
    var escapeConsumed=false
    var permissionCheckTime=0.0
    var borderColor:NSColor { paletteColor(UserDefaults.standard.integer(forKey:"borderColor")) }
    func paletteColor(_ index:Int)->NSColor { [.systemCyan,.systemYellow,.systemGreen,.systemPink,.white][max(0,min(4,index))] }
    func number(_ key:String,_ fallback:Double)->Double { UserDefaults.standard.object(forKey:key) as? Double ?? fallback }
    func bool(_ key:String,_ fallback:Bool)->Bool { UserDefaults.standard.object(forKey:key) as? Bool ?? fallback }
    func applicationDidFinishLaunching(_ notification:Notification) {
        if CommandLine.arguments.contains("--diagnostics") {
            print("Accessibility: \(AXIsProcessTrusted())")
            print("ScreenCapture: \(CGPreflightScreenCaptureAccess())")
            for screen in NSScreen.screens { print("Display: \(screen.localizedName) frame=\(screen.frame) scale=\(screen.backingScaleFactor)") }
            NSApp.terminate(nil); return
        }
        NSApp.setActivationPolicy(.accessory)
        status=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength); status.button?.title="◎ 教學"
        let menu=NSMenu()
        for (name,action) in [("切換聚光燈（雙按 Control）",#selector(toggleSpot)),("凍結與畫筆",#selector(freeze)),("結束講解",#selector(end)),("設定…",#selector(showSettings)),("權限與使用說明…",#selector(permissions)),("結束工具",#selector(quit))] { let item=NSMenuItem(title:name,action:action,keyEquivalent:""); item.target=self; menu.addItem(item) }; status.menu=menu
        if CommandLine.arguments.contains("--render-checks") { renderChecks(); return }
        if CommandLine.arguments.contains("--capture-checks") { captureChecks(); return }
        rebuild(); installTap()
        timer=Timer(timeInterval:1.0/60,repeats:true){[weak self] _ in self?.tick()}; RunLoop.main.add(timer!,forMode:.common)
        NotificationCenter.default.addObserver(self,selector:#selector(screenChanged),name:NSApplication.didChangeScreenParametersNotification,object:nil)
        NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(screenChanged),name:NSWorkspace.willSleepNotification,object:nil)
        if !bool("welcomed",false) { permissions(); UserDefaults.standard.set(true,forKey:"welcomed") }
        if CommandLine.arguments.contains("--settings") { showSettings() }
    }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool { if !flag { showSettings() }; return true }
    func rebuild() {
        for window in windows { window.close() }; windows=[]
        for screen in NSScreen.screens {
            let window=Overlay(contentRect:screen.frame,styleMask:.borderless,backing:.buffered,defer:false)
            window.title="教學畫布 · " + screen.localizedName; window.setFrame(screen.frame,display:false); window.level = .init(rawValue:Int(CGWindowLevelForKey(.screenSaverWindow))); window.backgroundColor = .clear; window.isOpaque=false; window.hasShadow=false; window.ignoresMouseEvents=true; window.isReleasedWhenClosed=false
            window.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.stationary]
            let canvas=Canvas(frame:NSRect(origin:.zero,size:screen.frame.size)); canvas.owner=self; window.contentView=canvas; windows.append(window)
        }
    }
    @objc func screenChanged() { end(); rebuild() }
    @objc func toggleSpot() { spot.toggle() }
    @objc func freeze() {
        guard frozen==nil && !capturing else { return }
        guard CGPreflightScreenCaptureAccess() else { CGRequestScreenCaptureAccess(); permissions(); return }
        guard let screen=NSScreen.screens.first(where:{$0.frame.contains(NSEvent.mouseLocation)}),let id=screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32,let window=windows.first(where:{$0.frame==screen.frame}),let canvas=window.contentView as? Canvas else { return }
        previousApp=NSWorkspace.shared.frontmostApplication
        if previousApp?.processIdentifier==ProcessInfo.processInfo.processIdentifier { previousApp=nil }
        settings?.orderOut(nil)
        capturing=true; generation += 1; let token=generation; let capture=Capture(); self.capture=capture
        capture.start(displayID:id) { [weak self,weak window,weak canvas] result in
            guard let self,self.generation==token else { return }; self.capturing=false; self.capture=nil
            switch result {
            case .success(let image):
                guard let window,let canvas else { return }; canvas.snapshot=image; canvas.history.clear(); window.ignoresMouseEvents=false; NSApp.activate(ignoringOtherApps:true); window.makeKeyAndOrderFront(nil); window.makeFirstResponder(canvas); self.showToolbar(screen:screen)
            case .failure(let error): self.alert("無法凍結畫面",error.localizedDescription+"\n請到系統設定檢查螢幕錄製權限，再重新啟動工具。")
            }
        }
    }
    @objc func end() {
        generation += 1; capturing=false; capture?.finish(.failure(NSError(domain:"取消",code:0))); capture=nil
        spot=false; hold.cancel(); toolbar?.close(); toolbar=nil; colorPicker=nil
        for window in windows { if let canvas=window.contentView as? Canvas { canvas.snapshot=nil; canvas.history.clear(); canvas.live=nil; canvas.lasers=[]; canvas.needsDisplay=true }; window.ignoresMouseEvents=true }
        previousApp?.activate(options:[]); previousApp=nil
    }
    @objc func quit() { end(); NSApp.terminate(nil) }
    func tick() {
        if tap==nil && clockNow()-permissionCheckTime>2 { permissionCheckTime=clockNow(); if AXIsProcessTrusted() { installTap() } }
        if hold.tick(clockNow()) { end() }
        let mouse=NSEvent.mouseLocation
        for window in windows {
            guard let canvas=window.contentView as? Canvas else { continue }
            let point=localPoint(mouse,frame:window.frame)
            let lit=spot && window.frame.contains(mouse)
            let moving=(point != canvas.cursor) && (lit || bool("halo",false))
            let animate = !canvas.lasers.isEmpty || !canvas.ripples.isEmpty || hold.start != nil
            if moving || lit != canvas.spotlight || animate { canvas.needsDisplay=true }
            let visible=canvas.snapshot != nil || lit || (bool("halo",false) && window.frame.contains(mouse)) || !canvas.ripples.isEmpty || hold.start != nil
            if visible && !window.isVisible { window.orderFrontRegardless(); canvas.needsDisplay=true }
            if !visible && window.isVisible { window.orderOut(nil) }
            canvas.cursor=point; canvas.spotlight=lit
            canvas.lasers.removeAll{clockNow()-$0.born>1}; canvas.ripples.removeAll{clockNow()-$0.1>0.6}
        }
    }
    func installTap() {
        guard tap==nil else { return }
        let types:[CGEventType]=[.flagsChanged,.keyDown,.keyUp,.leftMouseDown,.rightMouseDown]
        let mask=types.reduce(CGEventMask(0)){$0 | (CGEventMask(1)<<$1.rawValue)}
        tap=CGEvent.tapCreate(tap:.cgSessionEventTap,place:.headInsertEventTap,options:.defaultTap,eventsOfInterest:mask,callback:{ _,type,event,info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let owner=Unmanaged<Controller>.fromOpaque(info).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { if let tap=owner.tap { CGEvent.tapEnable(tap:tap,enable:true) }; owner.hold.cancel(); owner.doubleTap.cancel(); return Unmanaged.passUnretained(event) }
            return owner.handle(type,event) ? nil : Unmanaged.passUnretained(event)
        },userInfo:Unmanaged.passUnretained(self).toOpaque())
        if let tap { tapSource=CFMachPortCreateRunLoopSource(kCFAllocatorDefault,tap,0); CFRunLoopAddSource(CFRunLoopGetMain(),tapSource,.commonModes); CGEvent.tapEnable(tap:tap,enable:true) }
    }
    func handle(_ type:CGEventType,_ event:CGEvent)->Bool {
        let key=event.getIntegerValueField(.keyboardEventKeycode); let flags=event.flags; let now=clockNow()
        if type == .flagsChanged {
            let clean=flags.intersection([.maskShift,.maskAlternate,.maskCommand]).isEmpty
            if doubleTap.update(pressed:flags.contains(.maskControl),clean:clean,time:now), !bool("disableDoubleControl",false) { toggleSpot() }
        }
        if type == .keyDown {
            _ = doubleTap.update(pressed:flags.contains(.maskControl),clean:false,time:now)
            if key==53 && (active || escapeConsumed) { if active { hold.press(now) }; escapeConsumed=true; return true }
            let mods=flags.intersection([.maskControl,.maskAlternate,.maskCommand,.maskShift])
            let desired:CGEventFlags = [.maskControl,.maskAlternate]
            if mods==desired && event.getIntegerValueField(.keyboardEventAutorepeat)==0 {
                let freezeKey=Int64(number("freezeKey",2)); let spotKey=Int64(number("spotKey",1))
                if key==freezeKey { DispatchQueue.main.async { self.freeze() }; return true }
                if key==spotKey { toggleSpot(); return true }
            }
            if let canvas=frozen {
                if key==6 && flags.contains(.maskCommand) { if flags.contains(.maskShift) { canvas.history.redo() } else { canvas.history.undo() }; canvas.needsDisplay=true; return true }
                let keys:[Int64]=[18,19,20,21,23]; if let index=keys.firstIndex(of:key),mods.isEmpty { colorIndex=index; updateToolbarSelection(); return true }
            }
        }
        if type == .keyUp && key==53 && (escapeConsumed || hold.start != nil || active) { escapeConsumed=false; hold.cancel(); windows.forEach { $0.contentView?.needsDisplay=true }; return true }
        if (type == .leftMouseDown || type == .rightMouseDown) && bool("ripples",true) && frozen==nil { let mouse=NSEvent.mouseLocation; for window in windows where window.frame.contains(mouse) { (window.contentView as? Canvas)?.ripples.append((localPoint(mouse,frame:window.frame),now)) } }
        return false
    }
    var colorPicker:NSPopUpButton?
    func updateToolbarSelection() { colorPicker?.selectItem(at:colorIndex) }
    func button(_ title:String,_ action:Selector)->NSButton { let b=NSButton(title:title,target:self,action:action); b.bezelStyle = .rounded; return b }
    func showToolbar(screen:NSScreen) {
        let panel=NSPanel(contentRect:NSRect(x:screen.frame.minX+20,y:screen.frame.maxY-125,width:710,height:72),styleMask:[.titled],backing:.buffered,defer:false); panel.title="畫面已凍結 · 長按 Esc 3 秒結束"; panel.level = .init(rawValue:Int(CGWindowLevelForKey(.screenSaverWindow))+1); panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]; panel.isReleasedWhenClosed=false
        let stack=NSStackView(); stack.orientation = .horizontal; stack.spacing=6; stack.translatesAutoresizingMaskIntoConstraints=false
        let tools=NSPopUpButton(); tools.addItems(withTitles:["畫筆","直線","箭頭","矩形","橢圓","雷射筆"]); tools.selectItem(at:tool); tools.target=self; tools.action=#selector(selectTool(_:)); stack.addArrangedSubview(tools)
        let colors=NSPopUpButton(); colors.addItems(withTitles:["🔴 紅 1","🔵 藍 2","🟢 綠 3","⚫ 黑 4","⚪ 白 5"]); colors.selectItem(at:colorIndex); colors.target=self; colors.action=#selector(selectColor(_:)); colorPicker=colors; stack.addArrangedSubview(colors)
        let width=NSPopUpButton(); width.addItems(withTitles:["細 2","中 4","粗 8","特粗 12"]); width.selectItem(at:[2.0,4,8,12].firstIndex(of:number("penWidth",4)) ?? 1); width.target=self; width.action=#selector(selectWidth(_:)); stack.addArrangedSubview(width)
        for (title,action) in [("↶",#selector(undo)),("↷",#selector(redo)),("清除全部",#selector(clear)),("聚光燈",#selector(toggleSpot)),("結束講解",#selector(end))] { stack.addArrangedSubview(button(title,action)) }
        panel.contentView!.addSubview(stack); NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo:panel.contentView!.centerXAnchor),stack.centerYAnchor.constraint(equalTo:panel.contentView!.centerYAnchor)]); toolbar=panel; panel.makeKeyAndOrderFront(nil)
    }
    @objc func selectTool(_ sender:NSPopUpButton) { tool=sender.indexOfSelectedItem }
    @objc func selectColor(_ sender:NSPopUpButton) { colorIndex=sender.indexOfSelectedItem }
    @objc func selectWidth(_ sender:NSPopUpButton) { UserDefaults.standard.set([2.0,4,8,12][sender.indexOfSelectedItem],forKey:"penWidth") }
    @objc func undo() { frozen?.history.undo(); frozen?.needsDisplay=true }
    @objc func redo() { frozen?.history.redo(); frozen?.needsDisplay=true }
    @objc func clear() { frozen?.history.clear(); frozen?.lasers=[]; frozen?.live=nil; frozen?.needsDisplay=true }
    func alert(_ title:String,_ body:String) { NSApp.activate(ignoringOtherApps:true); let alert=NSAlert(); alert.window.level = .init(rawValue:Int(CGWindowLevelForKey(.screenSaverWindow))+2); alert.messageText=title; alert.informativeText=body; alert.runModal() }
    @objc func permissions() {
        let alert=NSAlert(); alert.window.level = .init(rawValue:Int(CGWindowLevelForKey(.screenSaverWindow))+2); alert.messageText="教學聚光燈 · 使用與權限"; alert.informativeText="雙按 Control：聚光燈\nControl＋Option＋D：凍結畫面與畫筆\n長按 Esc 3 秒：清除並結束講解\n\n請在系統設定 → 隱私權與安全性，允許本工具使用『輔助使用』及『螢幕錄製』。取得畫面僅供本機凍結，不會儲存或上傳。\n\n凍結不會暫停背景影片。若快捷鍵無反應，請授權後重新啟動工具。\n輔助使用：\(AXIsProcessTrusted() ? "已允許" : "未允許")\n螢幕錄製：\(CGPreflightScreenCaptureAccess() ? "已允許" : "未允許")"; alert.addButton(withTitle:"開啟輔助使用設定"); alert.addButton(withTitle:"開啟螢幕錄製設定"); alert.addButton(withTitle:"關閉"); NSApp.activate(ignoringOtherApps:true)
        let result=alert.runModal(); if result == .alertFirstButtonReturn { NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!) } else if result == .alertSecondButtonReturn { NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!) }
    }
    @objc func showSettings() {
        if let settings { settings.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true); return }
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:480,height:550),styleMask:[.titled,.closable],backing:.buffered,defer:false); window.title="教學聚光燈設定"; window.level = .init(rawValue:Int(CGWindowLevelForKey(.screenSaverWindow))+2); window.isReleasedWhenClosed=false
        let stack=NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing=14; stack.translatesAutoresizingMaskIntoConstraints=false
        for (label,key,min,max,value) in [("聚光燈半徑","radius",40.0,400.0,120.0),("背景遮暗","dim",0.1,0.9,0.6),("外框粗細","borderWidth",1.0,10.0,3.0),("發光強度","glow",0.0,30.0,12.0)] {
            let slider=NSSlider(value:number(key,value),minValue:min,maxValue:max,target:self,action:#selector(slide(_:))); slider.identifier=NSUserInterfaceItemIdentifier(key); slider.widthAnchor.constraint(equalToConstant:260).isActive=true
            stack.addArrangedSubview(NSStackView(views:[NSTextField(labelWithString:label),slider]))
        }
        for (label,key,fallback) in [("螢光外框","border",true),("游標光圈","halo",false),("點擊波紋","ripples",true),("停用雙按 Control（改用快捷鍵）","disableDoubleControl",false)] { let b=NSButton(checkboxWithTitle:label,target:self,action:#selector(changeBool(_:))); b.identifier=NSUserInterfaceItemIdentifier(key); b.state=bool(key,fallback) ? .on:.off; stack.addArrangedSubview(b) }
        let colors=NSPopUpButton(); colors.addItems(withTitles:["青藍","黃","綠","粉紅","白"]); colors.selectItem(at:UserDefaults.standard.integer(forKey:"borderColor")); colors.target=self; colors.action=#selector(borderChanged(_:)); stack.addArrangedSubview(NSStackView(views:[NSTextField(labelWithString:"外框顏色"),colors]))
        for (label,key,fallback) in [("凍結快捷鍵","freezeKey",2.0),("聚光燈快捷鍵","spotKey",1.0)] { let popup=NSPopUpButton(); popup.addItems(withTitles:["Control＋Option＋D","Control＋Option＋S","Control＋Option＋F","Control＋Option＋G"]); popup.selectItem(at:[2.0,1,3,5].firstIndex(of:number(key,fallback)) ?? 0); popup.identifier=NSUserInterfaceItemIdentifier(key); popup.target=self; popup.action=#selector(shortcutChanged(_:)); stack.addArrangedSubview(NSStackView(views:[NSTextField(labelWithString:label),popup])) }
        stack.addArrangedSubview(NSStackView(views:[button("試用聚光燈",#selector(toggleSpot)),button("凍結並畫圖",#selector(freeze)),button("權限說明",#selector(permissions))]))
        stack.addArrangedSubview(NSTextField(wrappingLabelWithString:"設定立即生效並儲存。長按 Esc 3 秒結束講解；工具列也可直接結束。"))
        window.contentView!.addSubview(stack); NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:window.contentView!.leadingAnchor,constant:24),stack.trailingAnchor.constraint(equalTo:window.contentView!.trailingAnchor,constant:-24),stack.topAnchor.constraint(equalTo:window.contentView!.topAnchor,constant:24)]); settings=window; window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
    }
    func captureChecks() {
        let screens=NSScreen.screens
        var index=0
        func next() {
            guard index<screens.count else { print("PASS: live capture on \(screens.count) displays; no images saved"); NSApp.terminate(nil); return }
            let screen=screens[index]; index += 1
            guard let id=screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 else { fatalError("display ID") }
            let service=Capture(); self.capture=service; let start=clockNow()
            service.start(displayID:id) { result in
                switch result {
                case .success(let image):
                    guard image.width==(CGDisplayCopyDisplayMode(id)?.pixelWidth ?? CGDisplayPixelsWide(id)),image.height==(CGDisplayCopyDisplayMode(id)?.pixelHeight ?? CGDisplayPixelsHigh(id)) else { fatalError("capture dimensions") }
                    print("PASS: \(screen.localizedName) pixels=\(image.width)x\(image.height) elapsed=\(clockNow()-start)s")
                    self.capture=nil; DispatchQueue.main.async { next() }
                case .failure(let error): print("FAIL: live capture \(error)"); exit(1)
                }
            }
        }
        next()
    }
    func renderChecks() {
        let canvas=Canvas(frame:NSRect(x:0,y:0,width:800,height:600)); canvas.owner=self
        var checks=0
        func verify(_ condition:Bool,_ label:String) { guard condition else { fatalError("FAIL: " + label) }; checks += 1; print("PASS: " + label) }
        guard let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:800,pixelsHigh:600,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),let graphics=NSGraphicsContext(bitmapImageRep:rep) else { fatalError("bitmap allocation") }
        func render() { NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current=graphics; canvas.draw(canvas.bounds); graphics.flushGraphics(); NSGraphicsContext.restoreGraphicsState() }
        for kind in 0...5 {
            for color in palette {
                canvas.history.clear()
                canvas.history.add(Stroke(points:[CGPoint(x:100,y:100),CGPoint(x:300,y:300)],color:color,width:4,tool:kind,born:clockNow()))
                render()
                var pixels=0
                for y in stride(from:0,to:600,by:2) { for x in stride(from:0,to:800,by:2) { if (rep.colorAt(x:x,y:y)?.alphaComponent ?? 0)>0.1 { pixels += 1 } } }
                verify(pixels>0,"render tool \(kind) color \(color.description)")
            }
        }
        canvas.history.clear(); canvas.cursor=CGPoint(x:400,y:300); canvas.spotlight=true
        render()
        verify((rep.colorAt(x:400,y:300)?.alphaComponent ?? 1)<0.01,"spotlight center transparent")
        verify(abs((rep.colorAt(x:20,y:20)?.alphaComponent ?? 0)-0.6)<0.02,"spotlight dim 60 percent")
        verify((rep.colorAt(x:520,y:300)?.alphaComponent ?? 0)>0.2,"fluorescent border rendered")
        canvas.spotlight=false
        for _ in 0..<100 {
            canvas.snapshot=rep.cgImage
            canvas.history.add(Stroke(points:[CGPoint(x:100,y:100)],color:.red,width:4,tool:0,born:clockNow()))
            canvas.snapshot=nil; canvas.history.clear()
        }
        verify(canvas.snapshot==nil && canvas.history.items.isEmpty,"100 synthetic canvas reset cycles")
        print("\(checks) rendering checks passed; synthetic only, not live capture")
        NSApp.terminate(nil)
    }
    @objc func slide(_ sender:NSSlider) { UserDefaults.standard.set(sender.doubleValue,forKey:sender.identifier!.rawValue); windows.forEach { $0.contentView?.needsDisplay=true } }
    @objc func changeBool(_ sender:NSButton) { UserDefaults.standard.set(sender.state == .on,forKey:sender.identifier!.rawValue); windows.forEach { $0.contentView?.needsDisplay=true } }
    @objc func borderChanged(_ sender:NSPopUpButton) { UserDefaults.standard.set(sender.indexOfSelectedItem,forKey:"borderColor"); windows.forEach { $0.contentView?.needsDisplay=true } }
    @objc func shortcutChanged(_ sender:NSPopUpButton) {
        let key=sender.identifier!.rawValue; let other=key=="freezeKey" ? "spotKey":"freezeKey"; let value=[2.0,1,3,5][sender.indexOfSelectedItem]
        if value==number(other,other=="freezeKey" ? 2:1) { sender.selectItem(at:[2.0,1,3,5].firstIndex(of:number(key,key=="freezeKey" ? 2:1)) ?? 0); alert("快捷鍵重複","請為聚光燈與凍結選擇不同的快捷鍵。") } else { UserDefaults.standard.set(value,forKey:key) }
    }
}
let app=NSApplication.shared
let controller=Controller()
app.delegate=controller
app.run()
