// Messag8 (macOS) - Envoie du texte en plein écran sur un 2e moniteur, en temps réel.
// Compilation : bash build.sh  (nécessite les outils de ligne de commande Xcode : xcode-select --install)
import Cocoa

// MARK: - Réglages (sauvegardés automatiquement)
final class Settings {
    private let d = UserDefaults.standard
    var fontName: String
    var size: CGFloat
    var bold: Bool
    var autoFit: Bool
    var fore: NSColor
    var back: NSColor
    var align: Int          // 0 gauche, 1 centre, 2 droite
    var live: Bool
    var flashCount: Int
    var flashSpeed: Int     // ms
    var beep: Bool
    var screenID: String

    init() {
        let d = UserDefaults.standard
        d.register(defaults: [
            "fontName": "Helvetica", "size": 120.0, "bold": true, "autoFit": true,
            "align": 1, "live": true, "flashCount": 4, "flashSpeed": 120,
            "beep": false, "screenID": ""
        ])
        fontName = d.string(forKey: "fontName") ?? "Helvetica"
        size = CGFloat(d.double(forKey: "size"))
        bold = d.bool(forKey: "bold")
        autoFit = false   // taille fixe : les caractères gardent toujours la même grosseur
        align = d.integer(forKey: "align")
        live = d.bool(forKey: "live")
        flashCount = d.integer(forKey: "flashCount")
        flashSpeed = d.integer(forKey: "flashSpeed")
        beep = d.bool(forKey: "beep")
        screenID = d.string(forKey: "screenID") ?? ""
        fore = Settings.color(d.array(forKey: "fore") as? [Double]) ?? .white
        back = Settings.color(d.array(forKey: "back") as? [Double]) ?? .black
    }

    static func color(_ a: [Double]?) -> NSColor? {
        guard let a = a, a.count == 4 else { return nil }
        return NSColor(srgbRed: CGFloat(a[0]), green: CGFloat(a[1]), blue: CGFloat(a[2]), alpha: CGFloat(a[3]))
    }

    static func comps(_ c: NSColor) -> [Double] {
        let s = c.usingColorSpace(.sRGB) ?? NSColor.white
        return [Double(s.redComponent), Double(s.greenComponent), Double(s.blueComponent), Double(s.alphaComponent)]
    }

    func save() {
        d.set(fontName, forKey: "fontName")
        d.set(Double(size), forKey: "size")
        d.set(bold, forKey: "bold")
        d.set(autoFit, forKey: "autoFit")
        d.set(align, forKey: "align")
        d.set(live, forKey: "live")
        d.set(flashCount, forKey: "flashCount")
        d.set(flashSpeed, forKey: "flashSpeed")
        d.set(beep, forKey: "beep")
        d.set(screenID, forKey: "screenID")
        d.set(Settings.comps(fore), forKey: "fore")
        d.set(Settings.comps(back), forKey: "back")
    }
}

// MARK: - Rendu (partagé entre l'aperçu et l'écran participant)
enum Renderer {
    static func font(_ s: Settings, _ size: CGFloat) -> NSFont {
        let fm = NSFontManager.shared
        let sz = max(1, size)
        if s.bold, let f = fm.font(withFamily: s.fontName, traits: .boldFontMask, weight: 9, size: sz) { return f }
        if let f = fm.font(withFamily: s.fontName, traits: [], weight: 5, size: sz) { return f }
        return s.bold ? NSFont.boldSystemFont(ofSize: sz) : NSFont.systemFont(ofSize: sz)
    }

    static func attrs(_ s: Settings, _ size: CGFloat, _ color: NSColor) -> [NSAttributedString.Key: Any] {
        let ps = NSMutableParagraphStyle()
        ps.alignment = s.align == 0 ? .left : (s.align == 2 ? .right : .center)
        ps.lineBreakMode = .byWordWrapping
        return [.font: font(s, size), .foregroundColor: color, .paragraphStyle: ps]
    }

