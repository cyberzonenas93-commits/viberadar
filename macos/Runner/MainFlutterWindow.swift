import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let desiredFrame = NSRect(x: 0, y: 0, width: 1480, height: 940)
    self.contentViewController = flutterViewController
    self.minSize = NSSize(width: 1320, height: 820)
    self.setContentSize(desiredFrame.size)
    self.center()
    self.title = "VibeRadar"

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
