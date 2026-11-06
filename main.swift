// wow-span: one big virtual display, mirrored slice-by-slice onto the physical screens.
// WoW runs Windowed on the virtual display, so Offhand sees one wide monitor; the mirror hides
// the title bar. Ctrl-C to quit: the virtual display vanishes with the process.
import AppKit
import ScreenCaptureKit

let refreshRate = 60.0  // calibration knob: match your slowest screen
let scale = CommandLine.arguments.contains("--retina") ? 2 : 1  // --retina: 2x pixels, sharp on 4K, heavier on the GPU

// Physical screens left→right. Every slice is as tall as the biggest screen (the game screen, 1:1);
// the others keep their own shape and are scaled, so no part of the canvas is ever off-screen.
func slices(_ sizes: [CGSize]) -> (CGSize, [CGRect]) {
    let h = sizes.max { $0.width * $0.height < $1.width * $1.height }?.height ?? 0
    var x: CGFloat = 0
    let rects = sizes.map { s -> CGRect in
        let w = (s.width * h / s.height).rounded()
        defer { x += w }
        return CGRect(x: x, y: 0, width: w, height: h)
    }
    return (CGSize(width: x, height: h), rects)
}

if CommandLine.arguments.contains("--selftest") {
    var (size, r) = slices([CGSize(width: 1920, height: 1080), CGSize(width: 900, height: 1600)])  // 16:9 game screen + portrait side screen
    precondition(size == CGSize(width: 2528, height: 1080))
    precondition(r[1] == CGRect(x: 1920, y: 0, width: 608, height: 1080))
    (size, r) = slices([CGSize(width: 1920, height: 1080), CGSize(width: 1600, height: 900)])  // + landscape 1600x900 side screen
    precondition(size == CGSize(width: 3840, height: 1080) && r[0].width == 1920)
    print("ok"); exit(0)
}

setvbuf(stdout, nil, _IONBF, 0)
_ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let physical = NSScreen.screens.sorted { $0.frame.minX < $1.frame.minX }
let (vsize, rects) = slices(physical.map(\.frame.size))

// Snapshot each real screen's mode and origin; creating the virtual display can disturb both.
func displayID(_ s: NSScreen) -> CGDirectDisplayID { s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID }
let saved = physical.map { s -> (CGDirectDisplayID, CGDisplayMode, CGRect) in
    let id = displayID(s); return (id, CGDisplayCopyDisplayMode(id)!, CGDisplayBounds(id))
}

let desc = CGVirtualDisplayDescriptor()
desc.queue = .main
desc.name = "WoW Span"
desc.maxPixelsWide = UInt32(vsize.width) * UInt32(scale)
desc.maxPixelsHigh = UInt32(vsize.height) * UInt32(scale)
desc.sizeInMillimeters = CGSize(width: vsize.width * 0.265, height: vsize.height * 0.265)
desc.vendorID = 0xF0F0; desc.productID = 1; desc.serialNum = 1
let vd: CGVirtualDisplay = CGVirtualDisplay(descriptor: desc)
let settings = CGVirtualDisplaySettings()
settings.hiDPI = scale == 2 ? 1 : 0
settings.modes = [CGVirtualDisplayMode(width: UInt32(vsize.width) * UInt32(scale), height: UInt32(vsize.height) * UInt32(scale), refreshRate: refreshRate)!,
                  CGVirtualDisplayMode(width: UInt32(vsize.width), height: UInt32(vsize.height), refreshRate: refreshRate)!]
guard vd.apply(settings) else { fatalError("could not create virtual display") }

