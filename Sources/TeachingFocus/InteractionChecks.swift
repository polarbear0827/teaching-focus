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
        let well=(effectPreviews[1].superview as! NSStackView).arrangedSubviews.compactMap { $0 as? NSColorWell }.first!; well.color=NSColor(srgbRed:0.2,green:0.5,blue:0.8,alpha:1); colorChanged(well)
        check(abs((haloColor.usingColorSpace(.sRGB)?.blueComponent ?? 0)-0.8)<0.001, "halo custom color persists")
        let borderWell=(effectPreviews[0].superview as! NSStackView).arrangedSubviews.compactMap { $0 as? NSColorWell }.first!; borderWell.color=NSColor(srgbRed:0.9,green:0.1,blue:0.3,alpha:1); colorChanged(borderWell)
        check(abs((borderColor.usingColorSpace(.sRGB)?.redComponent ?? 0)-0.9)<0.001, "border custom color persists")
        let haloSlider=NSSlider(value:42,minValue:6,maxValue:80,target:nil,action:nil); haloSlider.identifier=NSUserInterfaceItemIdentifier("haloRadius"); slide(haloSlider)
        check(haloRadius==42 && haloSizeLabel?.stringValue.contains("42")==true, "halo radius setting and label update")
        check(teachingMenuIcon().isTemplate && teachingMenuIcon().size.width==22, "menu icon supports system light and dark appearance")
        check(effectPreviews.count==2, "both effect color previews are present")
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
        check(holdDuration==3 && haloRadius==20 && number("penWidth",4)==4, "restore resets hold duration halo and pen size")
        check(binding("freezeKey")==Shortcut(key:2,modifiers:Shortcut.control | Shortcut.option) && binding("spotKey").key==1, "restore resets recorded shortcuts")
        check(!bool("halo",false) && bool("ripples",true) && bool("spotAnimation",true), "restore resets effect toggles")
        check(preferences.object(forKey:"haloColorRGB")==nil && preferences.object(forKey:"borderColorRGB")==nil, "restore resets custom colors")
        check(bool("welcomed",false) && preferences.string(forKey:"unrelated-setting")=="keep", "restore preserves onboarding and unrelated settings")
        check(effectPreviews.count==2 && holdLabel?.stringValue.contains("3") == true, "restore rebuilds settings and previews")
        settings?.close(); preferences.removePersistentDomain(forName:suite)
        print("\(checks) interaction checks passed; native APIs and synthetic local events, not physical keyboard acceptance")
        NSApp.terminate(nil)
    }
}
