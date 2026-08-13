import Cocoa
import ServiceManagement

// Donation details
let kBoostyURL = "https://boosty.to/sibainka/donate"
let kUSDT      = "TNWBzxHYo6J4s5w9nJEQfGewY5ZguEDS6V"          // USDT (TRC-20)
let kBTC       = "bc1qxdtfga2d3g35fwkagu9nth7d7c08tjpah9w5t3"  // BTC

let isRU = (Locale.preferredLanguages.first?.lowercased().hasPrefix("ru")) ?? false
func L(_ ru: String, _ en: String) -> String { isRU ? ru : en }

let fm = FileManager.default
let home = fm.homeDirectoryForCurrentUser
let appSupport = home.appendingPathComponent("Library/Application Support/FolderTop", isDirectory: true)
let dylibDst = appSupport.appendingPathComponent("foldertop_hook.dylib")
let launchAgent = home.appendingPathComponent("Library/LaunchAgents/com.foldertop.plist")
let dylibPathString = dylibDst.path

@discardableResult
func run(_ launchPath: String, _ args: [String]) -> (code: Int32, out: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: launchPath)
    p.arguments = args
    let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
    do { try p.run() } catch { return (-1, "\(error)") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
}

// Escape paths for shell/XML substitution (paths may contain special chars).
func shQuote(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}
func xmlEscape(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;")
     .replacingOccurrences(of: "<", with: "&lt;")
     .replacingOccurrences(of: ">", with: "&gt;")
}

func amfiDisabled() -> Bool {
    // The flag's value matters: 0x0/0 means AMFI is ON, not disabled.
    let out = run("/usr/sbin/nvram", ["boot-args"]).out
    guard let r = out.range(of: "amfi_get_out_of_my_way=") else { return false }
    let val = out[r.upperBound...].prefix { !$0.isWhitespace && $0 != "\"" }
    return !val.isEmpty && val != "0x0" && val != "0"
}
func isEnabled() -> Bool {
    fm.fileExists(atPath: dylibDst.path) && fm.fileExists(atPath: launchAgent.path)
}
func hookLoadedInFinder() -> Bool {
    let pid = run("/usr/bin/pgrep", ["-x", "Finder"]).out.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !pid.isEmpty else { return false }
    return run("/usr/bin/vmmap", [pid]).out.contains("foldertop_hook.dylib")
}

enum InstallError: Error { case amfiOn, missingBundledDylib, copyFailed(String), signFailed(String) }

