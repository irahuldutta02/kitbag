import Apps
import Authenticator
import Audio
import Blip
import Calculator
import Clipboard
import DevTools
import Dictation
import FileShelf
import KitbagCore
import Mirror
import SpeedTest
import SystemMonitor
import VideoPlayer

/// The one place tools are registered. Add a new tool's descriptor here.
enum AllTools {
  @MainActor static let descriptors: [ToolDescriptor] = [
    FileShelfTool.descriptor,
    ClipboardTool.descriptor,
    AuthenticatorTool.descriptor,
    VideoPlayerTool.descriptor,
    SystemMonitorTool.descriptor,
    SpeedTestTool.descriptor,
    CalculatorTool.descriptor,
    MirrorTool.descriptor,
    DevToolsTool.descriptor,
    PortManagerTool.descriptor,
    BlipTool.descriptor,
    AudioTool.descriptor,
    AppLauncherTool.descriptor,
    AppsTool.descriptor,
    DictationTool.descriptor,
  ]
}
