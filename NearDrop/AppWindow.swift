// SPDX-License-Identifier: Apache-2.0
//
//  AppWindow.swift
//  NearDrop
//
//  The app's window: a sidebar with Send and Received (working) plus placeholder pages
//  for what's coming (cable transfer, history, devices, settings).
//

import SwiftUI
import AppKit
import ServiceManagement

// MARK: - Received store

final class ReceivedStore: ObservableObject {
	static let shared = ReceivedStore()

	struct Item: Identifiable {
		enum State: Equatable { case waiting, receiving, done, declined, failed }
		let id: String
		let device: String
		let title: String
		let date: Date
		var state: State
		var progress = 0.0
		var urls: [URL] = []
		var activity = Date()
	}

	@Published private(set) var items: [Item] = []
	/// Set by the app delegate: accept or decline an incoming transfer.
	var respond: (String, Bool) -> Void = { _, _ in }

	var waiting: Int { items.filter { $0.state == .waiting }.count }

	/// All methods run on the main thread.
	private init() {
		// A transfer that was accepted but has gone silent for 90 s is stuck: say so instead of spinning forever.
		Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
			guard let self else { return }
			for i in self.items.indices where self.items[i].state == .receiving && Date().timeIntervalSince(self.items[i].activity) > 90 {
				self.items[i].state = .failed
			}
		}
	}

	func add(_ item: Item) { items.insert(item, at: 0) }

	func set(_ id: String, _ state: Item.State) {
		guard let i = items.firstIndex(where: { $0.id == id }) else { return }
		items[i].state = state
		items[i].activity = Date()
	}

	func setProgress(_ id: String, _ progress: Double) {
		guard let i = items.firstIndex(where: { $0.id == id }), items[i].state == .receiving else { return }
		items[i].progress = progress
		items[i].activity = Date()
	}

	/// Returns the item when this call moved it to done/failed (so the caller can play a sound), nil if nothing changed.
	@discardableResult
	func finish(_ id: String, error: Error?, files: [URL]) -> Item? {
		guard let i = items.firstIndex(where: { $0.id == id }) else { return nil }
		switch items[i].state {
		case .done, .declined, .failed: return nil
		case .waiting where error == nil && files.isEmpty: items[i].state = .failed  // the phone canceled before we answered
		default:
			items[i].urls = files
			items[i].state = error == nil ? .done : .failed
			if error == nil { items[i].progress = 1 }
		}
		return items[i]
	}
}

// MARK: - Navigation

enum Page: String, CaseIterable, Identifiable {
	case send, received, cable, history, devices, settings

	var id: String { rawValue }

	var title: String {
		switch self {
		case .send: return NSLocalizedString("PageSend", value: "Send", comment: "")
		case .received: return NSLocalizedString("PageReceive", value: "Receive", comment: "")
		case .cable: return NSLocalizedString("PageCable", value: "Cable", comment: "")
		case .history: return NSLocalizedString("PageHistory", value: "History", comment: "")
		case .devices: return NSLocalizedString("PageDevices", value: "Devices", comment: "")
		case .settings: return NSLocalizedString("PageSettings", value: "Settings", comment: "")
		}
	}

	var symbol: String {
		switch self {
		case .send: return "paperplane"
		case .received: return "tray.and.arrow.down"
		case .cable: return "cable.connector"
		case .history: return "clock"
		case .devices: return "laptopcomputer.and.iphone"
		case .settings: return "gearshape"
		}
	}

}

final class AppNav: ObservableObject {
	@Published var page: Page = .send
}

// MARK: - Root

struct AppRoot: View {
	@ObservedObject var model: ShareModel
	@ObservedObject var nav: AppNav
	@ObservedObject var store = ReceivedStore.shared

