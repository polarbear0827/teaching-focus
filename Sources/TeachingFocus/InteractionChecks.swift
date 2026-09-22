import AppKit
import FocusCore

extension Controller {
    func interactionChecks() {
        testMode = true
        let suite = "tw.teachingfocus.checks." + UUID().uuidString
        preferences = UserDefaults(suiteName:suite)!
        var checks=0
        func check(_ condition:Bool,_ label:String) { guard condition else { fatalError("FAIL: " + label) }; checks += 1; print("PASS: " + label) }
        func event(_ code:UInt16,_ flags:NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:flags,timestamp:0,windowNumber:0,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:code)!
        }
        let mods=Shortcut.control | Shortcut.option | Shortcut.shift | Shortcut.command
        preferences.set(79.0,forKey:"freezeKey"); preferences.set(80.0,forKey:"spotKey")
        preferences.set(Double(mods),forKey:"freezeKeyModifiers"); preferences.set(Double(mods),forKey:"spotKeyModifiers")
        preferences.set(true,forKey:"halo"); preferences.set(true,forKey:"ripples")
        let esc=CGEvent(keyboardEventSource:nil,virtualKey:53,keyDown:true)!
        check(!handle(.keyDown,esc), "halo and ripples do not capture idle Escape")
        spot=true; check(handle(.keyDown,esc) && hold.start != nil, "active spotlight begins Escape hold")
        end(); check(handle(.keyDown,esc) && hold.start == nil, "repeat after ending stays suppressed without new countdown")
        check(handle(.keyUp,esc), "release of consumed Escape is suppressed")
        check(!handle(.keyDown,esc), "new Escape after ending passes through")
        spot=true; togglePause()
        check(paused && !active && !spot && hold.start == nil, "pause clears lesson and hold")
        check(!handle(.keyDown,esc), "paused app does not intercept Escape")
        toggleSpot(); check(!spot, "spotlight cannot activate while paused")
        togglePause(); check(!paused && !spot, "resume starts with no stale spotlight")
        shortcutRouter=ShortcutRouter(); registerSavedShortcuts()
        check(shortcutRouter?.error == nil, "native shortcut registration succeeds")
        let competing=ShortcutRouter()
        check(competing.register(savedBindings()) != nil, "OS detects shortcut already registered by another router")
        let original=binding("freezeKey")
        beginRecording("freezeKey")
        check(!handle(.keyDown,esc), "global input handling suspended while recording")
        recordKey(event(2)); check(recordingCandidate == nil, "plain key rejected in recorder")
        recordKey(event(80,[.control,.option,.shift,.command])); check(recordingCandidate == nil, "other action duplicate rejected")
        recordKey(event(98,[.control,.option,.shift,.command])); check(recordingCandidate?.key == 98, "recorder captures custom key and modifiers")
        cancelRecording(); check(binding("freezeKey") == original, "cancel preserves previous shortcut")
        beginRecording("freezeKey"); recordKey(event(98,[.control,.option,.shift,.command])); saveRecording()
        check(binding("freezeKey").key == 98 && recordingAction == nil, "save persists custom shortcut")
        let registered=binding("freezeKey")
        beginRecording("freezeKey"); recordKey(event(99,[.control,.option,.shift,.command]))
        let blocker=ShortcutRouter()
        check(blocker.register(["freezeKey":Shortcut(key:99,modifiers:mods)]) == nil, "reserve conflicting candidate")
        saveRecording(); check(binding("freezeKey") == registered && recordingAction != nil, "OS conflict leaves saved binding unchanged and recorder open")
        blocker.unregister(); cancelRecording()
        beginRecording("freezeKey"); recordKey(event(53)); check(recordingAction == nil && binding("freezeKey") == registered, "Escape cancels recorder")
        let duration=NSSlider(value:1.5,minValue:0.5,maxValue:10,target:nil,action:nil)
        duration.identifier=NSUserInterfaceItemIdentifier("holdSeconds"); slide(duration)
        check(holdDuration == 1.5, "hold duration setting persists")
        togglePause(); beginRecording("freezeKey"); recordKey(event(100,[.control,.option,.shift,.command])); saveRecording()
        check(paused && binding("freezeKey").key == 100, "recording while paused saves without resuming")
        check(competing.register(savedBindings()) == nil, "paused saved shortcuts are not left registered")
        competing.unregister(); shortcutRouter?.unregister()
        showSettings(); settings?.contentView?.layoutSubtreeIfNeeded()
        check(holdLabel?.stringValue.contains("1.5") == true, "settings displays configured hold time")
        check(shortcutLabels["freezeKey"]?.stringValue == shortcutLabel(binding("freezeKey")), "settings displays recorded shortcut")
        func findWell(_ view:NSView) -> NSColorWell? {
            if let well=view as? NSColorWell { return well }
            return view.subviews.compactMap { findWell($0) }.first
        }
        let well=findWell(effectPreviews[1].superview!)!; well.color=NSColor(srgbRed:0.2,green:0.5,blue:0.8,alpha:1); colorChanged(well)
        check(abs((haloColor.usingColorSpace(.sRGB)?.blueComponent ?? 0)-0.8)<0.001, "halo custom color persists")
        let borderWell=findWell(effectPreviews[0].superview!)!; borderWell.color=NSColor(srgbRed:0.9,green:0.1,blue:0.3,alpha:1); colorChanged(borderWell)
        check(abs((borderColor.usingColorSpace(.sRGB)?.redComponent ?? 0)-0.9)<0.001, "border custom color persists")
        let haloSlider=NSSlider(value:42,minValue:6,maxValue:80,target:nil,action:nil); haloSlider.identifier=NSUserInterfaceItemIdentifier("haloRadius"); slide(haloSlider)
        check(haloRadius==42 && haloSizeLabel?.stringValue.contains("42")==true, "halo radius setting and label update")
        check(teachingMenuIcon().isTemplate && teachingMenuIcon().size.width==22, "menu icon supports system light and dark appearance")
        check(effectPreviews.count==2, "both effect color previews are present")
        let opacity=NSSlider(value:0.7,minValue:0,maxValue:1,target:nil,action:nil); opacity.identifier=NSUserInterfaceItemIdentifier("haloOpacity"); slide(opacity)
        check(haloOpacity==0.7 && haloOpacityLabel?.stringValue.contains("70%") == true, "halo opacity updates stored value and preview label")
        let animation=NSSlider(value:0.8,minValue:0.1,maxValue:1,target:nil,action:nil); animation.identifier=NSUserInterfaceItemIdentifier("animationSeconds"); slide(animation)
        check(abs(animationSeconds-0.8)<0.001, "animation duration persists")
        preferences.set(true,forKey:"particles"); preferences.set(2,forKey:"particleKind"); preferences.set(5,forKey:"particleIntensity")
        check(particleKind == .stars && particleIntensity==5, "particle options persist")
        preferences.set(["test":["right":0.0,"fraction":0.2]],forKey:"floatingPositions")
        if let output=ProcessInfo.processInfo.environment["TEACHINGFOCUS_QA_DIR"] {
            func export(_ view:NSView,_ name:String) {
                view.layoutSubtreeIfNeeded()
                guard let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) else { return }
                view.cacheDisplay(in:view.bounds,to:bitmap)
                if let png=bitmap.representation(using:.png,properties:[:]) { try? png.write(to:URL(fileURLWithPath:output).appendingPathComponent(name)) }
            }
            if let view=settingsScroll?.documentView { export(view,"settings.png") }
            beginRecording("freezeKey"); recordKey(event(3,[.control,.option]))
            if let view=recorderPanel?.contentView { export(view,"recorder.png") }
            cancelRecording()
        }
        preferences.set(true,forKey:"welcomed"); preferences.set("keep",forKey:"unrelated-setting")
        restoreDefaultSettings()
        check(paused, "restore defaults preserves pause state")
        check(haloOpacity==0.3 && animationSeconds==0.25 && !bool("particles",false) && particleIntensity==2, "restore resets new effect settings")
        check(preferences.object(forKey:"floatingPositions")==nil, "restore clears saved ball positions")
        check(holdDuration==3 && haloRadius==20 && number("penWidth",4)==4, "restore resets hold duration halo and pen size")
        check(binding("freezeKey")==Shortcut(key:2,modifiers:Shortcut.control | Shortcut.option) && binding("spotKey").key==1, "restore resets recorded shortcuts")
        check(!bool("halo",false) && bool("ripples",true) && bool("spotAnimation",true), "restore resets effect toggles")
        check(preferences.object(forKey:"haloColorRGB")==nil && preferences.object(forKey:"borderColorRGB")==nil, "restore resets custom colors")
        check(bool("welcomed",false) && preferences.string(forKey:"unrelated-setting")=="keep", "restore preserves onboarding and unrelated settings")
        check(effectPreviews.count==2 && holdLabel?.stringValue.contains("3") == true, "restore rebuilds settings and previews")
        paused=false
        let frame=CGRect(x:-1000,y:0,width:1000,height:800)
        let canvas=Canvas(frame:CGRect(origin:.zero,size:frame.size)); canvas.owner=self
        let context=CGContext(data:nil,width:1,height:1,bitsPerComponent:8,bytesPerRow:4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        canvas.snapshot=context.makeImage()
        let window=Overlay(contentRect:frame,styleMask:.borderless,backing:.buffered,defer:false); window.isReleasedWhenClosed=false; window.contentView=canvas; windows=[window]
        let controls=FloatingControls(owner:self,screenFrame:frame,displayKey:"test-display")
        floatingControls=controls
        check(!controls.expanded && controls.ball.frame.width==44, "freeze controls initially collapsed to a 44-point ball")
        controls.expand(); check(controls.expanded && !window.ignoresMouseEvents, "expanded panel enables outside-click shield")
        if let directory=ProcessInfo.processInfo.environment["TEACHINGFOCUS_QA_DIR"] {
            for (view,name) in [(controls.panel.contentView!,"floating-panel.png"),(controls.ballView,"floating-ball.png")] {
                view.layoutSubtreeIfNeeded()
                if let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) {
                    view.cacheDisplay(in:view.bounds,to:bitmap)
                    try? bitmap.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:directory).appendingPathComponent(name))
                }
            }
        }
        let down=NSEvent.mouseEvent(with:.leftMouseDown,location:CGPoint(x:120,y:120),modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
        canvas.mouseDown(with:down); canvas.mouseUp(with:down)
        check(!controls.expanded && canvas.history.items.isEmpty, "outside click closes panel without creating a stroke")
        canvas.mouseDown(with:down); canvas.mouseUp(with:down)
        check(canvas.history.items.count==1, "next canvas click draws normally")
        controls.expand()
        check(handle(.keyDown,esc) && !controls.expanded && frozen != nil, "Escape collapses panel while preserving frozen lesson")
        _ = handle(.keyUp,esc)
        controls.moveBall(to:CGPoint(x:-999,y:600)); controls.finishDrag()
        check(controls.ball.frame.minX == -988 && preferences.dictionary(forKey:"floatingPositions")?["test-display"] != nil, "drag snaps and persists display-specific position")
        controls.close()
        let restored=FloatingControls(owner:self,screenFrame:frame,displayKey:"test-display"); floatingControls=restored
        check(restored.ball.frame.minX == -988, "ball position restored for same screen")
        restored.close()
        let separate=FloatingControls(owner:self,screenFrame:frame,displayKey:"other-display"); floatingControls=separate
        check(separate.ball.frame.maxX == -12, "different screen starts with its own default position")
        canvas.particles.add(ParticleBurst(origin:.zero,born:clockNow(),kind:.dots,intensity:2)); canvas.ripples.append((.zero,clockNow()))
        togglePause()
        check(floatingControls == nil && frozen == nil && canvas.particles.bursts.isEmpty && canvas.ripples.isEmpty, "pause removes floating controls and transient effects")
        let second=Overlay(contentRect:CGRect(x:0,y:0,width:800,height:600),styleMask:.borderless,backing:.buffered,defer:false); second.isReleasedWhenClosed=false
        let secondCanvas=Canvas(frame:CGRect(x:0,y:0,width:800,height:600)); secondCanvas.owner=self; second.contentView=secondCanvas; windows.append(second)
        paused=false; reduceMotionOverride=false
        for index in 0..<12 { emitParticles(on:index%2==0 ? canvas:secondCanvas,point:.zero,time:Double(index)*0.01) }
        check(canvas.particles.bursts.count+secondCanvas.particles.bursts.count==8, "eight-burst cap applies across all monitors")
        canvas.particles.clear(); secondCanvas.particles.clear(); canvas.ripples=[(.zero,clockNow())]; reduceMotionOverride=true
        emitParticles(on:canvas,point:.zero,time:1)
        check(canvas.particles.bursts.isEmpty && canvas.ripples.count==1, "reduce motion suppresses particles without disabling ripples")
        reduceMotionOverride=nil; second.close()
        window.close(); windows=[]
        settings?.close(); preferences.removePersistentDomain(forName:suite)
        print("\(checks) interaction checks passed; native APIs and synthetic local events, not physical keyboard acceptance")
        NSApp.terminate(nil)
    }
}
