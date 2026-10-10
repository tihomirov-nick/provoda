import AppKit
import SwiftUI
import ProvodaCore

// The places where an app made from the template becomes itself. The rest of Sources/Provoda is the family's
// plumbing: the icon with its menu and panel, Settings, updates, the interface language and the sounds.

// MARK: - 1. The glyph

extension MenuBarIcon {
    /// The USB trident (`ProvodaMark`) in the menu bar canvas of the new utilities (Glyph.swift): 16 pt tall on a 22 pt
    /// canvas, its left edge on a whole pixel, lines of `Glyph.menuLine` in box units, grown with the mark.
    /// scripts/make_icon.swift draws the same mark on the app icon (`drawMark`).
    static func drawGlyph(in ctx: CGContext, box: CGRect) {
        ctx.saveGState()
        Glyph.enterMenuBox(ctx, bounds: ProvodaMark.bounds, scale: max(1, abs(ctx.userSpaceToDeviceSpaceTransform.a)))
        ProvodaMark.draw(ctx, line: Glyph.menuLine)
        ctx.restoreGState()
    }
}

/// The USB trident in our own geometry: an arrow up on a stem that ends in a solid circle below, a branch to the left
/// ending in a circle and a branch to the right ending in a square. The 100 × 100 box of Glyph.swift, y down.
enum ProvodaMark {
    /// The ink of the trident in the box: the menu bar and the app icon fit it to their room (Glyph.swift).
    /// scripts/make_icon.swift carries the same numbers, ProvodaTests compares them.
    static let bounds = CGRect(x: 20, y: 4.3, width: 59.5, height: 89.2)

    static func draw(_ ctx: CGContext, line w: CGFloat) {
        let p = Glyph.p
        let arrow = Glyph.line([p(50, 6), p(61, 23), p(39, 23)]).mutableCopy()!
        arrow.closeSubpath()
        Glyph.fill(ctx, arrow)
        Glyph.stroke(ctx, arrow, w * 0.4)   // rounds the arrowhead's corners
        Glyph.stroke(ctx, Glyph.line([p(50, 22), p(50, 80)]), w)
        Glyph.fill(ctx, Glyph.disc(p(50, 83), 10.5))
        Glyph.stroke(ctx, Glyph.line([p(50, 70), p(27, 55), p(27, 40)]), w)
        Glyph.fill(ctx, Glyph.disc(p(27, 37), 7))
        Glyph.stroke(ctx, Glyph.line([p(50, 59), p(73, 44), p(73, 34)]), w)
        Glyph.fill(ctx, Glyph.roundedRect(CGRect(x: 66.5, y: 23.5, width: 13, height: 13), 1.5))
    }
}

// MARK: - 2. The main view

/// The attached USB and Thunderbolt devices, a search field, «Настройки» and «Закрыть». The list follows the ports.
struct MainView: View {
    @ObservedObject private var store = DeviceStore.shared
    @AppStorage(DeviceSettings.showSerialsKey) private var showSerials = false
    @AppStorage(DeviceSettings.hideBuiltInKey) private var hideBuiltIn = true
    @State private var query = ""

