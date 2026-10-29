import AppKit
import PetCore

final class ActionItem: NSMenuItem {
    var actionBlock: () -> Void
    init(_ title: String, checked: Bool = false, action: @escaping () -> Void) {
        actionBlock = action
        super.init(title: title, action: #selector(invoke), keyEquivalent: "")
        target = self; state = checked ? .on : .off
    }
    required init(coder: NSCoder) { fatalError("init(coder:) not supported") }
    @objc private func invoke() { actionBlock() }
}
struct SavedState: Codable { var pets: [PetInstance] }
final class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let catalog: Catalog
    let config: URL
    let monitor: Monitor
    var instances: [PetInstance] = []
    var windows: [UUID: PetPanel] = [:]
    var threads: [ThreadState] = []
    var connection = "Starting…"
    var statusItem: NSStatusItem!
    var hidden = false
    let demo: Bool
    var demoTimer: Timer?
    init(catalog: Catalog, config: URL, monitor: Monitor, demo: Bool) {
        self.catalog = catalog; self.config = config; self.monitor = monitor; self.demo = demo
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = MenuBarIcon.make()
        let menu = NSMenu(); menu.delegate = self; statusItem.menu = menu
        if let data = try? Data(contentsOf: config), let saved = try? JSONDecoder().decode(SavedState.self, from: data) { instances = saved.pets }
        else {
            let keys = ["codex", "dewey", "fireball"].filter { catalog.pets[$0] != nil }
            let chosen = keys.isEmpty ? Array(catalog.pets.keys.sorted().prefix(3)) : keys
            let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
            for (index, key) in chosen.enumerated() { instances.append(PetInstance(petID: key, threadID: "*", x: screen.maxX - Double(index + 1) * 150, y: screen.minY + 20)) }
        }
        for instance in instances { show(instance) }
        save()
        monitor.onUpdate = { [weak self] threads, diagnostic in
            guard let self, !self.demo else { return }
            self.threads = threads; self.connection = diagnostic; self.refresh()
        }
        if demo {
            connection = "Demo · no Codex activity is being monitored"
            var step = 0
            demoTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                let states: [PetStatus] = [.idle, .thinking, .working, .waiting, .failed, .interrupted, .completed]
                self?.threads = [ThreadState(id: "demo", name: "Demo thread", status: states[step % states.count])]
                step += 1; self?.refresh()
            }
        } else { monitor.start() }
        if let directory = option("--smoke") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self else { return }
                do {
                    let output = URL(fileURLWithPath: directory)
                    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                    for (id, panel) in self.windows {
                        guard let view = panel.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                        view.cacheDisplay(in: view.bounds, to: bitmap)
                        if let data = bitmap.representation(using: .png, properties: [:]) {
                            try data.write(to: output.appendingPathComponent("\(id).png"))
                        }
                    }
                    print("Rendered \(self.windows.count) pet windows to \(directory)")
                } catch { fputs("Smoke render failed: \(error)\n", stderr) }
                NSApp.terminate(nil)
            }
        }
        if catalog.pets.isEmpty { alert("No pets found", "Add pet folders containing pet.json and a spritesheet to \(catalog.directory.path), then choose Reload pets from the menu-bar icon. You can also use codex-harem --import-codex to copy your existing pets once.") }
    }
    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop(); demoTimer?.invalidate(); windows.values.forEach { ($0.contentView as? PetView)?.stop() }; save()
    }
    func show(_ instance: PetInstance) {
        guard let pet = catalog.pets[instance.petID] else { return }
        var safe = instance; safe.size = min(300, max(70, safe.size.isFinite ? safe.size : 140))
        if !safe.x.isFinite { safe.x = 100 }; if !safe.y.isFinite { safe.y = 100 }
        let panel = PetPanel(contentRect: NSRect(x: safe.x, y: safe.y, width: safe.size, height: safe.size + 24), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false; panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        let view = PetView(pet: pet, instance: safe); panel.contentView = view
        view.onPositionChange = { [weak self] origin, shouldSave in
            guard let self, let index = self.instances.firstIndex(where: { $0.id == instance.id }) else { return }
            self.instances[index].x = origin.x; self.instances[index].y = origin.y
            if shouldSave { self.save() }
        }
        view.menuBuilder = { [weak self] in self?.petMenu(instance.id) ?? NSMenu() }
        windows[instance.id] = panel; view.keepOnScreen()
        if !hidden { panel.orderFrontRegardless() }
        view.start(); refresh()
    }
    func refresh() {
        for instance in instances {
            (windows[instance.id]?.contentView as? PetView)?.status = Selection.status(for: instance.threadID, threads: threads)
        }
    }
    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        let title = NSMenuItem(title: "Codex Harem", action: nil, keyEquivalent: ""); menu.addItem(title)
        menu.addItem(NSMenuItem(title: connection, action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        let add = NSMenuItem(title: "Add pet", action: nil, keyEquivalent: ""), sub = NSMenu()
        for (id, pet) in catalog.pets.sorted(by: { $0.value.manifest.displayName < $1.value.manifest.displayName }) {
            sub.addItem(ActionItem(pet.manifest.displayName) { [weak self] in self?.add(id) })
        }
        add.submenu = sub; menu.addItem(add)
        menu.addItem(ActionItem("Open pet folder") { [weak self] in
            guard let self else { return }
            do {
                try FileManager.default.createDirectory(at: self.catalog.directory, withIntermediateDirectories: true)
                NSWorkspace.shared.open(self.catalog.directory)
            } catch { self.alert("Cannot open pet folder", error.localizedDescription) }
        })
        menu.addItem(ActionItem("Reload pets") { [weak self] in
            guard let self else { return }
            self.catalog.reload()
            for id in Array(self.windows.keys) { self.removeWindow(id) }
            for instance in self.instances { self.show(instance) }
            self.save()
        })
        for instance in instances {
            let item = NSMenuItem(title: catalog.pets[instance.petID]?.manifest.displayName ?? "Missing pet: \(instance.petID)", action: nil, keyEquivalent: "")
            item.submenu = petMenu(instance.id); menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(ActionItem(hidden ? "Show pets" : "Hide pets") { [weak self] in
            guard let self else { return }; self.hidden.toggle()
            for panel in self.windows.values { if self.hidden { panel.orderOut(nil) } else { panel.orderFrontRegardless() } }
        })
        menu.addItem(ActionItem("Arrange pets") { [weak self] in self?.arrange() })
        if !catalog.errors.isEmpty {
            menu.addItem(ActionItem("Pet loading warnings (\(catalog.errors.count))") { [weak self] in self?.alert("Pet loading warnings", self?.catalog.errors.joined(separator: "\n") ?? "") })
        }
        menu.addItem(ActionItem("Quit") { NSApp.terminate(nil) })
    }
    func petMenu(_ id: UUID) -> NSMenu {
        let menu = NSMenu()
        guard let instance = instances.first(where: { $0.id == id }) else { return menu }
        menu.addItem(NSMenuItem(title: "Status: \(Selection.status(for: instance.threadID, threads: threads).rawValue)", action: nil, keyEquivalent: ""))
        menu.addItem(ActionItem("Follow latest thread", checked: instance.threadID == nil) { [weak self] in self?.bind(id, to: nil) })
        menu.addItem(ActionItem("Follow all threads", checked: instance.threadID == "*") { [weak self] in self?.bind(id, to: "*") })
        let item = NSMenuItem(title: "Follow thread", action: nil, keyEquivalent: ""), sub = NSMenu()
        for thread in threads.prefix(64) {
            sub.addItem(ActionItem("\(thread.name.prefix(55)) · \(thread.status.rawValue)", checked: instance.threadID == thread.id) { [weak self] in self?.bind(id, to: thread.id) })
        }
        item.submenu = sub; menu.addItem(item)
        let size = NSMenuItem(title: "Size", action: nil, keyEquivalent: ""), sizes = NSMenu()
        for value in [100.0, 140.0, 200.0, 260.0] {
            sizes.addItem(ActionItem("\(Int(value)) pt", checked: instance.size == value) { [weak self] in
                guard let self, let index = self.instances.firstIndex(where: { $0.id == id }) else { return }
                self.instances[index].size = value; self.removeWindow(id); self.show(self.instances[index]); self.save()
            })
        }
        size.submenu = sizes; menu.addItem(size)
        let speed = NSMenuItem(title: "Animation speed", action: nil, keyEquivalent: ""), speeds = NSMenu()
        for (label, value) in [("Slow (40%)", 0.4), ("Relaxed (65%, default)", 0.65), ("Original (100%)", 1.0), ("Fast (125%)", 1.25)] {
            speeds.addItem(ActionItem(label, checked: instance.playbackSpeed == value) { [weak self] in
                guard let self, let index = self.instances.firstIndex(where: { $0.id == id }) else { return }
                self.instances[index].animationSpeed = value
                if let view = self.windows[id]?.contentView as? PetView {
                    view.instance = self.instances[index]; view.resetPlayback()
                }
                self.save()
            })
        }
        speed.submenu = speeds; menu.addItem(speed)
        menu.addItem(ActionItem("Walk around", checked: instance.walksAround) { [weak self] in
            guard let self, let index = self.instances.firstIndex(where: { $0.id == id }) else { return }
            self.instances[index].walksAround.toggle()
            if let view = self.windows[id]?.contentView as? PetView {
                view.instance = self.instances[index]
                if !view.instance.walksAround { view.cancelWalking() }
            }
            self.save()
        })
        menu.addItem(.separator())
        menu.addItem(ActionItem("Remove pet") { [weak self] in self?.removeWindow(id); self?.instances.removeAll { $0.id == id }; self?.save() })
        return menu
    }
    func removeWindow(_ id: UUID) { (windows[id]?.contentView as? PetView)?.stop(); windows[id]?.close(); windows[id] = nil }
    func bind(_ id: UUID, to thread: String?) {
        guard let index = instances.firstIndex(where: { $0.id == id }) else { return }
        instances[index].threadID = thread
        (windows[id]?.contentView as? PetView)?.instance = instances[index]
        save(); refresh()
    }
    func add(_ pet: String) {
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let instance = PetInstance(petID: pet, threadID: "*", x: screen.midX + Double.random(in: -150...150), y: screen.minY + 30)
        instances.append(instance); show(instance); save()
    }
    func arrange() {
        let screen = NSScreen.main?.visibleFrame ?? .zero
        var x = screen.maxX, y = screen.minY + 20.0, rowHeight = 0.0
        for index in instances.indices {
            (windows[instances[index].id]?.contentView as? PetView)?.cancelWalking()
            let size = instances[index].size
            if x - size < screen.minX { x = screen.maxX; y += rowHeight + 10; rowHeight = 0 }
            x -= size + 8; rowHeight = max(rowHeight, size + 24)
            instances[index].x = x; instances[index].y = y
            windows[instances[index].id]?.setFrameOrigin(NSPoint(x: x, y: y))
            (windows[instances[index].id]?.contentView as? PetView)?.instance = instances[index]
        }
        save()
    }
    func save() {
        do {
            try FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(SavedState(pets: instances)).write(to: config, options: .atomic)
        } catch { connection = "Could not save pet settings: \(error.localizedDescription)" }
    }
    func alert(_ title: String, _ detail: String) {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = detail; alert.runModal()
    }
}