	var body: some View {
		NavigationSplitView {
			VStack(spacing: 0) {
				VStack(spacing: 6) {
					item(.send)
					item(.received)
					item(.cable)
				}
				VStack(spacing: 6) {
					item(.history)
					item(.devices)
				}
				.padding(.top, 22)
				Spacer(minLength: 0)
				item(.settings)
			}
			.padding(.horizontal, 12)
			.padding(.vertical, 12)
			.navigationSplitViewColumnWidth(210)
		} detail: {
			ZStack {
				switch nav.page {
				case .send: ShareRootView(model: model)
				case .received: ReceivePage(store: store)
				case .cable: CablePage()
				case .settings: SettingsPage()
				case .history: HistoryPage(store: .shared)
				case .devices: DevicesPage(history: .shared, openSend: { nav.page = .send }, openCable: { nav.page = .cable })
				}
			}
			.id(nav.page)
			.transition(.opacity)
			.animation(.easeInOut(duration: 0.18), value: nav.page)
			.frame(maxWidth: .infinity, maxHeight: .infinity)
			.clipped() // a page can never spill over the sidebar or title bar
			.navigationTitle(nav.page.title)
		}
		.toolbar(removing: .sidebarToggle)
	}

	private func item(_ page: Page) -> some View {
		SidebarItem(page: page, selected: nav.page == page, badge: page == .received ? store.waiting : 0) { nav.page = page }
	}
}

/// Sidebar row: icon in a fixed-width column so every label lines up, accent tint when selected.
private struct SidebarItem: View {
	let page: Page
	let selected: Bool
	let badge: Int
	let action: () -> Void
	@State private var hovered = false

	var body: some View {
		Button(action: action) {
			HStack(spacing: 10) {
				Image(systemName: page.symbol).symbolVariant(selected ? .fill : .none).font(.system(size: 15)).frame(width: 22)
				Text(page.title)
				Spacer(minLength: 0)
				if badge > 0 {
					Text("\(badge)").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
						.padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(Palette.accent))
				}
			}
			.font(.system(size: 14, weight: .medium))
			.foregroundStyle(selected ? Palette.accent : Color.primary)
			.padding(.horizontal, 10)
			.padding(.vertical, 9)
			.background(RoundedRectangle(cornerRadius: 10, style: .continuous)
				.fill(selected ? Palette.accent.opacity(0.14) : hovered ? Color.primary.opacity(0.06) : .clear))
			.animation(.easeOut(duration: 0.15), value: selected)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.onHover { hovered = $0 }
		.accessibilityAddTraits(selected ? .isSelected : [])
	}
}

/// Centers its content when it fits and scrolls when it doesn't, so a page can't overflow into the sidebar.
struct PageScroll<Content: View>: View {
	@ViewBuilder var content: Content

	var body: some View {
		GeometryReader { proxy in
			ScrollView {
				content.frame(maxWidth: .infinity, minHeight: proxy.size.height)
			}
			.scrollBounceBehavior(.basedOnSize)
		}
		.clipped()
		.background(Color(nsColor: .windowBackgroundColor))
	}
}

// MARK: - Settings page

private struct SettingsPage: View {
	@AppStorage(Chime.enabledKey) private var sounds = true
	@AppStorage(AppearanceMode.key) private var appearance = AppearanceMode.system.rawValue
	@State private var launchAtLogin = SMAppService.mainApp.status == .enabled
	@State private var loginError: String?

