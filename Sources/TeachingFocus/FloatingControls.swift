import AppKit
import FocusCore

final class FloatingWindow:NSPanel {
    override var canBecomeKey:Bool { true }
    override var canBecomeMain:Bool { false }
}
final class FloatingBallView:NSView {
    weak var controls:FloatingControls?
    private var press:CGPoint?
    private var startOrigin=CGPoint.zero
    private var dragged=false
    override func accessibilityPerformPress() -> Bool { controls?.toggle(); return controls != nil }
    override func draw(_ dirtyRect:NSRect) {
        NSColor.white.withAlphaComponent(0.96).setFill()
        let circle=NSBezierPath(ovalIn:bounds.insetBy(dx:1,dy:1)); circle.fill()
        (controls?.owner?.borderColor ?? NSColor.systemCyan).setStroke(); circle.lineWidth=2; circle.stroke()
        teachingMenuIcon().draw(in:NSRect(x:11,y:13,width:22,height:18))
        if controls?.expanded == true { NSColor.systemCyan.setFill(); NSBezierPath(ovalIn:NSRect(x:19,y:5,width:6,height:3)).fill() }
    }
    override func mouseDown(with event:NSEvent) {
        guard let controls else { return }; press=NSEvent.mouseLocation; startOrigin=controls.ball.frame.origin; dragged=false
    }
    override func mouseDragged(with event:NSEvent) {
        guard let press, let controls else { return }
        let point=NSEvent.mouseLocation
        if FloatingLayout.isDrag(from:press,to:point) { dragged=true }
        if dragged { controls.moveBall(to:CGPoint(x:startOrigin.x+point.x-press.x,y:startOrigin.y+point.y-press.y)) }
    }
    override func mouseUp(with event:NSEvent) {
        guard let press, let controls else { return }
        let point=NSEvent.mouseLocation
        if dragged || FloatingLayout.isDrag(from:press,to:point) {
            controls.moveBall(to:CGPoint(x:startOrigin.x+point.x-press.x,y:startOrigin.y+point.y-press.y)); controls.finishDrag()
        } else { controls.toggle() }
        self.press=nil; dragged=false
    }
}