    static func measure(_ text: String, _ a: [NSAttributedString.Key: Any], _ width: CGFloat) -> NSSize {
        return (text as NSString).boundingRect(
            with: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: a).size
    }

    static func fits(_ text: String, _ s: Settings, _ size: CGFloat, _ inner: NSRect) -> Bool {
        let a = attrs(s, size, .white)
        if measure(text, a, inner.width).height > inner.height { return false }
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        for w in words {
            if (w as NSString).size(withAttributes: a).width > inner.width { return false }
        }
        return true
    }

    static func draw(in area: NSRect, text: String, s: Settings, scale: CGFloat, inverted: Bool, hidden: Bool) {
        let back = inverted ? s.fore : s.back
        let fore = inverted ? s.back : s.fore
        back.setFill()
        area.fill()
        if hidden || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }

        let inner = area.insetBy(dx: area.width * 0.04, dy: area.height * 0.05)
        guard inner.width > 4, inner.height > 4 else { return }

        // Taille fixe choisie par l'utilisateur ; si le texte dépasse l'écran,
        // on réduit la police juste assez pour qu'il rentre.
        var size = s.size * scale
        if !fits(text, s, size, inner) {
            var lo: CGFloat = 2
            var hi: CGFloat = size
            for _ in 0..<14 {
                let mid = (lo + hi) / 2
                if fits(text, s, mid, inner) { lo = mid } else { hi = mid }
            }
            size = lo
        }

        let a = attrs(s, size, fore)
        let h = measure(text, a, inner.width).height
        let r = NSRect(x: inner.minX, y: inner.midY - h / 2, width: inner.width, height: h)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: area).addClip()
        (text as NSString).draw(in: r, withAttributes: a)
        NSGraphicsContext.restoreGraphicsState()
    }
}

// MARK: - Vues / fenêtres
final class CanvasView: NSView {
    var painter: ((NSRect) -> Void)?
    override var isOpaque: Bool { return true }
    override func draw(_ dirtyRect: NSRect) { painter?(bounds) }
}

final class DisplayWindow: NSWindow {
    override var canBecomeKey: Bool { return styleMask.contains(.titled) }
    override var canBecomeMain: Bool { return false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return styleMask.contains(.titled) ? super.constrainFrameRect(frameRect, to: screen) : frameRect
    }
}

final class ColorButton: NSButton {
    init(_ title: String, color: NSColor, textColor: NSColor = .white, fontSize: CGFloat = 14, height: CGFloat = 40,
         target: AnyObject?, action: Selector) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        self.target = target
        self.action = action
        isBordered = false
        wantsLayer = true
        layer?.backgroundColor = color.cgColor
        layer?.cornerRadius = 8
        let ps = NSMutableParagraphStyle()
        ps.alignment = .center
        attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: textColor, .font: NSFont.boldSystemFont(ofSize: fontSize), .paragraphStyle: ps])
        heightAnchor.constraint(equalToConstant: height).isActive = true
    }
    required init?(coder: NSCoder) { fatalError("non utilisé") }
    override var isEnabled: Bool { didSet { alphaValue = isEnabled ? 1 : 0.4 } }
}

final class NumberControl: NSStackView {
    let field = NSTextField()
    let stepper = NSStepper()
    var onChange: ((Double) -> Void)?

    init(min: Double, max: Double, step: Double, width: CGFloat) {
        super.init(frame: .zero)
        orientation = .horizontal
        spacing = 2
        stepper.minValue = min
        stepper.maxValue = max
        stepper.increment = step
        stepper.valueWraps = false
        let nf = NumberFormatter()
        nf.minimum = NSNumber(value: min)
        nf.maximum = NSNumber(value: max)
        nf.allowsFloats = false
        field.formatter = nf
        (field.cell as? NSTextFieldCell)?.sendsActionOnEndEditing = true
        field.widthAnchor.constraint(equalToConstant: width).isActive = true
        field.target = self
        field.action = #selector(fieldChanged)
        stepper.target = self
        stepper.action = #selector(stepped)
        addArrangedSubview(field)
        addArrangedSubview(stepper)
    }
    required init?(coder: NSCoder) { fatalError("non utilisé") }

