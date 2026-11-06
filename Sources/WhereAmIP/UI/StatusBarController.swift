import AppKit
import Foundation

/// macOS 顶部状态栏图标与下拉菜单控制器
@MainActor
public final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu: NSMenu
    private let scheduler: RefreshScheduler
    private let settings = AppSettings.shared

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    public init(scheduler: RefreshScheduler) {
        self.scheduler = scheduler
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.menu = NSMenu()
        super.init()

        self.menu.delegate = self
        self.statusItem.menu = self.menu

        setupBindings()
        updateStatusBarButton(with: scheduler.state)
        rebuildMenu()
    }

    private func setupBindings() {
        scheduler.onStateChange = { [weak self] newState in
            guard let self else { return }
            self.updateStatusBarButton(with: newState)
            self.rebuildMenu()
        }

        settings.onChange = { [weak self] in
            guard let self else { return }
            self.scheduler.reloadTimerSettings()
            self.updateStatusBarButton(with: self.scheduler.state)
            self.rebuildMenu()
        }
    }

    // MARK: - 状态栏图标文字渲染

    private func updateStatusBarButton(with state: IPFetchState) {
        guard let button = statusItem.button else { return }
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)

        switch state {
        case .loading(let previous):
            if let info = previous {
                // 有缓存时保持平稳显示，不闪烁
                button.title = settings.displayMode.format(info: info)
                button.toolTip = "WhereAmIP - 正在后台刷新... (\(info.ip))"
            } else {
                button.title = "🌐 …"
                button.toolTip = "WhereAmIP - 正在探测公网 IP..."
            }

        case .loaded(let info):
            button.title = settings.displayMode.format(info: info)
            button.toolTip = "\(info.flagEmoji) \(info.localizedCountryName) (\(info.countryCode)) - \(info.ip)"

        case .offline:
            button.title = "⚠️ 离线"
            button.toolTip = "WhereAmIP - 当前网络未连接"

        case .failed(let message, let previous):
            if let info = previous {
                button.title = settings.displayMode.format(info: info)
                button.toolTip = "WhereAmIP - 上次刷新失败: \(message)"
            } else {
                button.title = "🌐 --"
                button.toolTip = "WhereAmIP - 探测失败: \(message)"
            }
        }
    }

    // MARK: - NSMenuDelegate (第三层：展开菜单时触发 TTL 校验)

    public func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
        scheduler.triggerOnMenuOpen()
    }

    // MARK: - 构建下拉菜单

    private func rebuildMenu() {
        menu.removeAllItems()

        let state = scheduler.state

        // 1. 顶部归属地概览区
        if let info = state.currentInfo {
            let countryTitle = "\(info.flagEmoji)  \(info.localizedCountryName) (\(info.countryCode))"
            let headerItem = NSMenuItem(title: countryTitle, action: nil, keyEquivalent: "")
            let attrTitle = NSAttributedString(
                string: countryTitle,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
                    .foregroundColor: NSColor.labelColor
                ]
            )
            headerItem.attributedTitle = attrTitle
            menu.addItem(headerItem)

            // IP 行（点击可直接复制）
            let ipItem = NSMenuItem(
                title: "🌐  公网 IP:  \(info.ip)",
                action: #selector(copyIPAddress),
                keyEquivalent: ""
            )
            ipItem.target = self
            ipItem.toolTip = "点击复制 IP 地址"
            menu.addItem(ipItem)

            // 省市位置行
            if let location = info.locationDetail {
                let locItem = makeInfoMenuItem(text: "📍  位置:  \(location)")
                menu.addItem(locItem)
            }

            // 运营商与 ASN 行
            if let isp = info.ispDetail {
                let ispItem = makeInfoMenuItem(text: "🏢  运营商:  \(isp)")
                menu.addItem(ispItem)
            }

            // 若本次会话内发生过 IP 变更，展示上次的旧 IP 供比对
            if let prev = scheduler.previousDistinctInfo {
                let prevText = "🔀  上次出口:  \(prev.flagEmoji) \(prev.countryCode) · \(prev.ip)"
                menu.addItem(makeSubtleMenuItem(text: prevText))
            }

            // 更新时间与数据源行
            let timeStr = timeFormatter.string(from: info.fetchedAt)
            let elapsed = Int(max(0, Date().timeIntervalSince(info.fetchedAt)))
            let elapsedText = elapsed < 5 ? "刚刚" : "\(elapsed)秒前"
            var statusPrefix = "🕒  更新于 \(timeStr) (\(elapsedText)) · 源: \(info.source)"
            if case .loading = state {
                statusPrefix = "⏳  正在刷新... (上次: \(timeStr) · \(info.source))"
            } else if case .failed = state {
                statusPrefix = "⚠️  刷新异常，显示缓存 (\(timeStr) · \(info.source))"
            }
            menu.addItem(makeSubtleMenuItem(text: statusPrefix))
        } else {
            // 尚无缓存数据时的状态展示
            switch state {
            case .loading:
                menu.addItem(makeInfoMenuItem(text: "⏳  正在探测当前公网 IP 与国家属地..."))
            case .offline:
                menu.addItem(makeInfoMenuItem(text: "⚠️  当前网络已断开，等待网络连接恢复"))
            case .failed(let message, _):
                menu.addItem(makeInfoMenuItem(text: "❌  探测失败: \(message)"))
            case .loaded:
                break
            }
        }

        menu.addItem(.separator())

        // 2. 快捷操作区
        let copyIPItem = NSMenuItem(
            title: "复制公网 IP",
            action: #selector(copyIPAddress),
            keyEquivalent: "c"
        )
        copyIPItem.target = self
        copyIPItem.isEnabled = (state.currentInfo != nil)
        menu.addItem(copyIPItem)

        let copyAllItem = NSMenuItem(
            title: "复制完整归属地信息",
            action: #selector(copyFullDetails),
            keyEquivalent: "C"
        )
        copyAllItem.keyEquivalentModifierMask = [.command, .shift]
        copyAllItem.target = self
        copyAllItem.isEnabled = (state.currentInfo != nil)
        menu.addItem(copyAllItem)

        let refreshItem = NSMenuItem(
            title: "立即刷新",
            action: #selector(manualRefresh),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(.separator())

        // 3. 个性化设置子菜单
        menu.addItem(buildDisplayModeSubmenu())
        menu.addItem(buildRefreshPresetSubmenu())

        let notifyItem = NSMenuItem(
            title: "出口 IP 变动时弹出通知",
            action: #selector(toggleNotifyOnIPChange),
            keyEquivalent: ""
        )
        notifyItem.target = self
        notifyItem.state = settings.notifyOnIPChange ? .on : .off
        menu.addItem(notifyItem)

        menu.addItem(.separator())

        // 4. 退出
        let quitItem = NSMenuItem(
            title: "退出 WhereAmIP",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func makeInfoMenuItem(text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        let attr = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.labelColor
            ]
        )
        item.attributedTitle = attr
        return item
    }

    private func makeSubtleMenuItem(text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        let attr = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        item.attributedTitle = attr
        return item
    }

    private func buildDisplayModeSubmenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "状态栏显示样式", action: nil, keyEquivalent: "")
        let sub = NSMenu(title: "状态栏显示样式")
        let current = settings.displayMode

        for mode in DisplayMode.allCases {
            let item = NSMenuItem(
                title: mode.title,
                action: #selector(selectDisplayMode(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = mode.rawValue
            item.state = (mode == current) ? .on : .off
            sub.addItem(item)
        }

        parent.submenu = sub
        return parent
    }

    private func buildRefreshPresetSubmenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "自动刷新策略", action: nil, keyEquivalent: "")
        let sub = NSMenu(title: "自动刷新策略")
        let current = settings.refreshPreset

        for preset in RefreshPreset.allCases {
            let item = NSMenuItem(
                title: preset.title,
                action: #selector(selectRefreshPreset(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = preset.rawValue
            item.state = (preset == current) ? .on : .off
            sub.addItem(item)
        }

        sub.addItem(.separator())

        let effectiveSeconds = Int(scheduler.currentEffectivePollingInterval())
        let powerModeText = scheduler.isRunningOnBatteryOrLowPower()
            ? "🔋 当前为电池/低电量模式，轮询自动降频至 \(effectiveSeconds / 60) 分钟"
            : "🔌 当前为电源供电，后台轮询间隔 \(effectiveSeconds / 60) 分钟"
        sub.addItem(makeSubtleMenuItem(text: powerModeText))
        sub.addItem(makeSubtleMenuItem(text: "⚡ 网卡/VPN/系统代理切换时始终毫秒级感知(1.5s防抖)"))

        parent.submenu = sub
        return parent
    }

    // MARK: - 菜单交互事件

    @objc private func copyIPAddress() {
        guard let info = scheduler.state.currentInfo else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(info.ip, forType: .string)
    }

    @objc private func copyFullDetails() {
        guard let info = scheduler.state.currentInfo else { return }
        var lines: [String] = [
            "IP: \(info.ip)",
            "国家/地区: \(info.flagEmoji) \(info.localizedCountryName) (\(info.countryCode))"
        ]
        if let location = info.locationDetail {
            lines.append("位置: \(location)")
        }
        if let isp = info.ispDetail {
            lines.append("运营商: \(isp)")
        }
        lines.append("数据源: \(info.source)")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    @objc private func manualRefresh() {
        scheduler.triggerManualRefresh()
    }

    @objc private func selectDisplayMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = DisplayMode(rawValue: raw) else { return }
        settings.displayMode = mode
    }

    @objc private func selectRefreshPreset(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let preset = RefreshPreset(rawValue: raw) else { return }
        settings.refreshPreset = preset
    }

    @objc private func toggleNotifyOnIPChange() {
        settings.notifyOnIPChange.toggle()
    }

    @objc private func quitApp() {
        scheduler.stop()
        NSApplication.shared.terminate(nil)
    }
}
