import AppKit
import FocusCore

func drawParticles(_ buffer: ParticleBuffer, color:NSColor, at time:Double) {
    for burst in buffer.bursts {
        for sample in burst.samples(at:time) {
            color.withAlphaComponent(sample.opacity).setFill()
            color.withAlphaComponent(sample.opacity).setStroke()
            switch burst.kind {
            case .dots:
                NSBezierPath(ovalIn:NSRect(x:sample.point.x-sample.size,y:sample.point.y-sample.size,width:sample.size*2,height:sample.size*2)).fill()
            case .sparks:
                let path=NSBezierPath(); path.lineWidth=1.8; path.lineCapStyle = .round
                path.move(to:sample.point)
                path.line(to:CGPoint(x:sample.point.x-cos(sample.angle)*sample.size*3,y:sample.point.y-sin(sample.angle)*sample.size*3)); path.stroke()
            case .stars:
                let path=NSBezierPath()
                for index in 0..<8 {
                    let angle=sample.angle+Double(index)*Double.pi/4
                    let radius=sample.size*(index%2==0 ? 1.8:0.5)
                    let point=CGPoint(x:sample.point.x+cos(angle)*radius,y:sample.point.y+sin(angle)*radius)
                    if index==0 { path.move(to:point) } else { path.line(to:point) }
                }
                path.close(); path.fill()
            }
        }
    }
}
final class ParticlePreview: NSView {
    weak var owner:Controller?
    var buffer=ParticleBuffer()
    private var timer:Timer?
    init(owner:Controller) { self.owner=owner; super.init(frame:NSRect(x:0,y:0,width:140,height:76)); setAccessibilityLabel("點擊預覽粒子特效") }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override var intrinsicContentSize:NSSize { NSSize(width:140,height:76) }
    override func mouseDown(with event:NSEvent) { play() }
    func play() {
        guard let owner else { return }
        buffer.add(ParticleBurst(origin:CGPoint(x:bounds.midX,y:bounds.midY),born:clockNow(),kind:owner.particleKind,intensity:owner.particleIntensity),reducedMotion:owner.reduceMotion)
        needsDisplay=true
        guard !buffer.bursts.isEmpty else { return }
        timer?.invalidate()
        let timer=Timer(timeInterval:1.0/60,repeats:true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            if self.owner?.reduceMotion == true { self.buffer.clear() } else { self.buffer.expire(at:clockNow()) }; self.needsDisplay=true
            if self.buffer.bursts.isEmpty { timer.invalidate(); self.timer=nil }
        }
        self.timer=timer; RunLoop.main.add(timer,forMode:.common)
    }
    func clear() { timer?.invalidate(); timer=nil; buffer.clear(); needsDisplay=true }
    override func draw(_ dirtyRect:NSRect) {
        NSColor(white:0.14,alpha:1).setFill(); NSBezierPath(roundedRect:bounds,xRadius:10,yRadius:10).fill()
        if buffer.bursts.isEmpty {
            let label=(owner?.reduceMotion == true ? "已減少動態效果":"點擊預覽") as NSString
            let attributes:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:11),.foregroundColor:NSColor.white.withAlphaComponent(0.8)]
            let size=label.size(withAttributes:attributes); label.draw(at:NSPoint(x:(bounds.width-size.width)/2,y:(bounds.height-size.height)/2),withAttributes:attributes)
        }
        drawParticles(buffer,color:owner?.borderColor ?? .systemCyan,at:clockNow())
    }
    deinit { timer?.invalidate() }
}

extension Controller {
    @objc func previewEntrance() { effectPreviews.first(where:{ !$0.halo })?.playAnimation() }
    @objc func selectParticleKind(_ sender:NSPopUpButton) {
        preferences.set(sender.indexOfSelectedItem,forKey:"particleKind"); particlePreview?.play()
    }
    func particleControls() -> NSView {
        let enable=NSButton(checkboxWithTitle:"點擊粒子",target:self,action:#selector(changeBool(_:)))
        enable.identifier=NSUserInterfaceItemIdentifier("particles"); enable.state=bool("particles",false) ? .on:.off; enable.widthAnchor.constraint(equalToConstant:130).isActive=true
        let kinds=NSPopUpButton(); kinds.addItems(withTitles:["光點擴散","短線火花","小星芒"]); kinds.selectItem(at:particleKind.rawValue); kinds.target=self; kinds.action=#selector(selectParticleKind(_:)); kinds.widthAnchor.constraint(equalToConstant:168).isActive=true
        let label=NSTextField(labelWithString:"強度 \(particleIntensity)"); label.font = .systemFont(ofSize:11); particleIntensityLabel=label
        let intensity=NSSlider(value:Double(particleIntensity),minValue:1,maxValue:5,target:self,action:#selector(slide(_:))); intensity.identifier=NSUserInterfaceItemIdentifier("particleIntensity"); intensity.numberOfTickMarks=5; intensity.allowsTickMarkValuesOnly=true; intensity.widthAnchor.constraint(equalToConstant:110).isActive=true
        let adjustment=NSStackView(views:[label,intensity]); adjustment.spacing=6
        let options=NSStackView(views:[kinds,adjustment]); options.orientation = .vertical; options.alignment = .leading; options.spacing=6
        let preview=ParticlePreview(owner:self); preview.widthAnchor.constraint(equalToConstant:140).isActive=true; preview.heightAnchor.constraint(equalToConstant:76).isActive=true; particlePreview=preview
        let row=NSStackView(views:[enable,options,preview]); row.spacing=10; return row
    }
}


extension Controller {
    func emitParticles(on canvas:Canvas,point:CGPoint,time:Double) {
        guard !paused && frozen == nil && !capturing else { return }
        canvas.particles.add(ParticleBurst(origin:point,born:time,kind:particleKind,intensity:particleIntensity),reducedMotion:reduceMotion)
        let canvases=windows.compactMap { $0.contentView as? Canvas }
        for view in canvases { view.particles.expire(at:time) }
        while canvases.reduce(0, { $0 + $1.particles.bursts.count }) > 8 {
            guard let oldest=canvases.filter({ !$0.particles.bursts.isEmpty }).min(by:{ $0.particles.bursts[0].born < $1.particles.bursts[0].born }) else { break }
            oldest.particles.removeOldest(); oldest.needsDisplay=true
        }
    }
}