final class FloatingControls:NSObject {
    weak var owner:Controller?
    let screenFrame:CGRect
    let displayKey:String
    let ball:FloatingWindow
    let panel:FloatingWindow
    let ballView:FloatingBallView
    private(set) var expanded=false
    private var toolButtons:[NSButton]=[]
    private var colorButtons:[NSButton]=[]
    private var widthControl:NSSegmentedControl!
    private var hint:NSTextField!
    private var spotlightButton:NSButton!
    init(owner:Controller,screenFrame:CGRect,displayKey:String) {
        self.owner=owner; self.screenFrame=screenFrame; self.displayKey=displayKey
        let saved=(owner.preferences.dictionary(forKey:"floatingPositions")?[displayKey] as? [String:Double]) ?? [:]
        let frame=FloatingLayout.ball(in:screenFrame,right:(saved["right"] ?? 1)>0.5,fraction:saved["fraction"] ?? 0.5)
        ball=FloatingWindow(contentRect:frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel=FloatingWindow(contentRect:FloatingLayout.panel(beside:frame,in:screenFrame),styleMask:[.borderless],backing:.buffered,defer:false)
        ballView=FloatingBallView(frame:NSRect(origin:.zero,size:frame.size))
        super.init()
        for (window,offset) in [(ball,3),(panel,2)] {
            window.isOpaque=false; window.backgroundColor = .clear; window.hasShadow=true; window.isReleasedWhenClosed=false
            window.level = .init(rawValue:Int(CGWindowLevelForKey(.screenSaverWindow))+offset)
            window.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.stationary]
        }
        ball.title="講解工具懸浮球"; panel.title="講解工具"
        ballView.controls=self; ballView.setAccessibilityElement(true); ballView.setAccessibilityRole(.button); ballView.setAccessibilityLabel("講解工具：點擊展開，拖曳移動")
        ball.contentView=ballView
        buildPanel()
        if !owner.testMode { ball.orderFrontRegardless() }
    }
    private func buildPanel() {
        guard let owner else { return }
        let background=NSVisualEffectView(frame:NSRect(origin:.zero,size:panel.frame.size)); background.material = .popover; background.blendingMode = .behindWindow; background.state = .active; background.wantsLayer=true; background.layer?.cornerRadius=14; background.layer?.masksToBounds=true
        panel.contentView=background
        let stack=NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing=8; stack.translatesAutoresizingMaskIntoConstraints=false
        background.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:background.leadingAnchor,constant:16),stack.trailingAnchor.constraint(equalTo:background.trailingAnchor,constant:-16),stack.topAnchor.constraint(equalTo:background.topAnchor,constant:14)])
        func row(_ controls:[NSView]) {
            let row=NSStackView(views:controls); row.spacing=6; row.distribution = .fillEqually; stack.addArrangedSubview(row); row.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true
        }
        let title=NSTextField(labelWithString:"畫面已凍結"); title.font = .systemFont(ofSize:12,weight:.semibold)
        let collapse=NSButton(title:"收起",target:self,action:#selector(collapseAction)); collapse.bezelStyle = .rounded
        row([title,collapse])
        for (index,name) in ["畫筆","直線","箭頭","矩形","橢圓","雷射筆"].enumerated() {
            let button=NSButton(title:name,target:self,action:#selector(selectTool(_:))); button.bezelStyle = .rounded; button.setButtonType(.pushOnPushOff); button.tag=index; toolButtons.append(button)
        }
        row(Array(toolButtons[0..<3])); row(Array(toolButtons[3..<6]))
        for (index,name) in ["紅","藍","綠","黑","白"].enumerated() {
            let button=NSButton(title:name,target:self,action:#selector(selectColor(_:))); button.bezelStyle = .rounded; button.setButtonType(.pushOnPushOff); button.tag=index
            let color=palette[index]
            button.image=NSImage(size:NSSize(width:10,height:10),flipped:false) { _ in color.setFill(); let dot=NSBezierPath(ovalIn:NSRect(x:1,y:1,width:8,height:8)); dot.fill(); NSColor.gray.setStroke(); dot.lineWidth=0.5; dot.stroke(); return true }
            button.imagePosition = .imageLeading; colorButtons.append(button)
        }
        row(colorButtons)
        widthControl=NSSegmentedControl(labels:["2","4","8","12"],trackingMode:.selectOne,target:self,action:#selector(selectWidth(_:)))
        let widthLabel=NSTextField(labelWithString:"粗細"); widthLabel.font = .systemFont(ofSize:12)
        row([widthLabel,widthControl])
        row([owner.button("復原",#selector(Controller.undo)),owner.button("重做",#selector(Controller.redo)),owner.button("清除",#selector(Controller.clear))])
        spotlightButton=owner.button("聚光燈",#selector(Controller.toggleSpot)); spotlightButton.setButtonType(.pushOnPushOff)
        row([spotlightButton,owner.button("結束講解",#selector(Controller.end))])
        hint=NSTextField(labelWithString:""); hint.font = .systemFont(ofSize:11); hint.textColor = .secondaryLabelColor; stack.addArrangedSubview(hint)
        background.layoutSubtreeIfNeeded()
        let size=NSSize(width:320,height:stack.fittingSize.height+28)
        panel.setFrame(FloatingLayout.panel(beside:ball.frame,in:screenFrame,height:size.height),display:false)
        sync()
    }
    func sync() {
        guard let owner else { return }
        for button in toolButtons { button.state=button.tag==owner.tool ? .on:.off }
        for button in colorButtons { button.state=button.tag==owner.colorIndex ? .on:.off }
        widthControl.selectedSegment=[2.0,4,8,12].firstIndex(of:owner.number("penWidth",4)) ?? 1
        spotlightButton.state=owner.spot ? .on:.off
        hint.stringValue="長按 Esc \(owner.holdDurationText) 秒結束講解"
        ballView.needsDisplay=true
    }
    func contains(_ point:CGPoint) -> Bool { ball.frame.contains(point) || (expanded && panel.frame.contains(point)) }
    func toggle() { if expanded { collapse() } else { expand() } }
    func expand() {
        guard let owner, !owner.paused, owner.frozen != nil else { return }
        sync(); panel.setFrame(FloatingLayout.panel(beside:ball.frame,in:screenFrame,height:panel.frame.height),display:false); expanded=true
        if !owner.testMode { panel.makeKeyAndOrderFront(nil); ball.orderFrontRegardless() }
        owner.updateFloatingShields(); ballView.needsDisplay=true
    }
    func collapse() {
        expanded=false; panel.orderOut(nil); owner?.updateFloatingShields(); ballView.needsDisplay=true
        if owner?.testMode == false, let canvas=owner?.frozen { canvas.window?.makeKey(); canvas.window?.makeFirstResponder(canvas) }
    }
    @objc private func collapseAction() { collapse() }
    func moveBall(to origin:CGPoint) { if expanded { collapse() }; ball.setFrame(FloatingLayout.clamped(origin:origin,in:screenFrame),display:false) }
    func finishDrag() {
        let result=FloatingLayout.snapped(ball.frame,in:screenFrame); ball.setFrame(result.frame,display:false)
        guard let owner else { return }
        var positions=owner.preferences.dictionary(forKey:"floatingPositions") ?? [:]
        positions[displayKey]=["right":result.right ? 1.0:0.0,"fraction":result.fraction]
        owner.preferences.set(positions,forKey:"floatingPositions")
    }
    func close() { expanded=false; panel.close(); ball.close() }
    @objc private func selectTool(_ sender:NSButton) { owner?.tool=sender.tag; sync() }
    @objc private func selectColor(_ sender:NSButton) { owner?.colorIndex=sender.tag; sync() }
    @objc private func selectWidth(_ sender:NSSegmentedControl) { guard sender.selectedSegment>=0 else { return }; owner?.preferences.set([2.0,4,8,12][sender.selectedSegment],forKey:"penWidth"); sync() }
}

extension Controller {
    func showFloatingTools(screen:NSScreen) {
        guard !paused && frozen != nil else { return }
        floatingControls?.close()
        let id=screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 ?? 0
        let key=CGDisplayCreateUUIDFromDisplayID(id).map { CFUUIDCreateString(nil,$0.takeRetainedValue()) as String } ?? "display-\(id)"
        floatingControls=FloatingControls(owner:self,screenFrame:screen.frame,displayKey:key)
    }
    func updateFloatingShields() {
        let expanded=floatingControls?.expanded == true
        for window in windows {
            window.ignoresMouseEvents = !expanded && (window.contentView as? Canvas)?.snapshot == nil
            if expanded && !testMode { window.orderFrontRegardless() }
        }
        if expanded && !testMode { floatingControls?.panel.orderFrontRegardless(); floatingControls?.ball.orderFrontRegardless() }
    }
    @discardableResult func dismissFloatingPanel() -> Bool {
        guard floatingControls?.expanded == true else { return false }
        floatingControls?.collapse(); return true
    }
    func ownControlContains(_ point:CGPoint) -> Bool {
        if floatingControls?.contains(point) == true { return true }
        for window in [settings,recorderPanel] { if let window,window.isVisible,window.frame.contains(point) { return true } }
        if NSColorPanel.sharedColorPanelExists && NSColorPanel.shared.isVisible && NSColorPanel.shared.frame.contains(point) { return true }
        return false
    }
}
