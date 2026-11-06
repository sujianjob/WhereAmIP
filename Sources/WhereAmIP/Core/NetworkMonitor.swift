import Foundation
import Network
import SystemConfiguration
import AppKit

/// 网络与系统环境事件类型
public enum SystemEventReason: String, Sendable {
    case networkPathChanged = "网络拓扑变动"
    case systemProxyChanged = "系统代理变更"
    case systemWake = "系统唤醒"
    case screenUnlocked = "屏幕解锁"
}

/// 负责第一层“事件驱动”监听：网卡切换、VPN/TUN 变动、系统代理变更、睡眠唤醒与锁屏感知
@MainActor
public final class NetworkMonitor {
    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.whereamip.network.monitor", qos: .utility)
    private var dynamicStore: SCDynamicStore?
    private var runLoopSource: CFRunLoopSource?

    /// 当前网络是否处于可连接状态
    public private(set) var isConnected: Bool = true
    /// 当前屏幕是否处于锁定状态
    public private(set) var isScreenLocked: Bool = false

    /// 上一次记录的网络路径签名（用于过滤无实质变化的重复回调）
    private var lastPathSignature: String = ""

    /// 事件回调：(事件原因) -> Void
    public var onSystemEvent: ((SystemEventReason) -> Void)?
    /// 网络离线回调
    public var onNetworkOffline: (() -> Void)?
    /// 锁屏状态变更回调：(isLocked) -> Void
    public var onScreenLockChanged: ((Bool) -> Void)?

    public init() {}

    public func start() {
        startPathMonitor()
        startSystemProxyMonitor()
        startWorkspaceAndScreenMonitors()
    }

    public func stop() {
        pathMonitor.cancel()
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        dynamicStore = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }

    // MARK: - 1. NWPathMonitor 监听网卡、Wi-Fi、网线及 VPN (utun) 状态

    private func startPathMonitor() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let connected = (path.status == .satisfied)
            let interfaces = path.availableInterfaces.map { "\($0.name):\($0.type)" }.joined(separator: ",")
            let signature = "\(path.status)-\(interfaces)-\(path.isExpensive)-\(path.supportsIPv4)-\(path.supportsIPv6)"

            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasConnected = self.isConnected
                self.isConnected = connected

                if !connected {
                    self.lastPathSignature = signature
                    self.onNetworkOffline?()
                    return
                }

                // 首次启动或网络路径签名发生实质变化时触发
                if self.lastPathSignature != signature || !wasConnected {
                    let isInitial = self.lastPathSignature.isEmpty
                    self.lastPathSignature = signature
                    if !isInitial {
                        self.onSystemEvent?(.networkPathChanged)
                    }
                }
            }
        }
        pathMonitor.start(queue: monitorQueue)
    }

    // MARK: - 2. SCDynamicStore 监听系统 HTTP/SOCKS 代理及全局 IPv4 路由变化

    private func startSystemProxyMonitor() {
        let callback: SCDynamicStoreCallBack = { _, _, _ in
            Task { @MainActor in
                NotificationCenter.default.post(name: .whereAmIPSystemProxyDidChange, object: nil)
            }
        }

        var context = SCDynamicStoreContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
        guard let store = SCDynamicStoreCreate(nil, "com.whereamip.proxymonitor" as CFString, callback, &context) else {
            return
        }

        let watchedKeys: [CFString] = [
            "State:/Network/Global/Proxies" as CFString,
            "State:/Network/Global/IPv4" as CFString
        ]

        if SCDynamicStoreSetNotificationKeys(store, watchedKeys as CFArray, nil),
           let source = SCDynamicStoreCreateRunLoopSource(nil, store, 0) {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            self.dynamicStore = store
            self.runLoopSource = source
        }

        NotificationCenter.default.addObserver(
            forName: .whereAmIPSystemProxyDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.onSystemEvent?(.systemProxyChanged)
            }
        }
    }

    // MARK: - 3. 系统睡眠唤醒与屏幕锁定状态监听

    private func startWorkspaceAndScreenMonitors() {
        let wsCenter = NSWorkspace.shared.notificationCenter
        wsCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.onSystemEvent?(.systemWake)
            }
        }

        let distCenter = DistributedNotificationCenter.default()
        distCenter.addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isScreenLocked = true
                self.onScreenLockChanged?(true)
            }
        }

        distCenter.addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isScreenLocked = false
                self.onScreenLockChanged?(false)
                self.onSystemEvent?(.screenUnlocked)
            }
        }
    }
}

private extension Notification.Name {
    static let whereAmIPSystemProxyDidChange = Notification.Name("WhereAmIPSystemProxyDidChangeNotification")
}