	private var content: some View {
		VStack(spacing: 12) {
			row(NSLocalizedString("SettingAppearance", value: "Appearance", comment: ""),
				NSLocalizedString("SettingAppearanceHint", value: "Match your Mac, or always Light or Dark.", comment: "")) {
				Picker("", selection: $appearance) {
					ForEach(AppearanceMode.allCases) { Text($0.title).tag($0.rawValue) }
				}
				.pickerStyle(.segmented).labelsHidden().frame(width: 210)
			}
			row(NSLocalizedString("SettingSounds", value: "Play sounds", comment: ""),
				NSLocalizedString("SettingSoundsHint", value: "A chime when a transfer finishes or fails.", comment: "")) {
				Toggle("", isOn: $sounds).labelsHidden().toggleStyle(.switch)
			}
			row(NSLocalizedString("SettingLogin", value: "Open at login", comment: ""),
				loginError ?? NSLocalizedString("SettingLoginHint", value: "Keeps Blippy ready to receive after a restart.", comment: "")) {
				Toggle("", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin)).labelsHidden().toggleStyle(.switch)
			}
			row(NSLocalizedString("SettingShortcut", value: "Shortcut", comment: ""),
				NSLocalizedString("SettingShortcutHint", value: "Open Blippy from anywhere.", comment: "")) {
				Text("⌃⌥N").font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
			}
			row(NSLocalizedString("SettingSaveTo", value: "Received files", comment: ""),
				NSLocalizedString("SettingSaveToHint", value: "Saved to your Downloads folder.", comment: "")) {
				Button(NSLocalizedString("OpenDownloads", value: "Open Downloads", comment: "")) { SendSession.openDownloads() }
					.buttonStyle(GlassButtonStyle())
			}
			row(NSLocalizedString("SettingPrivacy", value: "Privacy", comment: ""),
				NSLocalizedString("SettingPrivacyHint", value: "No data collected. No analytics, accounts or servers.", comment: "")) {
				Image(systemName: "lock.shield").font(.system(size: 18)).foregroundStyle(.secondary)
			}
			if let coffee = AppInfo.coffeeURL { supportCard(coffee) }
			footer
			Spacer(minLength: 0)
		}
		.padding(24)
		.frame(maxWidth: 560)
	}

	/// Optional support section: a QR code and a button for the Buy Me a Coffee page (hidden until a link is set in AppInfo).
	private func supportCard(_ url: URL) -> some View {
		HStack(spacing: 16) {
			if let qr = SendSession.plainQRImage(url.absoluteString) {
				Image(nsImage: qr).resizable().interpolation(.none).frame(width: 84, height: 84)
					.padding(8).background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white))
					.accessibilityLabel(NSLocalizedString("CoffeeQR", value: "QR code for the Buy Me a Coffee page", comment: ""))
			}
			VStack(alignment: .leading, spacing: 8) {
				Text(NSLocalizedString("CoffeeTitle", value: "Enjoying Blippy?", comment: "")).font(.system(size: 14, weight: .semibold))
				Text(NSLocalizedString("CoffeeBody", value: "Blippy is free and open source. If it saves you time, you can buy me a coffee.", comment: ""))
					.font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
				Button(NSLocalizedString("CoffeeButton", value: "Buy Me a Coffee", comment: "")) { NSWorkspace.shared.open(url) }
					.buttonStyle(GlassButtonStyle(prominent: true))
			}
			Spacer(minLength: 0)
		}
		.padding(16)
		.card()
	}

	private var footer: some View {
		HStack(spacing: 6) {
			Text("Blippy \(AppInfo.version) · Apache 2.0").foregroundStyle(.tertiary)
			if let repo = AppInfo.repoURL { Link("GitHub", destination: repo) }
		}
		.font(.system(size: 11))
		.frame(maxWidth: .infinity)
		.padding(.top, 4)
	}

	var body: some View {
		PageScroll { content }
			.onChange(of: appearance) { _, value in AppearanceMode(rawValue: value)?.apply() }
	}

	private func row<Trailing: View>(_ title: String, _ detail: String, @ViewBuilder trailing: () -> Trailing) -> some View {
		HStack(spacing: 12) {
			VStack(alignment: .leading, spacing: 3) {
				Text(title).font(.system(size: 14, weight: .semibold))
				Text(detail).font(.system(size: 12)).foregroundStyle(loginError != nil && detail == loginError ? Palette.warning : .secondary)
			}
			Spacer(minLength: 8)
			trailing()
		}
		.padding(16)
		.card()
	}

	private func setLaunchAtLogin(_ on: Bool) {
		do {
			if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
			loginError = nil
		} catch {
			loginError = error.localizedDescription
		}
		launchAtLogin = SMAppService.mainApp.status == .enabled
	}
}

// MARK: - Receive page

private struct ReceivePage: View {
	@ObservedObject var store: ReceivedStore

