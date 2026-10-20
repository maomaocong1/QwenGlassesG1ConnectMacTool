import SwiftUI

@main
struct QwenGlassesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("Qwen Glasses G1 配对工具") {
            ContentView()
                .frame(minWidth: 980, minHeight: 640)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("退出") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