    var value: Double {
        get { return stepper.doubleValue }
        set { stepper.doubleValue = newValue; field.integerValue = Int(newValue) }
    }
    @objc func fieldChanged() {
        let v = Swift.min(stepper.maxValue, Swift.max(stepper.minValue, field.doubleValue))
        value = v
        onChange?(v)
    }
    @objc func stepped() {
        field.integerValue = Int(stepper.doubleValue)
        onChange?(stepper.doubleValue)
    }
}

// MARK: - Contrôleur principal
final class Controller: NSObject, NSTextViewDelegate, NSWindowDelegate {
    let s = Settings()
    var shown = ""
    var inverted = false
    var hiddenText = false
    var flashTicks = 0
    var flashTimer: Timer?
    var loading = true
    var screens: [NSScreen] = []
    var keyMonitor: Any?

    var window: NSWindow!
    var display: DisplayWindow?
    let displayView = CanvasView()
    let preview = CanvasView()
    var textView: NSTextView!

    let screenPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let fontPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let alignPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let foreWell = NSColorWell()
    let backWell = NSColorWell()
    let sizeCtl = NumberControl(min: 8, max: 1500, step: 10, width: 60)
    let flashCountCtl = NumberControl(min: 1, max: 30, step: 1, width: 36)
    let flashSpeedCtl = NumberControl(min: 40, max: 1000, step: 20, width: 48)
    let logoView = NSImageView()
    var backChecks: [NSButton] = [], foreChecks: [NSButton] = []
    let backColors: [NSColor] = [.black, .white, NSColor(srgbRed: 0, green: 177.0 / 255, blue: 64.0 / 255, alpha: 1)]
    let foreColors: [NSColor] = [.white, .black, NSColor(srgbRed: 1, green: 220.0 / 255, blue: 0, alpha: 1)]
    var chkBold: NSButton!, chkLive: NSButton!, chkBeep: NSButton!, chkHide: NSButton!
    var btnShow: NSButton!, btnSend: ColorButton!
    let status = NSTextField(wrappingLabelWithString: "")

