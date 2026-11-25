// xkill for macOS: click a window with the X cursor, its owning process gets SIGKILL. Esc / right-click cancels.
// Build: swiftc -O xkill.swift -o xkill
import AppKit

// Front-to-back on-screen windows; bounds are in CG global coords (top-left origin of the primary screen).
func pick(at p: CGPoint, in windows: [[String: Any]], excluding me: pid_t) -> (pid: pid_t, rect: CGRect)? {
    for w in windows {
        guard let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != me,
              (w[kCGWindowLayer as String] as? Int) == 0, // normal app windows only: never Dock, menu bar, WindowServer
              let b = w[kCGWindowBounds as String] as? [String: CGFloat],
              case let r = CGRect(x: b["X"]!, y: b["Y"]!, width: b["Width"]!, height: b["Height"]!), r.contains(p)
        else { continue }
        return (pid, r)
    }
    return nil
}

if CommandLine.arguments.contains("--selftest") {
    let ws: [[String: Any]] = [
        [kCGWindowOwnerPID as String: pid_t(1), kCGWindowLayer as String: 25, kCGWindowBounds as String: ["X": 0, "Y": 0, "Width": 999, "Height": 999] as [String: CGFloat]],
        [kCGWindowOwnerPID as String: pid_t(2), kCGWindowLayer as String: 0, kCGWindowBounds as String: ["X": 0, "Y": 0, "Width": 100, "Height": 100] as [String: CGFloat]],
        [kCGWindowOwnerPID as String: pid_t(3), kCGWindowLayer as String: 0, kCGWindowBounds as String: ["X": 0, "Y": 0, "Width": 500, "Height": 500] as [String: CGFloat]],
    ]
    precondition(pick(at: CGPoint(x: 50, y: 50), in: ws, excluding: 99)?.pid == 2)  // topmost layer-0 wins
    precondition(pick(at: CGPoint(x: 50, y: 50), in: ws, excluding: 2)?.pid == 3)   // own windows skipped
    precondition(pick(at: CGPoint(x: 300, y: 300), in: ws, excluding: 99)?.pid == 3)
    precondition(pick(at: CGPoint(x: 600, y: 600), in: ws, excluding: 99) == nil)
    precondition(pick(at: CGPoint(x: 50, y: 50), in: ws, excluding: 99)?.rect == CGRect(x: 0, y: 0, width: 100, height: 100))
    print("ok"); exit(0)
}

let xCursor: NSCursor = {
    let s: CGFloat = 24
    let img = NSImage(size: NSSize(width: s, height: s), flipped: false) { _ in
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 4, y: 4)); path.line(to: NSPoint(x: s - 4, y: s - 4))
        path.move(to: NSPoint(x: 4, y: s - 4)); path.line(to: NSPoint(x: s - 4, y: 4))
        path.lineCapStyle = .round
        NSColor.white.setStroke(); path.lineWidth = 6; path.stroke()
        NSColor.black.setStroke(); path.lineWidth = 3; path.stroke()
        return true
    }
    return NSCursor(image: img, hotSpot: NSPoint(x: s / 2, y: s / 2))
}()

// osascript is the zero-setup way to post a banner from a bare CLI binary (shows under Script Editor).
// The text goes in argv, not the script, so app names with quotes can't break it.
func notify(_ msg: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    p.arguments = ["-e", "on run argv", "-e", "display notification (item 1 of argv) with title \"xkill\" sound name \"Funk\"", "-e", "end run", msg]
    try? p.run(); p.waitUntilExit()
}

// What the pointer is over right now; drawn by every overlay so it spans screens.
var target: (pid: pid_t, rect: CGRect, name: String)?
let primaryMaxY = { NSScreen.screens[0].frame.maxY }

func windowUnderMouse() -> (pid: pid_t, rect: CGRect)? {
    let m = NSEvent.mouseLocation
    let p = CGPoint(x: m.x, y: primaryMaxY() - m.y) // Cocoa bottom-left -> CG top-left
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    return pick(at: p, in: list, excluding: getpid())
}

func refreshTarget() {
    let hit = windowUnderMouse()
    if hit?.pid == target?.pid && hit?.rect == target?.rect { return }
    target = hit.map { ($0.pid, $0.rect, NSRunningApplication(processIdentifier: $0.pid)?.localizedName ?? "pid \($0.pid)") }
    windows.forEach { $0.contentView?.needsDisplay = true }
}

final class Overlay: NSView {
    override func draw(_ dirty: NSRect) {
        guard let t = target, let win = window else { return }
        // CG global rect -> Cocoa global -> this screen's view coords
        let r = NSRect(x: t.rect.minX - win.frame.minX, y: primaryMaxY() - t.rect.maxY - win.frame.minY,
                       width: t.rect.width, height: t.rect.height)
        NSColor.systemRed.withAlphaComponent(0.18).setFill(); r.fill()
        let border = NSBezierPath(rect: r.insetBy(dx: 2, dy: 2)); border.lineWidth = 4
        NSColor.systemRed.setStroke(); border.stroke()

        let label = " ✕ \(t.name) " as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 15), .foregroundColor: NSColor.white]
        let size = label.size(withAttributes: attrs)
        let box = NSRect(x: r.midX - size.width / 2 - 6, y: r.midY - size.height / 2 - 4, width: size.width + 12, height: size.height + 8)
        NSColor.systemRed.setFill(); NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
        label.draw(at: NSPoint(x: box.minX + 6, y: box.minY + 4), withAttributes: attrs)
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: xCursor) }
    // cursor rects only apply while we're the active app; this keeps the X after a Desktop switch too
    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseMoved(with e: NSEvent) { xCursor.set(); refreshTarget() }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func keyDown(with e: NSEvent) { if e.keyCode == 53 { exit(1) } } // Esc
    override func rightMouseDown(with e: NSEvent) { exit(1) }
    override func mouseDown(with e: NSEvent) {
        guard let pid = windowUnderMouse()?.pid else { NSSound.beep(); return }
        let name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "?"
        if kill(pid, SIGKILL) == 0 {
            print("killed \(name) (pid \(pid))")
            notify("Killed \(name) (pid \(pid))")
            exit(0)
        }
        perror("kill \(pid)"); exit(1)
    }
}

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
var windows: [NSWindow] = []
for screen in NSScreen.screens {
    let w = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
    w.level = .screenSaver
    w.isOpaque = false
    w.backgroundColor = NSColor.black.withAlphaComponent(0.01) // fully clear windows let clicks fall through
    w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    w.contentView = Overlay()
    w.makeFirstResponder(w.contentView)
    windows.append(w)
}
// Switching Desktops hands focus to that Desktop's front app; take it back so the X cursor and Esc keep working.
func grabFocus() {
    windows.forEach { $0.orderFrontRegardless() }
    windows.first?.makeKey()
    app.activate(ignoringOtherApps: true)
    xCursor.set()
    refreshTarget()
}
NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
    grabFocus()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { grabFocus() } // again after the switch animation settles
}
grabFocus()
app.run()