// macOS auto-mirrors a new display onto the main one, and leaves the real screens mirrored
// when it goes away. Force it standalone, to the right of every physical screen.
func placeVirtual() -> Bool {
    var cfg: CGDisplayConfigRef?
    CGBeginDisplayConfiguration(&cfg)
    CGConfigureDisplayMirrorOfDisplay(cfg, vd.displayID, kCGNullDirectDisplay)
    for (id, mode, b) in saved {
        CGConfigureDisplayMirrorOfDisplay(cfg, id, kCGNullDirectDisplay)
        // Re-applying an unchanged mode resets rotation, so only restore what macOS actually changed.
        if CGDisplayCopyDisplayMode(id)?.ioDisplayModeID != mode.ioDisplayModeID {
            CGConfigureDisplayWithDisplayMode(cfg, id, mode, nil)
        }
        CGConfigureDisplayOrigin(cfg, id, Int32(b.minX), Int32(b.minY))
    }
    let right = saved.map { $0.2.maxX }.max()!
    CGConfigureDisplayOrigin(cfg, vd.displayID, Int32(right), 0)
    // Pick the mode that is vsize in points at the requested pixel scale.
    let opts = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
    if let modes = CGDisplayCopyAllDisplayModes(vd.displayID, opts) as? [CGDisplayMode],
       let m = modes.first(where: { $0.width == Int(vsize.width) && $0.pixelWidth == Int(vsize.width) * scale }) {
        CGConfigureDisplayWithDisplayMode(cfg, vd.displayID, m, nil)
    } else { print("wow-span: no \(scale)x mode offered; continuing at default") }
    return CGCompleteDisplayConfiguration(cfg, .forSession) == .success
}

final class Mirror: NSObject, SCStreamOutput {
    var layers: [CALayer] = []
    func stream(_ s: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let pb = sb.imageBuffer,
              let surf = CVPixelBufferGetIOSurface(pb)?.takeUnretainedValue() else { return }
        DispatchQueue.main.async {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            for l in self.layers { l.contents = surf }
            CATransaction.commit()
        }
    }
}
let mirror = Mirror()

// One borderless, click-through window per physical screen, showing its slice.
var windows: [NSWindow] = []
var windowDisplays: [CGDirectDisplayID] = []
for (screen, r) in zip(physical, rects) {
    let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
    w.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
    w.ignoresMouseEvents = true
    w.collectionBehavior = [.canJoinAllSpaces, .stationary]
    w.backgroundColor = .black
    let v = NSView(); v.wantsLayer = true
    v.layer!.contentsGravity = .resize
    v.layer!.contentsRect = CGRect(x: r.minX / vsize.width, y: r.minY / vsize.height,
                                   width: r.width / vsize.width, height: r.height / vsize.height)
    w.contentView = v
    w.setFrame(screen.frame, display: false)
    windows.append(w); mirror.layers.append(v.layer!)
    windowDisplays.append(displayID(screen))
}

// Mirror only while the frontmost window (first normal-layer window, front-to-back) sits on the
// virtual display, so Cmd-Tab away gives you your normal desktop back.
// (NSWorkspace.frontmostApplication is nil for a command-line process, so don't use it.)
// Windowed WoW (which Offhand requires) keeps the display's shape for its game area and puts a
// title bar on top, so it never quite fills the display. Mirror only the game area: the bottom
// `width / aspect` rows of the window. Returns that rect in virtual-display points, top-left origin.
var active = false
let wowOwner = "Wow"  // WoW's process name in the window list