	var body: some View {
		VStack(spacing: 0) {
			HStack(spacing: 14) {
				ZStack {
					PulseRing(size: 56)
					Image(systemName: "dot.radiowaves.left.and.right")
						.font(.system(size: 20, weight: .medium)).foregroundStyle(Palette.accent)
						.frame(width: 56, height: 56).glass(Circle(), tint: Palette.accent.opacity(0.12))
				}
				.frame(width: 84, height: 84)
				VStack(alignment: .leading, spacing: 4) {
					HStack(spacing: 6) {
						Circle().fill(Palette.success).frame(width: 8, height: 8)
						Text(NSLocalizedString("ReadyToReceive", value: "Ready to receive", comment: "")).font(.system(size: 16, weight: .semibold))
					}
					Text(String(format: NSLocalizedString("VisibleAs", value: "Visible as %@ on this Wi-Fi", comment: ""), Host.current().localizedName ?? "this Mac"))
						.font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
				}
				Spacer()
				Button(NSLocalizedString("OpenDownloads", value: "Open Downloads", comment: "")) { SendSession.openDownloads() }
					.buttonStyle(GlassButtonStyle())
			}
			.padding(.horizontal, 20).padding(.vertical, 14)

			if store.items.isEmpty {
				VStack(spacing: 6) {
					Image(systemName: "tray").font(.system(size: 34, weight: .light)).foregroundStyle(.secondary).padding(.bottom, 10)
					Text(NSLocalizedString("NothingReceived", value: "Nothing received yet", comment: "")).font(.system(size: 15, weight: .semibold))
					Text(NSLocalizedString("NothingReceivedHint", value: "Share from your phone with Quick Share and pick this Mac.", comment: ""))
						.font(.system(size: 12)).foregroundStyle(.secondary)
				}
				.frame(maxWidth: .infinity, maxHeight: .infinity)
			} else {
				ScrollView {
					LazyVStack(spacing: 10) {
						ForEach(store.items) { ReceivedRow(item: $0, store: store) }
					}
					.padding(.horizontal, 20).padding(.bottom, 20)
				}
			}
		}
		.background {
			ZStack(alignment: .top) {
				Color(nsColor: .windowBackgroundColor)
				RadialGradient(colors: [Palette.accent.opacity(0.14), .clear], center: .top, startRadius: 0, endRadius: 320)
			}
		}
	}
}

// MARK: - Cable page

private struct CablePage: View {
	@ObservedObject private var cable = CableModel.shared
	@State private var dropTargeted = false

	private var heroStatus: PhoneIcon.Status {
		switch cable.phase {
		case .sending: return .sending(cable.progress)
		case .finished: return hasFailures ? .failed : .success
		case .idle: return .idle
		}
	}

	private var hasFailures: Bool {
		cable.items.contains { if case .failed = $0.state { return true } else { return false } }
	}

	private var waitingForPhone: Bool {
		guard cable.phase == .idle else { return false }
		if case .ready = cable.link { return false }
		return true
	}

	private var pageBody: some View {
		VStack(spacing: 22) {
			Spacer(minLength: 0)
			ZStack {
				if waitingForPhone || cable.phase == .sending { PulseRing(size: 150) }
				PhoneIcon(height: 104, status: heroStatus)
			}
			.frame(width: 200, height: 170)

			VStack(spacing: 6) {
				Text(title).font(.system(size: 20, weight: .semibold))
				Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
					.multilineTextAlignment(.center).frame(maxWidth: 340).fixedSize(horizontal: false, vertical: true)
			}

			content
			Spacer(minLength: 0)
		}
		.padding(24)
	}

	var body: some View {
		PageScroll { pageBody }
		.overlay {
			if dropTargeted {
				RoundedRectangle(cornerRadius: 18, style: .continuous)
					.strokeBorder(Palette.accent, style: StrokeStyle(lineWidth: 2, dash: [7, 5])).padding(8).allowsHitTesting(false)
			}
		}
		.dropDestination(for: URL.self) { urls, _ in
			guard case .ready = cable.link, cable.phase != .sending else { return false }
			cable.send(urls)
			return true
		} isTargeted: { dropTargeted = $0 }
		.onAppear { cable.start() }
		.onDisappear { cable.stop() }
	}

