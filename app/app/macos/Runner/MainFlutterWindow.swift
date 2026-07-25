import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    // WaxDeck's canvas colour, so the window does not flash the system
    // background before Flutter's first frame. Resolved per appearance
    // rather than pinned to dark: a light-mode desktop should not flash
    // charcoal either. Keep in step with WaxColors.canvas.
    self.backgroundColor = NSColor(name: nil) { appearance in
      let dark =
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
      return dark
        ? NSColor(srgbRed: 0x16 / 255.0, green: 0x13 / 255.0, blue: 0x0F / 255.0, alpha: 1)
        : NSColor(srgbRed: 0xFA / 255.0, green: 0xF9 / 255.0, blue: 0xF6 / 255.0, alpha: 1)
    }
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
