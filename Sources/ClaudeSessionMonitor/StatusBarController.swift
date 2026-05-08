import AppKit

final class StatusBarController {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()

    private let titleSummaryItem = NSMenuItem(title: "Initializing…", action: nil, keyEquivalent: "")
    private let projectionItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let tokenItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let burnItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let resetItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let costItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let lastUpdatedItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    var refreshHandler: (() -> Void)?

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "…"
            button.font = NSFont.menuBarFont(ofSize: 0)
        }
        buildMenu()
        statusItem.menu = menu
    }

    private func buildMenu() {
        titleSummaryItem.isEnabled = false
        projectionItem.isEnabled = false
        tokenItem.isEnabled = false
        burnItem.isEnabled = false
        resetItem.isEnabled = false
        costItem.isEnabled = false
        lastUpdatedItem.isEnabled = false

        menu.addItem(titleSummaryItem)
        menu.addItem(projectionItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(tokenItem)
        menu.addItem(burnItem)
        menu.addItem(resetItem)
        menu.addItem(costItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(lastUpdatedItem)
        menu.addItem(NSMenuItem.separator())

        let refresh = NSMenuItem(title: "Refresh now", action: #selector(refreshClicked), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        let openUsage = NSMenuItem(title: "Open claude.ai/settings/usage", action: #selector(openUsageClicked), keyEquivalent: "u")
        openUsage.target = self
        menu.addItem(openUsage)

        menu.addItem(NSMenuItem.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(quitClicked), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    func render(state: MonitorState) {
        guard let button = statusItem.button else { return }

        switch state {
        case .loading:
            button.attributedTitle = plain("…")
            titleSummaryItem.title = "Loading…"
            projectionItem.isHidden = true
            tokenItem.isHidden = true
            burnItem.isHidden = true
            resetItem.isHidden = true
            costItem.isHidden = true
        case .idle:
            button.attributedTitle = plain("—")
            titleSummaryItem.title = "No active session"
            projectionItem.isHidden = true
            tokenItem.isHidden = true
            burnItem.isHidden = true
            resetItem.isHidden = true
            costItem.isHidden = true
        case .error(let message):
            button.attributedTitle = colored("!", color: .systemRed)
            titleSummaryItem.title = "Error"
            projectionItem.isHidden = false
            projectionItem.title = message
            tokenItem.isHidden = true
            burnItem.isHidden = true
            resetItem.isHidden = true
            costItem.isHidden = true
        case .active(let snapshot):
            let pct = Int(snapshot.currentPercent.rounded())
            button.attributedTitle = colored("\(pct)%", color: color(forPercent: snapshot.currentPercent))
            titleSummaryItem.title = "Current session: \(formatPercent(snapshot.currentPercent))"
            projectionItem.isHidden = false
            projectionItem.title = "Projected at burn rate: \(formatPercent(snapshot.projectedPercent))"
            tokenItem.isHidden = false
            tokenItem.title = "Tokens: \(formatTokens(snapshot.totalTokens)) / \(formatTokens(snapshot.limit))"
            burnItem.isHidden = false
            if let burn = snapshot.burnTokensPerMinute {
                burnItem.title = "Burn: \(formatTokens(Int(burn))) tok/min"
            } else {
                burnItem.title = "Burn: —"
            }
            resetItem.isHidden = false
            resetItem.title = "Resets \(formatReset(snapshot.endTime))"
            costItem.isHidden = false
            if let projCost = snapshot.projectedTotalCost {
                costItem.title = String(format: "Cost: $%.2f (proj. $%.2f)", snapshot.costUSD, projCost)
            } else {
                costItem.title = String(format: "Cost: $%.2f", snapshot.costUSD)
            }
        }
        lastUpdatedItem.title = "Updated " + DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    }

    @objc private func refreshClicked() {
        refreshHandler?()
    }

    @objc private func openUsageClicked() {
        if let url = URL(string: "https://claude.ai/settings/usage") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quitClicked() {
        NSApp.terminate(nil)
    }

    private func plain(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.menuBarFont(ofSize: 0),
            .foregroundColor: NSColor.labelColor,
        ])
    }

    private func colored(_ text: String, color: NSColor) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.menuBarFont(ofSize: 0),
            .foregroundColor: color,
        ])
    }

    private func color(forPercent pct: Double) -> NSColor {
        switch pct {
        case ..<60: return .labelColor
        case ..<80: return .systemYellow
        case ..<95: return .systemOrange
        default: return .systemRed
        }
    }

    private func formatPercent(_ value: Double) -> String {
        if value >= 100 {
            return String(format: "%.0f%%", value)
        }
        return String(format: "%.1f%%", value)
    }

    private func formatTokens(_ value: Int) -> String {
        let v = Double(value)
        if v >= 1_000_000_000 { return String(format: "%.2fB", v / 1_000_000_000) }
        if v >= 1_000_000 { return String(format: "%.2fM", v / 1_000_000) }
        if v >= 1_000 { return String(format: "%.1fK", v / 1_000) }
        return "\(value)"
    }

    private func formatReset(_ date: Date) -> String {
        let timeStr = DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
        let interval = date.timeIntervalSinceNow
        if interval <= 0 { return "now" }
        let minutes = Int((interval / 60).rounded())
        if minutes < 60 { return "at \(timeStr) (in \(minutes)m)" }
        let hours = minutes / 60
        let rem = minutes % 60
        return "at \(timeStr) (in \(hours)h \(rem)m)"
    }
}

enum MonitorState {
    case loading
    case idle
    case active(SessionSnapshot)
    case error(String)
}
