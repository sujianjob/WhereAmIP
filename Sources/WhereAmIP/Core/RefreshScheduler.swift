import Foundation
import IOKit.ps

/// 状态栏当前的探测状态
public enum IPFetchState: Equatable, Sendable {
    case loading(previous: IPInfo?)
    case loaded(IPInfo)
    case offline
    case failed(message: String, previous: IPInfo?)

    public var currentInfo: IPInfo? {
        switch self {
        case .loading(let previous):
            return previous
        case .loaded(let info):
            return info
        case .offline:
            return nil
        case .failed(_, let previous):
            return previous
        }
    }
}

/// 三层混合刷新调度器：
/// 1. 第一层：事件即时驱动 + 1.5s 防抖（网卡/VPN/代理/唤醒/解锁）
/// 2. 第二层：自适应低频轮询（默认 5 分钟，电池供电自动降频，锁屏彻底暂停）
/// 3. 第三层：交互触发（点开菜单 TTL 20s 校验、手动立即刷新）
@MainActor
public final class RefreshScheduler {
    private let ipService = IPService.shared
    private let networkMonitor = NetworkMonitor()
    private let settings = AppSettings.shared
    private let notificationManager = NotificationManager.shared

    /// 防抖窗口时长（1.5 秒）
    private let debounceInterval: TimeInterval = 1.5
    /// 点击展开菜单时的缓存有效时长 TTL（20 秒）
    private let menuOpenTTL: TimeInterval = 20.0

    private var debounceTask: Task<Void, Never>?
    private var fetchTask: Task<Void, Never>?
    private var pollingTimer: Timer?

    /// 当前探测状态
    public private(set) var state: IPFetchState = .loading(previous: nil) {
        didSet {
            onStateChange?(state)
        }
    }

    /// 最近一次成功获取到的 IP 信息
    private var lastLoadedInfo: IPInfo?
    /// 上一次不同的出口 IP 信息（用于对比变更历史）
    public private(set) var previousDistinctInfo: IPInfo?
    /// 最近一次刷新触发原因描述
    public private(set) var lastTriggerReason: String = "初始启动"

    /// 状态更新回调
    public var onStateChange: ((IPFetchState) -> Void)?

    public init() {
        setupMonitorCallbacks()
    }

    /// 启动调度器与监听
    public func start() {
        networkMonitor.start()
        schedulePollingTimer()
        triggerImmediateRefresh(reason: "应用启动")
    }

    /// 停止调度器
    public func stop() {
        debounceTask?.cancel()
        fetchTask?.cancel()
        pollingTimer?.invalidate()
        pollingTimer = nil
        networkMonitor.stop()
    }

    /// 当用户修改刷新频率预设时重新排期定时器
    public func reloadTimerSettings() {
        schedulePollingTimer()
    }

    // MARK: - 第三层：交互触发

    /// 用户点击菜单栏图标展开菜单时调用（超过 20s TTL 才静默刷新）
    public func triggerOnMenuOpen() {
        guard networkMonitor.isConnected else {
            state = .offline
            return
        }

        // 若正在加载中，不重复触发
        if case .loading = state {
            return
        }

        if let lastInfo = lastLoadedInfo {
            let elapsed = Date().timeIntervalSince(lastInfo.fetchedAt)
            if elapsed >= menuOpenTTL {
                triggerImmediateRefresh(reason: "展开菜单校验")
            }
        } else {
            triggerImmediateRefresh(reason: "展开菜单重试")
        }
    }

    /// 用户手动点击“立即刷新”
    public func triggerManualRefresh() {
        triggerImmediateRefresh(reason: "手动刷新")
    }

    // MARK: - 第一层：系统与网络事件处理 + 1.5s 防抖

    private func setupMonitorCallbacks() {
        networkMonitor.onSystemEvent = { [weak self] reason in
            self?.triggerDebouncedRefresh(reason: reason.rawValue)
        }

        networkMonitor.onNetworkOffline = { [weak self] in
            guard let self else { return }
            self.debounceTask?.cancel()
            self.fetchTask?.cancel()
            self.state = .offline
        }

        networkMonitor.onScreenLockChanged = { [weak self] isLocked in
            guard let self else { return }
            if isLocked {
                // 锁屏时彻底停止后台轮询与挂起任务，零电量消耗
                self.debounceTask?.cancel()
                self.pollingTimer?.invalidate()
                self.pollingTimer = nil
            } else {
                // 解锁后恢复轮询定时器（解锁事件本身也会触发一次刷新）
                self.schedulePollingTimer()
            }
        }
    }

    private func triggerDebouncedRefresh(reason: String) {
        guard !networkMonitor.isScreenLocked else { return }

        debounceTask?.cancel()
        let nanos = UInt64(debounceInterval * 1_000_000_000)
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled, let self else { return }
            self.executeFetch(reason: reason)
        }
    }

    private func triggerImmediateRefresh(reason: String) {
        debounceTask?.cancel()
        executeFetch(reason: reason)
    }

    // MARK: - 第二层：自适应低频智能轮询

    private func schedulePollingTimer() {
        pollingTimer?.invalidate()
        pollingTimer = nil

        guard !networkMonitor.isScreenLocked else { return }

        let interval = currentEffectivePollingInterval()
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard !self.networkMonitor.isScreenLocked, self.networkMonitor.isConnected else { return }
                self.executeFetch(reason: "定时轮询")
                // 每次轮询后动态检查电源状态，若切换了电池/电源模式则自适应调整下次间隔
                self.adjustTimerIfPowerSourceChanged(currentInterval: interval)
            }
        }
        // 允许系统合并定时器唤醒 (10% 宽容度)，大幅降低 macOS CPU 唤醒功耗
        timer.tolerance = max(5.0, interval * 0.1)
        pollingTimer = timer
    }

    private func adjustTimerIfPowerSourceChanged(currentInterval: TimeInterval) {
        let desired = currentEffectivePollingInterval()
        if abs(desired - currentInterval) > 1.0 {
            schedulePollingTimer()
        }
    }

    /// 计算当前生效的轮询间隔（综合用户预设 + 电池/低电量模式）
    public func currentEffectivePollingInterval() -> TimeInterval {
        let preset = settings.refreshPreset
        if isRunningOnBatteryOrLowPower() {
            return preset.batteryInterval
        }
        return preset.baseInterval
    }

    /// 检测 Mac 当前是否使用电池供电或开启了低电量模式
    public func isRunningOnBatteryOrLowPower() -> Bool {
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            return true
        }
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let powerSourceType = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() as String? else {
            return false
        }
        return powerSourceType == kIOPSBatteryPowerValue
    }

    // MARK: - 执行网络探测与变更通知

    private func executeFetch(reason: String) {
        fetchTask?.cancel()
        lastTriggerReason = reason
        state = .loading(previous: lastLoadedInfo)

        fetchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let info = try await self.ipService.fetchCurrentIPInfo()
                guard !Task.isCancelled else { return }

                // 检测最近一次查询出口 IP 是否发生变化
                if let previous = self.lastLoadedInfo, previous.ip != info.ip {
                    self.previousDistinctInfo = previous
                    if self.settings.notifyOnIPChange {
                        self.notificationManager.sendIPChangedNotification(from: previous, to: info)
                    }
                }

                self.lastLoadedInfo = info
                self.state = .loaded(info)
            } catch {
                guard !Task.isCancelled else { return }
                if !self.networkMonitor.isConnected {
                    self.state = .offline
                } else {
                    self.state = .failed(message: error.localizedDescription, previous: self.lastLoadedInfo)
                }
            }
        }
    }
}