    var body: some View {
        let attached = DeviceList.visible(store.devices, hideBuiltIn: hideBuiltIn)
        let found = DeviceList.search(attached, query: query, showSerials: showSerials)
        VStack(alignment: .leading, spacing: Metrics.gap) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("Подключено"))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if !attached.isEmpty {
                    Text(verbatim: "\(attached.count)")
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(Palette.secondary)
                }
            }
            .padding(.horizontal, 2)
            if attached.isEmpty {
                EmptyNote(symbol: "cable.connector", text: L("Ничего не подключено"),
                          hint: L("Устройства USB и Thunderbolt появятся здесь сразу после подключения"))
            } else if found.isEmpty {
                EmptyNote(symbol: "magnifyingglass", text: L("Ничего не нашлось"), hint: nil)
            } else {
                DeviceRows(devices: found, showSerials: showSerials)
            }
            PanelFooter(query: $query)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DeviceRows: View {
    let devices: [ConnectedDevice]
    let showSerials: Bool

    var body: some View {
        let rows = VStack(spacing: 0) {
            ForEach(Array(devices.enumerated()), id: \.element.id) { index, device in
                if index > 0 { Separator(leading: 52) }
                DeviceRow(device: device, showSerials: showSerials)
            }
        }
        // Up to five devices the panel grows with the list, after that the list scrolls. A scroller would take its
        // width from the rows (with a mouse attached macOS shows scrollers all the time), so the bottom edge fades
        // instead, and the last row scrolls clear of the fade.
        if devices.count > 5 {
            ScrollView { rows.padding(.bottom, 20) }
                .scrollIndicators(.never)
                .frame(height: 360)
                .mask(LinearGradient(stops: [.init(color: .black, location: 0.86), .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
                .card()
        } else {
            rows.card()
        }
    }
}

private struct DeviceRow: View {
    let device: ConnectedDevice
    let showSerials: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: device.kind.symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 30, height: 30)
                .background(Palette.control, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityLabel(device.kind.title)
            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if device.link != nil || device.power?.label != nil {
                    // Side by side, or one under the other when a long link («USB 3.2 Gen 2×2 · 20 Гбит/с») leaves
                    // no room: the badges never squeeze the panel wider.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 4) { badges }
                        VStack(alignment: .leading, spacing: 4) { badges }
                    }
                }
                Text(device.details)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
                if let shortage = device.power?.shortage {
                    Text(shortage)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.orange)
                }
                if showSerials, let serial = device.serial {
                    Text(L("Серийный номер %@", serial))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var badges: some View {
        if let link = device.link { Badge(text: link.label) }
        if let power = device.power?.label { Badge(text: power, symbol: "bolt.fill") }
    }
}

/// A small capsule: the link or the power.
private struct Badge: View {
    let text: String
    var symbol: String?

    var body: some View {
        HStack(spacing: 3) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 8, weight: .bold))
            }
            Text(text).font(.system(size: 10.5, weight: .medium))
        }
        .lineLimit(1)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.white.opacity(0.1), in: Capsule())
        .fixedSize()
    }
}

private struct EmptyNote: View {
    let symbol: String
    let text: String
    let hint: String?

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(Palette.secondary)
            Text(text)
                .font(.system(size: 12, weight: .medium))
            if let hint {
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 16)
        .card()
    }
}

/// The search field, «Настройки» and «Закрыть».
private struct PanelFooter: View {
    @Binding var query: String

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.secondary)
                TextField(L("Поиск"), text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(L("Очистить"))
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Palette.control, in: Capsule())
            RoundButton(symbol: "gearshape", help: L("Настройки")) {
                PanelActions.close()
                SettingsWindow.show()
            }
            RoundButton(symbol: "xmark", help: L("Закрыть")) {
                PanelActions.close()
            }
        }
    }
}

private struct RoundButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(Palette.control, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .help(help)
        .accessibilityLabel(help)
    }
}

@MainActor
enum PanelActions {
    static func close() {
        NSApp.windows.compactMap { $0 as? StatusPanel }.forEach { $0.dismiss() }
    }
}

// MARK: - 3. The app's section in Settings

struct AppSettingsSection: View {
    @AppStorage(DeviceSettings.showSerialsKey) private var showSerials = false
    @AppStorage(DeviceSettings.hideBuiltInKey) private var hideBuiltIn = true
    @AppStorage(DeviceSettings.notifyKey) private var notify = false

    var body: some View {
        SectionTitle(L("Устройства"))
        VStack(spacing: 0) {
            SwitchRow(title: L("Показывать серийные номера"),
                      help: L("Серийный номер появится под именем устройства, его можно выделить и скопировать"),
                      isOn: $showSerials)
            Separator()
            SwitchRow(title: L("Скрывать встроенные хабы"),
                      help: L("Хабы внутри переходников и мониторов и собственные устройства Mac. То, что подключено через такой хаб, остаётся в списке"),
                      isOn: $hideBuiltIn)
            Separator()
            SwitchRow(title: L("Уведомлять о подключении"),
                      help: L("Когда появляется новое устройство, macOS показывает уведомление с его именем и скоростью"),
                      isOn: $notify)
        }
        .card()
        .onChange(of: notify) { _, on in
            if on { ConnectNotice.requestPermission() }
        }
    }
}

// MARK: - 4. The actions of the menu and 5. being busy

@MainActor
enum AppActions {
    /// The list is the panel itself: no actions of its own in the menu.
    static func menuItems() -> [NSMenuItem] {
        []
    }

    /// Nothing to interrupt: after a restart the list is read again.
    static var isBusy: Bool {
        false
    }
}
