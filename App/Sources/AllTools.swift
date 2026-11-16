import Apps
import Authenticator
import Audio
import Blip
import Clipboard
import DevTools
import Dictation
import FileShelf
import KitbagCore
import SpeedTest
import SystemMonitor

/// The one place tools are registered. Add a new tool's descriptor here.
enum AllTools {
  @MainActor static let descriptors: [ToolDescriptor] = [
    FileShelfTool.descriptor,
    ClipboardTool.descriptor,
    AuthenticatorTool.descriptor,
    SystemMonitorTool.descriptor,
    SpeedTestTool.descriptor,
    DevToolsTool.descriptor,
    BlipTool.descriptor,
    AudioTool.descriptor,
    AppsTool.descriptor,
    DictationTool.descriptor,
  ]
}
