import AppKit

final class PreviewColorWell: NSColorWell {
    override func activate(_ exclusive: Bool) {
        NSColorPanel.shared.level = .init(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 4)
        NSColorPanel.shared.showsAlpha = false
        super.activate(exclusive)
    }
}

final class FlippedDocument: NSView { override var isFlipped: Bool { true } }

final class EffectPreview: NSView {
    weak var owner: Controller?
    let halo: Bool
    init(owner: Controller, halo: Bool) { self.owner=owner; self.halo=halo; super.init(frame:NSRect(x:0,y:0,width:240,height:76)) }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override var intrinsicContentSize:NSSize { NSSize(width:240,height:76) }
    override func draw(_ dirtyRect:NSRect) {
        guard let owner else { return }
        let rounded=NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:1),xRadius:10,yRadius:10)
        NSGraphicsContext.saveGraphicsState(); rounded.addClip()
        NSColor(white:0.94,alpha:1).setFill(); bounds.fill()
        NSColor(white:0.15,alpha:1).setFill(); NSRect(x:bounds.midX,y:0,width:bounds.width/2,height:bounds.height).fill()
        let center=CGPoint(x:bounds.midX,y:bounds.midY)
        let radius=halo ? min(33, owner.haloRadius * 0.7) : 25
        let circle=NSBezierPath(ovalIn:NSRect(x:center.x-radius,y:center.y-radius,width:radius*2,height:radius*2))
        if halo { owner.haloColor.withAlphaComponent(0.35).setFill(); circle.fill() }
        else {
            let shadow=NSShadow(); shadow.shadowColor=owner.borderColor; shadow.shadowBlurRadius=min(14,owner.number("glow",12)); shadow.set()
            owner.borderColor.setStroke(); circle.lineWidth=owner.number("borderWidth",3); circle.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        NSColor.separatorColor.setStroke(); rounded.lineWidth=1; rounded.stroke()
        let arrow=NSBezierPath(); arrow.move(to:CGPoint(x:center.x-5,y:center.y+9)); arrow.line(to:CGPoint(x:center.x+8,y:center.y)); arrow.line(to:CGPoint(x:center.x+1,y:center.y-1)); arrow.line(to:CGPoint(x:center.x-4,y:center.y-8)); arrow.close()
        NSColor.white.setFill(); arrow.fill(); NSColor.black.setStroke(); arrow.lineWidth=1; arrow.stroke()
    }
}

func teachingMenuIcon() -> NSImage {
    let image=NSImage(size:NSSize(width:22,height:18),flipped:false) { _ in
        NSColor.black.setStroke()
        for inset:CGFloat in [1,4] {
            let ring=NSBezierPath(ovalIn:NSRect(x:inset,y:inset,width:18-inset*2,height:18-inset*2)); ring.lineWidth=1.2; ring.stroke()
        }
        let arrow=NSBezierPath()
        arrow.move(to:NSPoint(x:9,y:13)); arrow.line(to:NSPoint(x:19,y:7)); arrow.line(to:NSPoint(x:15,y:6)); arrow.line(to:NSPoint(x:13,y:1)); arrow.line(to:NSPoint(x:11,y:2)); arrow.line(to:NSPoint(x:13,y:7)); arrow.line(to:NSPoint(x:9,y:6)); arrow.close()
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current?.cgContext.setBlendMode(.clear); arrow.lineWidth=2.7; arrow.stroke(); NSGraphicsContext.restoreGraphicsState()
        NSColor.black.setFill(); arrow.fill()
        return true
    }
    image.isTemplate=true
    image.accessibilityDescription="教學聚光燈"
    return image
}

extension Controller {
    func color(_ key:String, fallback:NSColor) -> NSColor {
        guard let values=preferences.array(forKey:key) as? [Double], values.count==3, values.allSatisfy({$0.isFinite && $0>=0 && $0<=1}) else { return fallback }
        return NSColor(srgbRed:values[0],green:values[1],blue:values[2],alpha:1)
    }
    @objc func colorChanged(_ sender:NSColorWell) {
        guard let key=sender.identifier?.rawValue, let selected=sender.color.usingColorSpace(.sRGB) else { return }
        preferences.set([selected.redComponent,selected.greenComponent,selected.blueComponent],forKey:key)
        effectPreviews.forEach { $0.needsDisplay=true }
        windows.forEach { $0.contentView?.needsDisplay=true }
    }
    func colorControls(title:String,key:String,selected:NSColor,halo:Bool) -> NSView {
        let well=PreviewColorWell(frame:NSRect(x:0,y:0,width:48,height:28)); well.color=selected; well.identifier=NSUserInterfaceItemIdentifier(key); well.target=self; well.action=#selector(colorChanged(_:)); well.setAccessibilityLabel(title)
        well.widthAnchor.constraint(equalToConstant:48).isActive=true; well.heightAnchor.constraint(equalToConstant:28).isActive=true
        let preview=EffectPreview(owner:self,halo:halo); effectPreviews.append(preview)
        preview.widthAnchor.constraint(equalToConstant:240).isActive=true; preview.heightAnchor.constraint(equalToConstant:76).isActive=true
        let row=NSStackView(views:[NSTextField(labelWithString:title),well,preview]); row.spacing=12
        return row
    }
    func resizeSettingsDocument() {
        guard let scroll=settingsScroll, let stack=settingsStack, let document=scroll.documentView else { return }
        document.setFrameSize(NSSize(width:scroll.contentSize.width,height:max(scroll.contentSize.height,stack.fittingSize.height+48)))
    }
}


extension Controller {
    @objc func confirmResetSettings() {
        let prompt=NSAlert()
        prompt.messageText="還原預設設定？"
        prompt.informativeText="將還原顏色、大小、效果開關、快捷鍵及 Esc 長按時間，並結束目前講解、清除畫布。暫停狀態與 macOS 權限不會變更。"
        prompt.addButton(withTitle:"還原設定"); prompt.addButton(withTitle:"取消")
        prompt.window.level = .init(rawValue:Int(CGWindowLevelForKey(.screenSaverWindow))+4)
        if prompt.runModal() == .alertFirstButtonReturn { restoreDefaultSettings() }
    }
    func restoreDefaultSettings() {
        recorderPanel?.close(); end(); doubleTap.cancel(); hold.cancel(); escape.reset()
        let keys=["radius","dim","borderWidth","glow","border","spotAnimation","halo","ripples","disableDoubleControl","borderColor","borderColorRGB","haloColorRGB","haloRadius","freezeKey","spotKey","freezeKeyModifiers","spotKeyModifiers","holdSeconds","penWidth"]
        for key in keys { preferences.removeObject(forKey:key) }
        tool=0; colorIndex=0
        NSColorPanel.shared.orderOut(nil)
        settings?.close(); settings=nil; settingsScroll=nil; settingsStack=nil
        effectPreviews.removeAll(); shortcutLabels.removeAll()
        pauseButton=nil; inputStatusLabel=nil; holdLabel=nil; haloSizeLabel=nil; instructionsLabel=nil
        registerSavedShortcuts(); showSettings(); refreshStatus()
        windows.forEach { $0.contentView?.needsDisplay=true }
    }
}