// Anything else that opens on the invisible display (e.g. a browser link clicked in WoW) can't be
// seen or reached, so move it onto the main display.
func rescueStrayWindows() {
    let vb = CGDisplayBounds(vd.displayID)
    guard let list = CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return }
    for w in list where (w[kCGWindowLayer as String] as? Int) == 0 && (w[kCGWindowOwnerName as String] as? String) != wowOwner {
        guard let b = w[kCGWindowBounds as String], let r = CGRect(dictionaryRepresentation: b as! CFDictionary),
              r.width > 100, r.height > 100, vb.contains(CGPoint(x: r.midX, y: r.midY)),
              let pid = w[kCGWindowOwnerPID as String] as? pid_t else { continue }
        var wins: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &wins) == .success,
              let axWindows = wins as? [AXUIElement] else { continue }
        for ax in axWindows {
            var pos: CFTypeRef?
            guard AXUIElementCopyAttributeValue(ax, kAXPositionAttribute as CFString, &pos) == .success else { continue }
            var p = CGPoint.zero
            AXValueGetValue(pos as! AXValue, .cgPoint, &p)
            guard vb.contains(CGPoint(x: p.x + 50, y: p.y + 50)) else { continue }
            var target = CGPoint(x: 50, y: 50)  // top-left of the main display
            AXUIElementSetAttributeValue(ax, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &target)!)
        }
    }
}
// Mission Control / App Exposé draw as big Dock windows above everything; step aside while they're up.
func missionControlOpen() -> Bool {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return list.contains {
        ($0[kCGWindowOwnerName as String] as? String) == "Dock" && ($0[kCGWindowLayer as String] as? Int ?? 0) >= 18
            && (($0[kCGWindowBounds as String]).flatMap { CGRect(dictionaryRepresentation: $0 as! CFDictionary) }?.width ?? 0) > 300
    }
}

// If WoW opened on a real screen (it started before the virtual display existed), pull it over.
func pullWoWOntoVirtual() {
    let vb = CGDisplayBounds(vd.displayID)
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
          let w = list.first(where: { ($0[kCGWindowOwnerName as String] as? String) == wowOwner && ($0[kCGWindowLayer as String] as? Int) == 0 }),
          let b = w[kCGWindowBounds as String], let r = CGRect(dictionaryRepresentation: b as! CFDictionary),
          r.width > 400, !vb.contains(CGPoint(x: r.midX, y: r.midY)),
          let pid = w[kCGWindowOwnerPID as String] as? pid_t else { return }
    var wins: CFTypeRef?
    guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &wins) == .success,
          let ax = (wins as? [AXUIElement])?.first else { return }
    var origin = vb.origin, size = vb.size
    AXUIElementSetAttributeValue(ax, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &origin)!)
    AXUIElementSetAttributeValue(ax, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &size)!)
}