	private var title: String {
		switch cable.phase {
		case .sending: return String(format: NSLocalizedString("SendingTo", value: "Sending to %@", comment: ""), cable.targetName)
		case .finished: return hasFailures ? NSLocalizedString("CableSomeFailed", value: "Some files didn’t send", comment: "")
			: String(format: NSLocalizedString("SentTo", value: "Sent to %@", comment: ""), cable.targetName)
		case .idle:
			switch cable.link {
			case .none: return NSLocalizedString("CableConnect", value: "Connect your phone", comment: "")
			case .noAdb: return NSLocalizedString("CableNoAdb", value: "adb not found", comment: "")
			case .noDebugging: return NSLocalizedString("CableDebugging", value: "Turn on USB debugging", comment: "")
			case .unauthorized: return NSLocalizedString("CableAllow", value: "Allow on your phone", comment: "")
			case .offline: return NSLocalizedString("CableReconnect", value: "Reconnect the cable", comment: "")
			case .ready(_, let name): return String(format: NSLocalizedString("CableReady", value: "%@ is ready", comment: ""), name)
			}
		}
	}

	private var subtitle: String {
		switch cable.phase {
		case .sending: return cable.speedText ?? NSLocalizedString("CableSavingTo", value: "Saving to Downloads on your phone", comment: "")
		case .finished: return NSLocalizedString("CableSavedTo", value: "In Downloads on your phone", comment: "")
		case .idle:
			switch cable.link {
			case .none: return NSLocalizedString("CableConnectHint", value: "Plug in a USB-C data cable and unlock the phone.", comment: "")
			case .noAdb: return NSLocalizedString("CableNoAdbHint", value: "The bundled adb tool is missing from this build.", comment: "")
			case .noDebugging(let name): return String(format: NSLocalizedString("CableDebuggingHint", value: "%@ is connected. Enable Developer options, then USB debugging.", comment: ""), name)
			case .unauthorized: return NSLocalizedString("CableAllowHint", value: "Tap Allow on the “Allow USB debugging?” prompt. Tick “Always allow” so it asks once.", comment: "")
			case .offline: return NSLocalizedString("CableOfflineHint", value: "The phone isn’t responding. Unplug it and plug it back in.", comment: "")
			case .ready: return NSLocalizedString("CableReadyHint", value: "Drop files here. They save to Downloads on your phone.", comment: "")
			}
		}
	}

	@ViewBuilder
	private var content: some View {
		switch cable.phase {
		case .sending, .finished:
			VStack(spacing: 14) {
				VStack(spacing: 8) {
					ForEach(cable.items) { CableRow(item: $0) }
				}
				.frame(maxWidth: 420)
				if cable.phase == .sending {
					Button(NSLocalizedString("Cancel", value: "Cancel", comment: ""), action: cable.cancel).buttonStyle(GlassButtonStyle())
				} else {
					Button(NSLocalizedString("Done", value: "Done", comment: ""), action: cable.reset).buttonStyle(GlassButtonStyle(prominent: true))
				}
			}
		case .idle:
			switch cable.link {
			case .noDebugging:
				VStack(alignment: .leading, spacing: 10) {
					step("1", NSLocalizedString("DebugStep1", value: "Settings → About phone → tap Build number 7 times", comment: ""))
					step("2", NSLocalizedString("DebugStep2", value: "Settings → System → Developer options", comment: ""))
					step("3", NSLocalizedString("DebugStep3", value: "Turn on USB debugging", comment: ""))
				}
			case .ready:
				VStack(spacing: 12) {
					Button(NSLocalizedString("ChooseFiles", value: "Choose Files…", comment: "")) { choose(photosOnly: false) }
						.buttonStyle(GlassButtonStyle(prominent: true))
				}
			default:
				EmptyView()
			}
			if photosFallback {
				VStack(spacing: 8) {
					Text(String(format: NSLocalizedString("PhotoMode", value: "%@ is in Photo transfer mode", comment: ""), cable.cameraName ?? ""))
						.font(.system(size: 12)).foregroundStyle(.secondary)
					Button(NSLocalizedString("SendPhotos", value: "Send photos & videos…", comment: "")) { choose(photosOnly: true) }
						.buttonStyle(GlassButtonStyle())
					Text(NSLocalizedString("PhotoNote", value: "Photos and videos only. They go to the camera folder, not Downloads.", comment: ""))
						.font(.system(size: 11)).foregroundStyle(.tertiary)
				}
			}
		}
	}

