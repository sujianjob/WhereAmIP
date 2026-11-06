import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var scheduler: RefreshScheduler?
    private var statusBarController: StatusBarController?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // 设置为 .accessory 模式：仅在顶部菜单栏显示，不在 Dock 栏和 Cmd+Tab 中出现
        NSApplication.shared.setActivationPolicy(.accessory)

        // 初始化通知中心与横幅权限
        NotificationManager.shared.setup()

        let refreshScheduler = RefreshScheduler()
        self.scheduler = refreshScheduler
        self.statusBarController = StatusBarController(scheduler: refreshScheduler)

        refreshScheduler.start()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        scheduler?.stop()
    }
}