func gameRectOnVirtual() -> CGRect? {
    let vb = CGDisplayBounds(vd.displayID)
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
          let front = list.first(where: { ($0[kCGWindowLayer as String] as? Int) == 0 && ($0[kCGWindowAlpha as String] as? Double ?? 1) > 0 }),
          (front[kCGWindowOwnerName as String] as? String) == wowOwner,  // only ever mirror WoW
          let b = front[kCGWindowBounds as String], let r = CGRect(dictionaryRepresentation: b as! CFDictionary),
          vb.contains(CGPoint(x: r.midX, y: r.midY))
    else { return nil }
    let w = min(r.width, vb.width), h = min(r.height, w * vsize.height / vsize.width)
    return CGRect(x: r.minX - vb.minX, y: r.maxY - vb.minY - h, width: w, height: h)
}
// Each physical screen shows one slice of `source` (WoW's game area); map a global point between a
// screen and the matching spot on the virtual display. nil if the point isn't on a mirrored area.
func mapCursor(_ p: CGPoint, toVirtual: Bool) -> CGPoint? {
    guard let src = source else { return nil }
    let vb = CGDisplayBounds(vd.displayID), k = src.width / vsize.width
    for (r, id) in zip(rects, windowDisplays) {
        let phys = CGDisplayBounds(id)
        let virt = CGRect(x: vb.minX + src.minX + r.minX * k, y: vb.minY + src.minY + r.minY * k, width: r.width * k, height: r.height * k)
        let (from, to) = toVirtual ? (phys, virt) : (virt, phys)
        if from.contains(p) {
            return CGPoint(x: to.minX + (p.x - from.minX) * to.width / from.width, y: to.minY + (p.y - from.minY) * to.height / from.height)
        }
    }
    return nil
}
let contentsYFromTop = false  // calibration knob: flip if the mirror shows the title bar instead of the bottom
var source: CGRect?
func applyCrop(_ src: CGRect) {
    let k = src.width / vsize.width
    for (layer, r) in zip(mirror.layers, rects) {
        let top = (src.minY + r.minY * k) / vsize.height, h = r.height * k / vsize.height
        layer.contentsRect = CGRect(x: (src.minX + r.minX * k) / vsize.width, y: contentsYFromTop ? top : 1 - top - h,
                                    width: r.width * k / vsize.width, height: h)
    }
}
// Display reconfiguration (ours, or macOS reshuffling) can leave a mirror window off its screen.
// Recompute from CGDisplayBounds (always fresh; NSScreen frames can be stale) in Cocoa coordinates.
func realign() {
    let mainH = CGDisplayBounds(CGMainDisplayID()).height
    for (w, id) in zip(windows, windowDisplays) {
        let b = CGDisplayBounds(id)
        let f = CGRect(x: b.minX, y: mainH - b.maxY, width: b.width, height: b.height)
        if w.frame != f { w.setFrame(f, display: true) }
    }
}
Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in  // fast enough to step aside for Mission Control
    realign()
    rescueStrayWindows()
    pullWoWOntoVirtual()
    let src = gameRectOnVirtual()
    if let src, src != source { source = src; applyCrop(src) }
    let now = src != nil && !missionControlOpen()
    guard now != active else { return }
    // Keep the cursor where it appears: map it through the mirror in whichever direction we switch.
    if let p = CGEvent(source: nil)?.location, let q = mapCursor(p, toVirtual: now) { CGWarpMouseCursorPosition(q) }
    active = now
    windows.forEach { now ? $0.orderFrontRegardless() : $0.orderOut(nil) }
}

// The virtual display is invisible: while mirroring keep the cursor on it, otherwise keep it off it.
func clamp(_ p: CGPoint, to r: CGRect) -> CGPoint {
    CGPoint(x: min(max(p.x, r.minX), r.maxX - 1), y: min(max(p.y, r.minY), r.maxY - 1))
}
func guardCursor() {
    guard let p = CGEvent(source: nil)?.location else { return }
    let vb = CGDisplayBounds(vd.displayID)
    var c = p
    if active { c = clamp(p, to: vb) }
    else if vb.contains(p) {
        let edge = saved.map(\.2).max { $0.maxX < $1.maxX }!  // physical screen touching the virtual one
        c = clamp(p, to: edge)
    }
    if c != p { CGWarpMouseCursorPosition(c) }
}
NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { _ in guardCursor() }
Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in guardCursor() }  // backstop if events are missed

var stream: SCStream?
Task { do {
    try await Task.sleep(for: .seconds(1))
    guard placeVirtual() else { print("wow-span: could not place virtual display"); exit(1) }
    var display: SCDisplay?
    for _ in 0..<20 {
        display = try await SCShareableContent.current.displays.first { $0.displayID == vd.displayID }
        if display != nil { break }
        try await Task.sleep(for: .milliseconds(250))
    }
    guard let display else { fatalError("virtual display never appeared") }
    let cfg = SCStreamConfiguration()
    cfg.width = Int(vsize.width) * scale; cfg.height = Int(vsize.height) * scale
    cfg.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(refreshRate))
    cfg.queueDepth = 3
    cfg.showsCursor = true
    let s = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: cfg, delegate: nil)
    try s.addStreamOutput(mirror, type: .screen, sampleHandlerQueue: .global(qos: .userInteractive))
    try await s.startCapture()
    stream = s
    print("wow-span: virtual display \"WoW Span\" \(Int(vsize.width))x\(Int(vsize.height)) is live. Ctrl-C to quit.")
} catch { print("wow-span: capture failed: \(error) (grant Screen Recording to your terminal, then rerun)"); exit(1) } }

app.run()
