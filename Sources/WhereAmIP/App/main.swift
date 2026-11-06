import AppKit
import Foundation

// 支持通过 `--check` 或 `--cli` 参数在终端快速验证探测链路与国旗转换
if CommandLine.arguments.contains("--check") || CommandLine.arguments.contains("--cli") {
    Task.detached {
        print("🔍 [WhereAmIP] 正在探测当前公网出口 IP 与国家归属地...")
        let startTime = Date()
        do {
            let info = try await IPService.shared.fetchCurrentIPInfo()
            let elapsedMs = Int(Date().timeIntervalSince(startTime) * 1000)
            print("✅ 探测成功 (\(elapsedMs) ms):")
            print("   状态栏预览 : \(info.flagEmoji) \(info.countryCode)")
            print("   公网 IP    : \(info.ip)")
            print("   国家/地区  : \(info.flagEmoji) \(info.localizedCountryName) (\(info.countryCode))")
            if let loc = info.locationDetail {
                print("   省市位置   : \(loc)")
            }
            if let isp = info.ispDetail {
                print("   运营商/ASN : \(isp)")
            }
            print("   数据源     : \(info.source)")
            fflush(stdout)
            exit(0)
        } catch {
            print("❌ 探测失败: \(error.localizedDescription)")
            fflush(stdout)
            exit(1)
        }
    }
    dispatchMain()
}

// 启动 macOS 状态栏常驻应用
let app = NSApplication.shared
let delegate = MainActor.assumeIsolated {
    AppDelegate()
}
app.delegate = delegate
app.run()