	private var photosFallback: Bool {
		guard cable.phase == .idle, cable.cameraName != nil else { return false }
		if case .ready = cable.link { return false }
		return true
	}

	private func step(_ number: String, _ text: String) -> some View {
		HStack(spacing: 12) {
			Text(number).font(.system(size: 12, weight: .semibold)).frame(width: 24, height: 24).glass(Circle())
			Text(text).font(.system(size: 13))
		}
	}

	private func choose(photosOnly: Bool) {
		let panel = NSOpenPanel()
		panel.canChooseFiles = true
		panel.canChooseDirectories = !photosOnly
		panel.allowsMultipleSelection = true
		if photosOnly { panel.allowedContentTypes = [.image, .movie] }
		panel.begin { response in
			guard response == .OK else { return }
			photosOnly ? cable.sendPhotos(panel.urls) : cable.send(panel.urls)
		}
	}
}

private struct CableRow: View {
	let item: CableModel.Item

	var body: some View {
		HStack(spacing: 12) {
			FileThumb(url: item.url, size: 30)
			VStack(alignment: .leading, spacing: 4) {
				Text(item.url.lastPathComponent).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
				switch item.state {
				case .sending(let fraction): if item.isFolder || item.size == 0 { ProgressView().controlSize(.small) } else { ProgressView(value: fraction).tint(Palette.accent) }
				case .failed(let message): Text(message).font(.system(size: 11)).foregroundStyle(Palette.warning).lineLimit(2)
				case .done: Text(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file)).font(.system(size: 11)).foregroundStyle(.secondary)
				case .waiting: Text(NSLocalizedString("Waiting", value: "Waiting", comment: "")).font(.system(size: 11)).foregroundStyle(.secondary)
				}
			}
			Spacer(minLength: 8)
			if case .done = item.state { Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.success) }
		}
		.padding(12)
		.card(cornerRadius: 14)
	}
}

private struct ReceivedRow: View {
	let item: ReceivedStore.Item
	let store: ReceivedStore

	var body: some View {
		HStack(spacing: 12) {
			FileThumb(url: item.urls.first, fallback: icon, size: 34)
			VStack(alignment: .leading, spacing: 2) {
				Text(item.title).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.middle)
				Text("\(item.device) · \(item.date.formatted(.relative(presentation: .named)))")
					.font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
			}
			Spacer(minLength: 8)
			trailing
		}
		.padding(14)
		.card()
	}

	private var icon: NSImage {
		if let url = item.urls.first { return NSWorkspace.shared.icon(forFile: url.path) }
		return NSWorkspace.shared.icon(for: .data)
	}

	@ViewBuilder
	private var trailing: some View {
		switch item.state {
		case .waiting:
			HStack(spacing: 8) {
				Button(NSLocalizedString("Decline", comment: "")) { store.respond(item.id, false) }.buttonStyle(GlassButtonStyle())
				Button(NSLocalizedString("Accept", comment: "")) { store.respond(item.id, true) }.buttonStyle(GlassButtonStyle(prominent: true))
			}
		case .receiving:
			HStack(spacing: 8) {
				if item.progress > 0 {
					ProgressView(value: item.progress).tint(Palette.accent).frame(width: 90)
					Text("\(Int(item.progress * 100))%").monospacedDigit().foregroundStyle(.secondary)
				} else {
					ProgressView().controlSize(.small)
					Text(NSLocalizedString("Receiving", value: "Receiving", comment: "")).foregroundStyle(.secondary)
				}
			}
			.font(.system(size: 12))
		case .done:
			Button(NSLocalizedString("ShowInFinder", value: "Show", comment: "")) {
				NSWorkspace.shared.activateFileViewerSelecting(item.urls)
			}
			.buttonStyle(GlassButtonStyle())
		case .declined:
			Text(NSLocalizedString("TransferDeclined", value: "Declined", comment: "")).font(.system(size: 12)).foregroundStyle(.secondary)
		case .failed:
			Text(NSLocalizedString("TransferFailed", value: "Failed", comment: "")).font(.system(size: 12)).foregroundStyle(Palette.warning)
		}
	}
}