    func start() {
        buildMenu()
        buildWindow()
        applySettings()
        refreshScreens()
        loading = false

        displayView.painter = { [weak self] b in
            guard let self = self else { return }
            Renderer.draw(in: b, text: self.shown, s: self.s, scale: 1, inverted: self.inverted, hidden: self.hiddenText)
        }
        preview.painter = { [weak self] b in self?.paintPreview(b) }

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.refreshScreens()
            if let d = self.display, d.isVisible { self.placeDisplay() }
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self = self else { return e }
            switch e.keyCode {
            case 96: self.flash(nil); return nil                       // F5
            case 100: self.toggleHide(nil); return nil                 // F8
            case 101: self.clearAll(nil); return nil                   // F9
            case 36, 76:                                               // Retour
                if e.modifierFlags.contains(.command) { self.sendText(nil); return nil }
            default: break
            }
            return e
        }

        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
        showDisplay()
    }

    // MARK: Menu
    func buildMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quitter Messag8", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "Édition")
        edit.addItem(withTitle: "Annuler", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Rétablir", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Couper", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copier", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Coller", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Tout sélectionner", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit

        let cmdItem = NSMenuItem()
        main.addItem(cmdItem)
        let cmd = NSMenu(title: "Commandes")
        func add(_ t: String, _ a: Selector, _ k: String) {
            let i = NSMenuItem(title: t, action: a, keyEquivalent: k)
            i.target = self
            cmd.addItem(i)
        }
        add("Envoyer", #selector(sendText(_:)), "\r")
        add("Flash", #selector(flash(_:)), "f")
        add("Masquer / afficher le texte", #selector(toggleHide(_:)), "b")
        add("Effacer", #selector(clearAll(_:)), "k")
        cmd.addItem(.separator())
        add("Afficher / masquer l'écran participant", #selector(toggleDisplay(_:)), "e")
        cmdItem.submenu = cmd

        NSApp.mainMenu = main
    }

    // MARK: Interface
    func header(_ t: String) -> NSTextField {
        let l = NSTextField(labelWithString: t)
        l.font = NSFont.boldSystemFont(ofSize: 13)
        l.setContentHuggingPriority(.required, for: .vertical)
        return l
    }
    func label(_ t: String) -> NSTextField { return NSTextField(labelWithString: t) }
    func row(_ v: [NSView]) -> NSStackView {
        let r = NSStackView(views: v)
        r.orientation = .horizontal
        r.spacing = 6
        r.alignment = .centerY
        return r
    }
    func check(_ t: String) -> NSButton {
        return NSButton(checkboxWithTitle: t, target: self, action: #selector(optionChanged(_:)))
    }

    func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 880),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Messag8"
        window.minSize = NSSize(width: 900, height: 820)
        window.isReleasedWhenClosed = false
        window.delegate = self
        let content = window.contentView!

        // --- Colonne gauche : texte + aperçu
        let scroll = NSTextView.scrollableTextView()
        scroll.borderType = .bezelBorder
        textView = scroll.documentView as? NSTextView
        textView.font = NSFont.systemFont(ofSize: 22)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.delegate = self

        let h1 = header("Message à envoyer")
        let h2 = header("Aperçu de l'écran participant")
        let left = NSStackView(views: [h1, scroll, h2, preview])
        left.orientation = .vertical
        left.alignment = .leading
        left.distribution = .fill
        left.spacing = 6
        left.setCustomSpacing(14, after: scroll)
        left.translatesAutoresizingMaskIntoConstraints = false
        scroll.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .vertical)
        preview.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .vertical)
        content.addSubview(left)
        scroll.widthAnchor.constraint(equalTo: left.widthAnchor).isActive = true
        preview.widthAnchor.constraint(equalTo: left.widthAnchor).isActive = true
        scroll.heightAnchor.constraint(equalTo: preview.heightAnchor, multiplier: 0.8).isActive = true

        // --- Colonne droite : options
        screenPopup.target = self
        screenPopup.action = #selector(screenChanged(_:))
        btnShow = NSButton(title: "Masquer l'écran participant", target: self, action: #selector(toggleDisplay(_:)))

        fontPopup.addItems(withTitles: NSFontManager.shared.availableFontFamilies.sorted())
        fontPopup.target = self
        fontPopup.action = #selector(optionChanged(_:))

        chkBold = check("Gras")
        sizeCtl.onChange = { [weak self] v in
            guard let self = self, !self.loading else { return }
            self.s.size = CGFloat(v)
            self.refresh()
        }
        backChecks = ["Noir", "Blanc", "Vert"].map {
            NSButton(checkboxWithTitle: $0, target: self, action: #selector(colorCheck(_:)))
        }
        foreChecks = ["Blanc", "Noir", "Jaune"].map {
            NSButton(checkboxWithTitle: $0, target: self, action: #selector(colorCheck(_:)))
        }

        alignPopup.addItems(withTitles: ["Gauche", "Centre", "Droite"])
        alignPopup.target = self
        alignPopup.action = #selector(optionChanged(_:))

        for w in [foreWell, backWell] {
            w.target = self
            w.action = #selector(optionChanged(_:))
            w.translatesAutoresizingMaskIntoConstraints = false
            w.widthAnchor.constraint(equalToConstant: 50).isActive = true
            w.heightAnchor.constraint(equalToConstant: 26).isActive = true
        }

        chkLive = check("Temps réel (apparaît en tapant)")
        btnSend = ColorButton("ENVOYER   (⌘ ↩)", color: NSColor(srgbRed: 0.24, green: 0.55, blue: 0.9, alpha: 1),
                              target: self, action: #selector(sendText(_:)))

        let btnFlash = ColorButton("⚡  FLASH   (⌘F / F5)", color: NSColor(srgbRed: 1, green: 0.67, blue: 0, alpha: 1),
                                   textColor: .black, fontSize: 20, height: 58, target: self, action: #selector(flash(_:)))
        flashCountCtl.onChange = { [weak self] v in self?.s.flashCount = Int(v) }
        flashSpeedCtl.onChange = { [weak self] v in self?.s.flashSpeed = Int(v) }
        chkBeep = check("Son avec le flash")

        chkHide = check("Masquer le texte (⌘B / F8)")
        let btnClear = ColorButton("EFFACER   (⌘K / F9)", color: NSColor(srgbRed: 0.86, green: 0.27, blue: 0.27, alpha: 1),
                                   target: self, action: #selector(clearAll(_:)))
        status.textColor = .secondaryLabelColor
        status.font = NSFont.systemFont(ofSize: 11)

        let hScreen = header("Écran participant"), hFont = header("Police"), hSend = header("Envoi")
        let hFlash = header("Flash"), hScr = header("Écran")
        let hBack = header("Couleur du fond"), hFore = header("Couleur du texte")
        let items: [NSView] = [
            hScreen, screenPopup, btnShow,
            hFont, fontPopup,
            row([label("Taille :"), sizeCtl, chkBold]),
            row([label("Alignement :"), alignPopup]),
            hBack, row(backChecks + [label(" Autre :"), backWell]),
            hFore, row(foreChecks + [label(" Autre :"), foreWell]),
            hSend, chkLive, btnSend,
            hFlash, btnFlash,
            row([label("Nombre :"), flashCountCtl, label("Vitesse (ms) :"), flashSpeedCtl]),
            chkBeep,
            hScr, chkHide, btnClear,
            status
        ]
        let right = NSStackView(views: items)
        right.orientation = .vertical
        right.alignment = .leading
        right.spacing = 6
        right.translatesAutoresizingMaskIntoConstraints = false
        let headers: [NSView] = [hFont, hBack, hFore, hSend, hFlash, hScr]
        for (i, v) in items.enumerated() where i > 0 && headers.contains(where: { $0 === v }) {
            right.setCustomSpacing(16, after: items[i - 1])
        }
        content.addSubview(right)
        for v in [screenPopup, btnShow!, fontPopup, btnSend!, btnFlash, btnClear, status] as [NSView] {
            v.widthAnchor.constraint(equalTo: right.widthAnchor).isActive = true
        }

        // Logo en bas à droite (sous « Effacer »)
        logoView.translatesAutoresizingMaskIntoConstraints = false
        logoView.imageScaling = .scaleProportionallyUpOrDown
        logoView.imageAlignment = .alignCenter
        logoView.toolTip = "Cliquer sur « Changer le logo… » pour le remplacer"
        loadLogo()
        let btnLogo = NSButton(title: "Changer le logo…", target: self, action: #selector(chooseLogo(_:)))
        let btnLogoDefault = NSButton(title: "Logo par défaut", target: self, action: #selector(defaultLogo(_:)))
        for b in [btnLogo, btnLogoDefault] { b.bezelStyle = .inline; b.controlSize = .small }
        let logoRow = row([btnLogo, btnLogoDefault])
        logoRow.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(logoRow)
        for o in [NSLayoutConstraint.Orientation.horizontal, .vertical] {
            logoView.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: o)
            logoView.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: o)
        }
        content.addSubview(logoView)
        let logoPreferred = logoView.heightAnchor.constraint(equalToConstant: 174)
        logoPreferred.priority = NSLayoutConstraint.Priority(250)

        NSLayoutConstraint.activate([
            left.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            left.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            left.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            left.trailingAnchor.constraint(equalTo: right.leadingAnchor, constant: -20),
            right.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            right.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            right.widthAnchor.constraint(equalToConstant: 310),
            right.bottomAnchor.constraint(lessThanOrEqualTo: logoView.topAnchor, constant: -12),
            logoView.leadingAnchor.constraint(equalTo: right.leadingAnchor),
            logoView.trailingAnchor.constraint(equalTo: right.trailingAnchor),
            logoView.bottomAnchor.constraint(equalTo: logoRow.topAnchor, constant: -6),
            logoRow.leadingAnchor.constraint(equalTo: right.leadingAnchor),
            logoRow.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            logoView.heightAnchor.constraint(lessThanOrEqualToConstant: 174),
            logoView.heightAnchor.constraint(greaterThanOrEqualToConstant: 60),
            logoPreferred,
        ])
    }

    func applySettings() {
        loading = true
        if fontPopup.item(withTitle: s.fontName) != nil { fontPopup.selectItem(withTitle: s.fontName) }
        else if fontPopup.item(withTitle: "Helvetica") != nil { fontPopup.selectItem(withTitle: "Helvetica") }
        sizeCtl.value = Double(min(1500, max(8, s.size)))
        chkBold.state = s.bold ? .on : .off
        alignPopup.selectItem(at: min(2, max(0, s.align)))
        foreWell.color = s.fore
        backWell.color = s.back
        syncColorChecks()
        chkLive.state = s.live ? .on : .off
        btnSend.isEnabled = !s.live
        flashCountCtl.value = Double(min(30, max(1, s.flashCount)))
        flashSpeedCtl.value = Double(min(1000, max(40, s.flashSpeed)))
        chkBeep.state = s.beep ? .on : .off
        loading = false
    }

    // MARK: Écrans
    static func screenID(_ sc: NSScreen) -> String {
        return (sc.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? ""
    }

    func refreshScreens() {
        let wasLoading = loading
        loading = true
        screens = NSScreen.screens
        screenPopup.removeAllItems()
        var sel = -1, firstSecondary = -1
        for (i, sc) in screens.enumerated() {
            var name = ""
            if #available(macOS 10.15, *) { name = sc.localizedName }
            let title = "Écran \(i + 1)\(i == 0 ? " (principal)" : "") – \(name) \(Int(sc.frame.width))x\(Int(sc.frame.height))"
            screenPopup.addItem(withTitle: title)
            if Controller.screenID(sc) == s.screenID { sel = i }
            if i > 0 && firstSecondary < 0 { firstSecondary = i }
        }
        // Par défaut : le 2e écran. Si l'écran mémorisé est le principal mais qu'un 2e existe, on prend le 2e.
        if sel < 0 || (sel == 0 && firstSecondary >= 0) { sel = firstSecondary >= 0 ? firstSecondary : 0 }
        if sel >= 0 && sel < screens.count { screenPopup.selectItem(at: sel) }
        status.stringValue = screens.count < 2
            ? "Un seul moniteur détecté : l'écran participant s'ouvre en fenêtre de test. Branchez le 2e moniteur (en mode étendu, pas en recopie) et il sera utilisé automatiquement."
            : "\(screens.count) moniteurs détectés."
        loading = wasLoading
    }

    func targetScreen() -> NSScreen {
        let i = screenPopup.indexOfSelectedItem
        if i >= 0 && i < screens.count { return screens[i] }
        return NSScreen.screens.first ?? NSScreen.main!
    }

    func showDisplay() {
        if display == nil {
            let w = DisplayWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 540),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.contentView = displayView
            w.backgroundColor = .black
            w.hidesOnDeactivate = false
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            w.delegate = self
            display = w
        }
        placeDisplay()
        display?.orderFront(nil)
        updateShowButton()
        refresh()
    }

    func placeDisplay() {
        guard let w = display else { return }
        let scr = targetScreen()
        let windowed = (scr == NSScreen.screens.first)   // jamais en plein écran sur l'écran de contrôle
        if windowed {
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.level = .normal
            w.title = "Écran participant (mode fenêtre – un seul moniteur)"
            let vf = scr.visibleFrame
            w.setFrame(NSRect(x: vf.minX + 60, y: vf.maxY - 60 - 540, width: 960, height: 540), display: true)
        } else {
            w.styleMask = [.borderless]
            w.level = .screenSaver
            w.setFrame(scr.frame, display: true)
        }
        w.contentView = displayView
        refresh()
    }

    func updateShowButton() {
        let vis = display?.isVisible ?? false
        btnShow.title = vis ? "Masquer l'écran participant" : "Afficher l'écran participant"
    }

    // MARK: Actions
    @objc func screenChanged(_ sender: Any?) {
        if loading { return }
        s.screenID = Controller.screenID(targetScreen())
        if let d = display, d.isVisible { placeDisplay() }
        refresh()
    }

    @objc func toggleDisplay(_ sender: Any?) {
        if let d = display, d.isVisible { d.orderOut(nil); updateShowButton(); refresh() }
        else { showDisplay() }
    }

    @objc func optionChanged(_ sender: Any?) {
        if loading { return }
        if let f = fontPopup.titleOfSelectedItem { s.fontName = f }
        s.bold = chkBold.state == .on
        s.align = max(0, alignPopup.indexOfSelectedItem)
        s.fore = foreWell.color
        s.back = backWell.color
        s.beep = chkBeep.state == .on
        hiddenText = chkHide.state == .on
        let live = chkLive.state == .on
        if live != s.live {
            s.live = live
            btnSend.isEnabled = !live
            if live { sendText(nil) }
        }
        syncColorChecks()
        refresh()
    }

    // MARK: Logo (modifiable)
    static var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        return base.appendingPathComponent("Messag8", isDirectory: true)
    }

    func loadLogo() {
        var img: NSImage? = nil
        if let p = UserDefaults.standard.string(forKey: "logoPath"), !p.isEmpty {
            img = NSImage(contentsOfFile: p)
        }
        if img == nil, let url = Bundle.main.url(forResource: "logo", withExtension: "png") {
            img = NSImage(contentsOf: url)
        }
        logoView.image = img
    }

    @objc func chooseLogo(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = "Choisir un logo"
        panel.allowedFileTypes = ["png", "jpg", "jpeg", "gif", "bmp", "tif", "tiff", "heic"]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let src = panel.url else { return }
        guard NSImage(contentsOf: src) != nil else {
            let a = NSAlert()
            a.messageText = "Impossible d'utiliser cette image."
            a.runModal()
            return
        }
        do {
            // Copie dans le dossier de Messag8 pour que le logo reste même si l'original est déplacé
            let fm = FileManager.default
            let dir = Controller.supportDir
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            if let old = try? fm.contentsOfDirectory(atPath: dir.path) {
                for f in old where f.hasPrefix("logo_perso.") { try? fm.removeItem(at: dir.appendingPathComponent(f)) }
            }
            let dest = dir.appendingPathComponent("logo_perso." + src.pathExtension.lowercased())
            try fm.copyItem(at: src, to: dest)
            UserDefaults.standard.set(dest.path, forKey: "logoPath")
            loadLogo()
        } catch {
            let a = NSAlert()
            a.messageText = "Impossible de copier l'image : \(error.localizedDescription)"
            a.runModal()
        }
    }

    @objc func defaultLogo(_ sender: Any?) {
        UserDefaults.standard.set("", forKey: "logoPath")
        loadLogo()
    }

    // Cases de couleur : une seule cochée à la fois (comme des boutons radio)
    @objc func colorCheck(_ sender: NSButton) {
        if let i = backChecks.firstIndex(of: sender) {
            s.back = backColors[i]
            backWell.color = s.back
        } else if let i = foreChecks.firstIndex(of: sender) {
            s.fore = foreColors[i]
            foreWell.color = s.fore
        }
        syncColorChecks()
        refresh()
    }

    static func sameColor(_ a: NSColor, _ b: NSColor) -> Bool {
        let x = Settings.comps(a), y = Settings.comps(b)
        for i in 0..<3 where abs(x[i] - y[i]) > 0.01 { return false }
        return true
    }

    func syncColorChecks() {
        for (i, b) in backChecks.enumerated() { b.state = Controller.sameColor(backColors[i], s.back) ? .on : .off }
        for (i, b) in foreChecks.enumerated() { b.state = Controller.sameColor(foreColors[i], s.fore) ? .on : .off }
    }

    func textDidChange(_ notification: Notification) {
        if s.live { sendText(nil) }
    }

    @objc func sendText(_ sender: Any?) {
        shown = textView.string
        refresh()
    }

    @objc func clearAll(_ sender: Any?) {
        textView.string = ""
        shown = ""
        refresh()
        window.makeFirstResponder(textView)
    }

    @objc func toggleHide(_ sender: Any?) {
        chkHide.state = chkHide.state == .on ? .off : .on
        hiddenText = chkHide.state == .on
        refresh()
    }

    @objc func flash(_ sender: Any?) {
        if !(display?.isVisible ?? false) { showDisplay() }
        if !s.live { sendText(nil) }
        if s.beep { (NSSound(named: "Glass") ?? NSSound(named: "Ping"))?.play() }
        flashTimer?.invalidate()
        flashTicks = s.flashCount * 2 - 1
        inverted = true
        refresh()
        let t = Timer(timeInterval: Double(s.flashSpeed) / 1000.0, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            if self.flashTicks <= 0 {
                timer.invalidate()
                self.inverted = false
            } else {
                self.inverted.toggle()
                self.flashTicks -= 1
            }
            self.refresh()
        }
        RunLoop.main.add(t, forMode: .common)
        flashTimer = t
    }

    func refresh() {
        preview.needsDisplay = true
        displayView.needsDisplay = true
    }

    // MARK: Aperçu
    func paintPreview(_ b: NSRect) {
        NSColor(white: 0.18, alpha: 1).setFill()
        b.fill()
        var target = targetScreen().frame.size
        if let d = display, d.isVisible { target = displayView.bounds.size }
        guard target.width > 0, target.height > 0 else { return }
        let pane = b.insetBy(dx: 8, dy: 8)
        guard pane.width > 0, pane.height > 0 else { return }
        let scale = min(pane.width / target.width, pane.height / target.height)
        let w = target.width * scale, h = target.height * scale
        let r = NSRect(x: pane.midX - w / 2, y: pane.midY - h / 2, width: w, height: h)
        Renderer.draw(in: r, text: shown, s: s, scale: scale, inverted: inverted, hidden: hiddenText)
        NSColor.gray.setStroke()
        NSBezierPath(rect: r).stroke()
    }

    // MARK: Fenêtres
    func windowWillClose(_ notification: Notification) {
        guard let w = notification.object as? NSWindow else { return }
        if w === window {
            s.save()
            NSApp.terminate(nil)
        } else {
            DispatchQueue.main.async { self.updateShowButton(); self.refresh() }
        }
    }

    func windowDidResize(_ notification: Notification) {
        refresh()
    }
}

// MARK: - Application
final class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: Controller?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let c = Controller()
        controller = c
        c.start()
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationWillTerminate(_ notification: Notification) {
        controller?.s.save()
    }
}

let app = NSApplication.shared
let appDelegate = AppDelegate()
app.delegate = appDelegate
app.setActivationPolicy(.regular)
app.run()