func bundledDylib() -> URL? {
    if let res = Bundle.main.resourceURL?.appendingPathComponent("foldertop_hook.dylib"),
       fm.fileExists(atPath: res.path) { return res }
    return nil
}
// Application Support is user-writable — the dylib could be swapped out.
// Restore it from the signed bundle before every injection.
@discardableResult
func refreshInstalledDylib() -> Bool {
    guard let src = bundledDylib(), let want = try? Data(contentsOf: src) else { return false }
    if let have = try? Data(contentsOf: dylibDst), have == want { return true }
    do {
        try fm.createDirectory(at: appSupport, withIntermediateDirectories: true)
        if fm.fileExists(atPath: dylibDst.path) { try fm.removeItem(at: dylibDst) }
        try fm.copyItem(at: src, to: dylibDst)
    } catch { return false }
    return run("/usr/bin/codesign", ["-s", "-", "--force", dylibDst.path]).code == 0
}
func writeLaunchAgent() throws {
    // If the app was deleted, the agent removes itself and the whole install.
    let appPath = Bundle.main.bundlePath
    let payload = "if [ ! -d \(shQuote(appPath)) ]; then rm -f \(shQuote(launchAgent.path)); rm -rf \(shQuote(appSupport.path)); launchctl unsetenv DYLD_INSERT_LIBRARIES; killall Finder; exit 0; fi; launchctl setenv DYLD_INSERT_LIBRARIES \(shQuote(dylibPathString)); killall Finder; sleep 2; launchctl unsetenv DYLD_INSERT_LIBRARIES"
    let plist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>Label</key><string>com.foldertop</string>
        <key>RunAtLoad</key><true/>
        <key>ProgramArguments</key>
        <array><string>/bin/sh</string><string>-c</string><string>\(xmlEscape(payload))</string></array>
    </dict>
    </plist>
    """
    try fm.createDirectory(at: launchAgent.deletingLastPathComponent(), withIntermediateDirectories: true)
    try plist.write(to: launchAgent, atomically: true, encoding: .utf8)
}
// setenv is visible to every process during these ~2s (the hook self-filters
// by bundle id). Call from a background thread only — it blocks on sleep.
func injectNow() {
    refreshInstalledDylib()
    run("/bin/launchctl", ["setenv", "DYLD_INSERT_LIBRARIES", dylibPathString])
    run("/usr/bin/killall", ["Finder"])
    Thread.sleep(forTimeInterval: 2.0)
    run("/bin/launchctl", ["unsetenv", "DYLD_INSERT_LIBRARIES"])
}
func enable() throws {
    guard amfiDisabled() else { throw InstallError.amfiOn }
    guard let src = bundledDylib() else { throw InstallError.missingBundledDylib }
    try fm.createDirectory(at: appSupport, withIntermediateDirectories: true)
    if fm.fileExists(atPath: dylibDst.path) { try? fm.removeItem(at: dylibDst) }
    do { try fm.copyItem(at: src, to: dylibDst) } catch { throw InstallError.copyFailed("\(error)") }
    let cs = run("/usr/bin/codesign", ["-s", "-", "--force", dylibDst.path])
    if cs.code != 0 { throw InstallError.signFailed(cs.out) }
    try writeLaunchAgent()
    // RunAtLoad injects and restarts Finder itself. Reload the agent; if load
    // didn't fire (already loaded), inject manually as a fallback.
    run("/bin/launchctl", ["unload", launchAgent.path])
    if run("/bin/launchctl", ["load", launchAgent.path]).code != 0 { injectNow() }
}
func disable() {
    run("/bin/launchctl", ["unload", launchAgent.path])
    try? fm.removeItem(at: launchAgent)
    try? fm.removeItem(at: dylibDst)
    run("/bin/launchctl", ["unsetenv", "DYLD_INSERT_LIBRARIES"])
    run("/usr/bin/killall", ["Finder"])
}
func uninstall() {
    disable()
    try? SMAppService.mainApp.unregister()
    try? fm.trashItem(at: Bundle.main.bundleURL, resultingItemURL: nil)
}

let recoveryText = L(
"""
Чтобы Perch мог работать, нужно один раз разрешить системе загружать
дополнение в Finder. Это делается в режиме восстановления.

1. Выключите Mac. Держите кнопку питания до «Загрузка параметров запуска».
2. Параметры → войдите администратором.
3. Утилиты → Утилита безопасной загрузки → выберите диск →
   Смягчённый режим безопасности.
4. Утилиты → Терминал:
       csrutil disable
       nvram boot-args="amfi_get_out_of_my_way=0x1"
5. Перезагрузитесь в обычную macOS и снова откройте Perch.

Отключить потом: тот же экран → Полная безопасность,
и в Терминале  sudo nvram -d boot-args
""",
"""
For Perch to work, allow the system to load a small add-on into
Finder once. This is done in Recovery mode.

1. Shut down. Hold the power button until “Loading startup options”.
2. Options → sign in as an administrator.
3. Utilities → Startup Security Utility → pick your disk →
   Reduced Security (Permissive).
4. Utilities → Terminal:
       csrutil disable
       nvram boot-args="amfi_get_out_of_my_way=0x1"
5. Reboot into normal macOS and open Perch again.

To turn it off later: same screen → Full Security,
and in Terminal  sudo nvram -d boot-args
""")

func appLaunchAtLogin() -> Bool { SMAppService.mainApp.status == .enabled }
func setAppLaunchAtLogin(_ on: Bool) {
    do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
    catch { NSLog("Perch login-item error: \(error)") }
}

final class Toggle: NSView {
    var isOn = false { didSet { needsDisplay = true } }
    var enabledState = true { didSet { needsDisplay = true } }
    var onToggle: (() -> Void)?
    override var intrinsicContentSize: NSSize { NSSize(width: 40, height: 24) }
    override func draw(_ dirty: NSRect) {
        let track = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        let base = isOn ? NSColor.systemGreen : NSColor(white: 0.38, alpha: 1)
        base.withAlphaComponent(enabledState ? 1 : 0.45).setFill()
        track.fill()
        let d = bounds.height - 4
        let x = isOn ? bounds.maxX - d - 2 : 2
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: x, y: 2, width: d, height: d)).fill()
    }
    override func mouseDown(with e: NSEvent) { if enabledState { isOn.toggle(); onToggle?() } }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var window: NSWindow!
    var donateWindow: NSWindow!
    var foldersToggle: Toggle!
    var loginToggle: Toggle!
    var statusBadge: NSTextField!
    var statusBadgeBox: NSView!
    var mainView: NSView!
    var donateView: NSView!
    var lastHookRunning = false   // cache: vmmap is costly, keep it off main
    var busy = false              // blocks a repeated click during enable/disable

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            if let url = Bundle.main.url(forResource: "menubarTemplate", withExtension: "png"),
               let img = NSImage(contentsOf: url) {
                img.isTemplate = true; img.size = NSSize(width: 18, height: 18); btn.image = img
            } else if let img = NSImage(systemSymbolName: "folder", accessibilityDescription: "Perch") {
                img.isTemplate = true; btn.image = img
            } else { btn.title = "Perch" }
        }
        rebuildMenu(); buildWindow(); showWindow()
    }

    func item(_ title: String, _ sel: Selector?, on: Bool = false, enabled: Bool = true) -> NSMenuItem {
        let m = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        if sel != nil { m.target = self }
        m.state = on ? .on : .off; m.isEnabled = enabled
        return m
    }
    func rebuildMenu() {
        let menu = NSMenu()
        let enabled = isEnabled(); let amfi = amfiDisabled()
        let head = item("Perch", nil, enabled: false)
        head.attributedTitle = NSAttributedString(string: "Perch",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
        menu.addItem(head); menu.addItem(.separator())
        menu.addItem(item(enabled ? L("Папки сверху: включено", "Folders on top: on")
                                   : L("Папки сверху: выключено", "Folders on top: off"),
                          #selector(toggleClicked), on: enabled, enabled: amfi || enabled))
        if enabled {
            // Use the cache instead of vmmap on main — otherwise menu/launch stalls.
            menu.addItem(item(lastHookRunning ? L("Работает в Finder ✓", "Running in Finder ✓")
                                              : L("Перезапустите Finder", "Restart Finder"),
                              nil, enabled: false))
        }
        if !amfi {
            menu.addItem(item(L("Нужна разовая настройка системы", "One-time system setup needed"),
                              #selector(showRecovery)))
        }
        menu.addItem(.separator())
        menu.addItem(item(L("Открыть окно Perch", "Open Perch window"), #selector(showWindow)))
        menu.addItem(item(L("Перезапустить Finder", "Restart Finder"), #selector(relaunchFinder)))
        menu.addItem(item(L("Запускать при входе", "Launch at login"),
                          #selector(toggleLoginItem), on: appLaunchAtLogin()))
        menu.addItem(item(L("Поддержать проект…", "Support the project…"), #selector(showDonate)))
        menu.addItem(item(L("Удалить Perch…", "Uninstall Perch…"), #selector(uninstallClicked)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L("Выйти", "Quit"),
                                action: #selector(NSApp.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func mkLabel(_ f: NSRect, _ t: String, size: CGFloat, bold: Bool = false,
                 color: NSColor = .labelColor) -> NSTextField {
        let l = NSTextField(frame: f); l.stringValue = t
        l.isEditable = false; l.isBordered = false; l.drawsBackground = false; l.textColor = color
        l.font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
        return l
    }
    func makeRow(_ card: NSView, _ title: String, _ right: NSView, y: CGFloat, divider: Bool) {
        let W: CGFloat = 392
        let lbl = mkLabel(NSRect(x: 14, y: y + 13, width: 240, height: 20), title, size: 14)
        card.addSubview(lbl)
        right.setFrameOrigin(NSPoint(x: W - 14 - right.frame.width,
                                     y: y + (46 - right.frame.height) / 2))
        card.addSubview(right)
        if divider {
            let d = NSView(frame: NSRect(x: 14, y: y, width: W - 28, height: 1))
            d.wantsLayer = true
            d.layer?.backgroundColor = NSColor.separatorColor.cgColor
            card.addSubview(d)
        }
    }
    func roundedFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        if let d = base.fontDescriptor.withDesign(.rounded) { return NSFont(descriptor: d, size: size) ?? base }
        return base
    }
    func makeCard(_ y: CGFloat, _ h: CGFloat) -> NSView {
        let card = NSView(frame: NSRect(x: 24, y: y, width: 392, height: h))
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.6).cgColor
        card.layer?.cornerRadius = 10
        return card
    }

    func buildWindow() {
        let WW: CGFloat = 440, HH: CGFloat = 340
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: WW, height: HH),
                         styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        w.title = "Perch"; w.center(); w.isReleasedWhenClosed = false
        let c = NSView(frame: NSRect(x: 0, y: 0, width: WW, height: HH))

        let title = mkLabel(NSRect(x: 20, y: HH - 54, width: WW - 40, height: 34), "Perch", size: 26)
        title.font = roundedFont(26, .bold); title.alignment = .center
        c.addSubview(title)

        let card = makeCard(HH - 54 - 14 - 138, 138)
        foldersToggle = Toggle(frame: NSRect(x: 0, y: 0, width: 40, height: 24))
        foldersToggle.onToggle = { [weak self] in self?.toggleClicked() }
        makeRow(card, L("Папки сверху", "Folders on top"), foldersToggle, y: 92, divider: true)
        loginToggle = Toggle(frame: NSRect(x: 0, y: 0, width: 40, height: 24))
        loginToggle.onToggle = { [weak self] in self?.toggleLoginItem() }
        makeRow(card, L("Запускать при входе", "Launch at login"), loginToggle, y: 46, divider: true)
        statusBadge = mkLabel(NSRect(x: 0, y: 4, width: 78, height: 15), "", size: 12)
        statusBadge.alignment = .center
        statusBadgeBox = NSView(frame: NSRect(x: 0, y: 0, width: 78, height: 24))
        statusBadgeBox.wantsLayer = true; statusBadgeBox.layer?.cornerRadius = 7
        statusBadgeBox.addSubview(statusBadge)
        makeRow(card, L("Состояние системы", "System status"), statusBadgeBox, y: 0, divider: false)
        c.addSubview(card)

        let btnRowY = card.frame.minY - 12 - 34
        let recBtn = NSButton(frame: NSRect(x: 24, y: btnRowY, width: 191, height: 34))
        recBtn.title = L("Как настроить…", "How to set up…"); recBtn.bezelStyle = .rounded
        recBtn.target = self; recBtn.action = #selector(showRecovery); c.addSubview(recBtn)
        let relBtn = NSButton(frame: NSRect(x: 225, y: btnRowY, width: 191, height: 34))
        relBtn.title = L("Перезапустить Finder", "Restart Finder"); relBtn.bezelStyle = .rounded
        relBtn.target = self; relBtn.action = #selector(relaunchFinder); c.addSubview(relBtn)

        let donateBtn = NSButton(frame: NSRect(x: 24, y: btnRowY - 44, width: 392, height: 34))
        donateBtn.bezelStyle = .rounded; donateBtn.target = self; donateBtn.action = #selector(showDonate)
        let heart = NSMutableAttributedString(string: "♥ ",
            attributes: [.foregroundColor: NSColor.systemPink, .font: NSFont.systemFont(ofSize: 13)])
        heart.append(NSAttributedString(string: L("Поддержать проект", "Support the project"),
            attributes: [.foregroundColor: NSColor.systemPink, .font: NSFont.systemFont(ofSize: 13)]))
        donateBtn.attributedTitle = heart
        c.addSubview(donateBtn)

        let unin = NSButton(frame: NSRect(x: (WW - 160) / 2, y: btnRowY - 44 - 30, width: 160, height: 22))
        unin.title = L("Удалить Perch", "Uninstall Perch"); unin.bezelStyle = .inline; unin.isBordered = false
        unin.contentTintColor = .tertiaryLabelColor; unin.font = NSFont.systemFont(ofSize: 12)
        unin.target = self; unin.action = #selector(uninstallClicked); c.addSubview(unin)

        mainView = c
        w.contentView = c; window = w
    }
    func setBadge(_ text: String, _ color: NSColor) {
        statusBadge.stringValue = text
        statusBadge.textColor = color
        statusBadgeBox.layer?.backgroundColor = color.withAlphaComponent(0.16).cgColor
    }
    func refreshWindow() {
        guard foldersToggle != nil else { return }
        let enabled = isEnabled(); let amfi = amfiDisabled()
        foldersToggle.isOn = enabled
        foldersToggle.enabledState = amfi || enabled
        loginToggle.isOn = appLaunchAtLogin()

        // Quick badge without vmmap; when enabled, refine asynchronously.
        if !amfi { setBadge(L("Настройка", "Setup"), .systemOrange) }
        else if enabled { setBadge(L("Проверка…", "Checking…"), .systemGray) }
        else { setBadge(L("Готово", "Ready"), .systemGreen) }
        if enabled && amfi { refreshRunningStatus() }
    }
    // Whether the hook is loaded in Finder (vmmap in background); cache it and refresh the menu.
    func refreshRunningStatus() {
        DispatchQueue.global(qos: .utility).async {
            let running = hookLoadedInFinder()
            DispatchQueue.main.async {
                guard isEnabled(), amfiDisabled() else { return }
                if running != self.lastHookRunning { self.lastHookRunning = running; self.rebuildMenu() }
                self.setBadge(running ? L("Работает", "Running") : L("Рестарт", "Restart"),
                              running ? .systemGreen : .systemOrange)
            }
        }
    }
    @objc func showWindow() {
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); refreshWindow()
    }

    func buildDonateView() -> NSView {
        let WW: CGFloat = 440, HH: CGFloat = 340
        let v = NSView(frame: NSRect(x: 0, y: 0, width: WW, height: HH))
        let back = NSButton(frame: NSRect(x: 12, y: HH - 32, width: 110, height: 24))
        back.title = L("‹ Назад", "‹ Back"); back.isBordered = false
        back.contentTintColor = .controlAccentColor; back.font = NSFont.systemFont(ofSize: 13)
        back.target = self; back.action = #selector(goBack); v.addSubview(back)

        let title = mkLabel(NSRect(x: 20, y: HH - 64, width: WW - 40, height: 30),
                            L("Поддержать", "Support"), size: 22)
        title.font = roundedFont(22, .bold); title.alignment = .center; v.addSubview(title)
        let sub = mkLabel(NSRect(x: 20, y: HH - 88, width: WW - 40, height: 18),
                          L("Проект бесплатный — спасибо!", "The app is free — thank you!"),
                          size: 12, color: .secondaryLabelColor)
        sub.alignment = .center; v.addSubview(sub)

        let card = makeCard(HH - 88 - 12 - 138, 138)
        makeRow(card, "Boosty",
                mkLabel(NSRect(x: 0, y: 0, width: 12, height: 20), "›", size: 18, color: .tertiaryLabelColor),
                y: 92, divider: true)
        let cu = NSButton(frame: NSRect(x: 0, y: 0, width: 100, height: 26))
        cu.title = L("Копировать", "Copy"); cu.bezelStyle = .rounded
        cu.target = self; cu.action = #selector(copyUSDT)
        makeRow(card, "USDT (TRC-20)", cu, y: 46, divider: true)
        let cb = NSButton(frame: NSRect(x: 0, y: 0, width: 100, height: 26))
        cb.title = L("Копировать", "Copy"); cb.bezelStyle = .rounded
        cb.target = self; cb.action = #selector(copyBTC)
        makeRow(card, "BTC", cb, y: 0, divider: false)
        v.addSubview(card)

        let hit = NSButton(frame: NSRect(x: card.frame.minX, y: card.frame.minY + 92, width: 392, height: 46))
        hit.title = ""; hit.isBordered = false; hit.isTransparent = true
        hit.target = self; hit.action = #selector(openBoosty); v.addSubview(hit)

        let uf = NSTextField(frame: NSRect(x: 24, y: card.frame.minY - 28, width: 392, height: 16))
        uf.stringValue = "USDT: \(kUSDT)"; uf.isEditable = false; uf.isBordered = false
        uf.drawsBackground = false; uf.isSelectable = true
        uf.font = NSFont.systemFont(ofSize: 10); uf.textColor = .tertiaryLabelColor; v.addSubview(uf)
        let bf = NSTextField(frame: NSRect(x: 24, y: card.frame.minY - 48, width: 392, height: 16))
        bf.stringValue = "BTC: \(kBTC)"; bf.isEditable = false; bf.isBordered = false
        bf.drawsBackground = false; bf.isSelectable = true
        bf.font = NSFont.systemFont(ofSize: 10); bf.textColor = .tertiaryLabelColor; v.addSubview(bf)
        return v
    }
    @objc func showDonate() {
        if donateView == nil { donateView = buildDonateView() }
        window.contentView = donateView
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc func goBack() {
        window.contentView = mainView; refreshWindow()
    }
    @objc func openBoosty() { if let u = URL(string: kBoostyURL) { NSWorkspace.shared.open(u) } }
    func copyStr(_ s: String) { let pb = NSPasteboard.general; pb.clearContents(); pb.setString(s, forType: .string) }
    @objc func copyUSDT() { copyStr(kUSDT) }
    @objc func copyBTC() { copyStr(kBTC) }

    func refreshAll() { rebuildMenu(); refreshWindow() }
    @objc func toggleClicked() {
        // Heavy (blocking) calls run in the background; busy blocks a repeated click.
        if busy { return }
        busy = true
        let turningOn = !isEnabled()
        foldersToggle?.enabledState = false
        DispatchQueue.global(qos: .userInitiated).async {
            var recovery = false
            var errMsg: String? = nil
            if turningOn {
                do { try enable() }
                catch InstallError.amfiOn { recovery = true }
                catch { errMsg = "\(error)" }
            } else {
                disable()
            }
            DispatchQueue.main.async {
                self.busy = false
                if recovery { self.showRecovery() }
                else if let m = errMsg { self.alert(L("Не удалось включить", "Couldn’t turn on"), m) }
                self.refreshAll()
            }
        }
    }
    @objc func relaunchFinder() {
        if busy { return }
        busy = true
        DispatchQueue.global(qos: .userInitiated).async {
            if isEnabled() && amfiDisabled() { injectNow() }
            else { run("/usr/bin/killall", ["Finder"]) }
            DispatchQueue.main.async { self.busy = false; self.refreshAll() }
        }
    }
    @objc func toggleLoginItem() { setAppLaunchAtLogin(!appLaunchAtLogin()); refreshAll() }
    @objc func showRecovery() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = L("Разовая настройка системы", "One-time system setup")
        let tf = NSTextField(wrappingLabelWithString: recoveryText)
        tf.alignment = .left
        tf.isSelectable = true
        tf.font = NSFont.systemFont(ofSize: 12)
        tf.preferredMaxLayoutWidth = 430
        tf.frame = NSRect(x: 0, y: 0, width: 430, height: tf.intrinsicContentSize.height)
        a.accessoryView = tf
        a.addButton(withTitle: "OK")
        a.runModal()
    }
    @objc func uninstallClicked() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = L("Удалить Perch?", "Uninstall Perch?")
        a.informativeText = L("Папки вернутся к обычному порядку, дополнение из Finder снимется, приложение уйдёт в корзину.",
                              "Folders go back to normal, the Finder add-on is removed, and the app is moved to Trash.")
        a.addButton(withTitle: L("Удалить", "Uninstall"))
        a.addButton(withTitle: L("Отмена", "Cancel"))
        a.alertStyle = .warning
        if a.runModal() == .alertFirstButtonReturn { uninstall(); NSApp.terminate(nil) }
    }
    func alert(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert(); a.messageText = title; a.informativeText = text
        a.addButton(withTitle: "OK"); a.runModal()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()