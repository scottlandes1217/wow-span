// Recovery: un-mirror every display (run if screens are ever left mirrored).
import CoreGraphics
var ids = [CGDirectDisplayID](repeating: 0, count: 8); var n: UInt32 = 0
CGGetOnlineDisplayList(8, &ids, &n)
var cfg: CGDisplayConfigRef?
CGBeginDisplayConfiguration(&cfg)
for id in ids.prefix(Int(n)) {
    CGConfigureDisplayMirrorOfDisplay(cfg, id, kCGNullDirectDisplay)
}
print("unmirror:", CGCompleteDisplayConfiguration(cfg, .permanently).rawValue)
