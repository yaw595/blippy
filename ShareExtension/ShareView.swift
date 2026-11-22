// SPDX-License-Identifier: Apache-2.0
//
//  ShareView.swift
//  ShareExtension
//
//  SwiftUI interface shared by the Share sheet and the main window:
//  device picker, transfer progress, QR sheet. Liquid Glass on macOS 26+, materials before.
//

import SwiftUI
import AppKit
import QuickLookThumbnailing
import NearbyShare

// MARK: - Palette

extension Color {
	init(hex: UInt32) {
		self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
				  blue: Double(hex & 0xFF) / 255, opacity: 1)
	}
}

enum Palette {
	/// Matches the app icon's blue.
	static let accent = Color(hex: 0x3D7DF2)
	static let warning = Color(hex: 0xFF9F0A)
	static let success = Color(hex: 0x22B573)
}

// MARK: - Liquid Glass helpers

@available(macOS 26.0, *)
private func makeGlass(tint: Color?, interactive: Bool) -> Glass {
	var glass = Glass.regular
	if let tint { glass = glass.tint(tint) }
	if interactive { glass = glass.interactive() }
	return glass
}

extension View {
	@ViewBuilder
	func glass<S: InsettableShape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
		if #available(macOS 26.0, *) {
			self.glassEffect(makeGlass(tint: tint, interactive: interactive), in: shape)
		} else {
			self.background(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(Material.ultraThin), in: shape)
				.overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
		}
	}
}

extension View {
	/// The standard card: a soft fill with a hairline edge. Adapts to Light and Dark.
	func card(cornerRadius: CGFloat = 16) -> some View {
		background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(Color.primary.opacity(0.045)))
			.overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
	}
}

struct GlassButtonStyle: ButtonStyle {
	var prominent = false

	func makeBody(configuration: Configuration) -> some View {
		configuration.label
			.font(.system(size: 13, weight: .semibold))
			.foregroundStyle(prominent ? Color.white : Color.primary)
			.padding(.horizontal, 18)
			.padding(.vertical, 9)
			.glass(Capsule(), tint: prominent ? Palette.accent : nil, interactive: true)
			.opacity(configuration.isPressed ? 0.85 : 1)
			.scaleEffect(configuration.isPressed ? 0.97 : 1)
			.animation(.easeOut(duration: 0.12), value: configuration.isPressed)
	}
}

// MARK: - Phone icon (matches Design/phone.svg)

struct PhoneIcon: View {
	enum Status { case idle, sending(Double), success, failed }

	var height: CGFloat
	var status: Status = .idle

	var body: some View {
		let u = height / 120
		let shape = RoundedRectangle(cornerRadius: 14 * u, style: .continuous)

		ZStack {
			shape.fill(Color.primary.opacity(0.05))
			switch status {
			case .idle: EmptyView()
			case .sending(let p): liquid(Palette.accent, fraction: p, shape: shape)
			case .success: liquid(Palette.accent, fraction: 1, shape: shape)
			case .failed: liquid(Palette.warning, fraction: 1, shape: shape)
			}
			switch status {
			case .success: Check(size: 34 * u, lineWidth: 6 * u)
			case .failed: Image(systemName: "exclamationmark").font(.system(size: 30 * u, weight: .bold)).foregroundStyle(.white)
			default: EmptyView()
			}
			Circle().fill(Color.primary) // punch-hole camera
				.frame(width: 6 * u, height: 6 * u)
				.frame(maxHeight: .infinity, alignment: .top).padding(.top, 11 * u)
			Capsule().fill(Color.primary) // home bar
				.frame(width: 20 * u, height: 4 * u)
				.frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 9 * u)
			shape.strokeBorder(Color.primary, lineWidth: 3 * u)
		}
		.frame(width: 64 * u, height: height)
	}

	/// Flat fill that rises from the bottom, with a thin surface line.
	private func liquid(_ color: Color, fraction: Double, shape: RoundedRectangle) -> some View {
		ZStack(alignment: .top) {
			color
			Rectangle().fill(.white.opacity(0.45)).frame(height: 1.5)
		}
		.frame(height: max(0, min(1, fraction)) * height)
		.frame(maxHeight: .infinity, alignment: .bottom)
		.clipShape(shape)
		.animation(.easeInOut(duration: 0.4), value: fraction)
	}
}

/// Checkmark that draws itself in.
private struct Check: View {
	let size: CGFloat
	let lineWidth: CGFloat
	@State private var drawn = false

	var body: some View {
		Path { p in
			p.move(to: CGPoint(x: size * 0.14, y: size * 0.54))
			p.addLine(to: CGPoint(x: size * 0.40, y: size * 0.78))
			p.addLine(to: CGPoint(x: size * 0.86, y: size * 0.24))
		}
		.trim(from: 0, to: drawn ? 1 : 0)
		.stroke(Color.white, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
		.frame(width: size, height: size)
		.onAppear { withAnimation(.easeOut(duration: 0.45).delay(0.25)) { drawn = true } }
	}
}

/// Small file preview (Quick Look thumbnail), falling back to the file's icon while it loads.
struct FileThumb: View {
	let url: URL?
	var fallback: NSImage?
	var size: CGFloat = 28
	@State private var thumbnail: NSImage?

	var body: some View {
		Image(nsImage: thumbnail ?? fallback ?? (url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage()))
			.resizable().interpolation(.high).aspectRatio(contentMode: .fit)
			.frame(width: size, height: size)
			.clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
			.task(id: url) {
				guard let url, url.isFileURL else { return }
				let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: size, height: size),
														   scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
				if let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
					thumbnail = representation.nsImage
				}
			}
	}
}

private struct DeviceGlyph: View {
	let device: ShareModel.Device
	var height: CGFloat
	var status: PhoneIcon.Status = .idle

	var body: some View {
		if device.isComputer {
			Image(systemName: "laptopcomputer").font(.system(size: height * 0.62, weight: .light)).frame(height: height)
		} else {
			PhoneIcon(height: height, status: status)
		}
	}
}

// MARK: - Model

final class ShareModel: ObservableObject {
	enum Mode { case shareSheet, window }

	struct FileSummary {
		var title: String
		var subtitle: String
		var icon: NSImage
		var thumbURL: URL?
	}

	struct Device: Identifiable, Equatable {
		let id: String
		let name: String
		let isComputer: Bool

		init(_ info: RemoteDeviceInfo) {
			id = info.id ?? info.name
			name = info.name
			isComputer = info.type == .computer
		}
	}

	enum Phase: Equatable {
		case connecting, sending, finished
		case confirming(pin: String)
		case failed(String)

		var isDone: Bool {
			switch self {
			case .finished, .failed: return true
			default: return false
			}
		}
	}

	/// One outgoing transfer (one device).
	struct Transfer: Identifiable, Equatable {
		let device: Device
		var phase: Phase = .connecting
		var progress = 0.0
		var eta: String?
		var id: String { device.id }
	}

	@Published var mode: Mode = .shareSheet
	@Published var headerIcon: NSImage?
	@Published var file = FileSummary(title: "", subtitle: "", icon: NSImage())
	@Published var hasFiles = false
	@Published var notice: String?
	@Published var devices: [Device] = []
	@Published var selected: Set<String> = []
	@Published var transfers: [Transfer] = []
	@Published var showQRCode = false
	@Published var qrImage: NSImage?
	/// Phones on the network that aren't showing a name (Quick Share closed or not set to Everyone).
	@Published var hiddenCount = 0
	@Published var showHelp = false
	/// The QR code opens by itself once per session when no phone turns up.
	var autoQRShown = false
	/// Set in the main window so the help can jump to the Cable page.
	var onShowCable: (() -> Void)?

	var onActivate: (Device) -> Void = { _ in }
	var onToggle: (Device) -> Void = { _ in }
	var onSendSelected: () -> Void = {}
	var onDropOnDevice: (Device, [URL]) -> Void = { _, _ in }
	var onDropFiles: ([URL]) -> Void = { _ in }
	var onClearFiles: () -> Void = {}
	var onChooseFiles: () -> Void = {}
	var onShowQRCode: () -> Void = {}
	var onCancel: () -> Void = {}
	var onDone: () -> Void = {}

	var isTransferring: Bool { !transfers.isEmpty }
	var isFinished: Bool { !transfers.isEmpty && transfers.allSatisfy { $0.phase.isDone } }
}

// MARK: - Root

struct ShareRootView: View {
	static let size = CGSize(width: 440, height: 500)

	@ObservedObject var model: ShareModel
	@State private var dropTargeted = false

	var body: some View {
		let fixed = model.mode == .shareSheet
		VStack(spacing: 0) {
			if fixed {
				HStack(spacing: 8) {
					if let icon = model.headerIcon {
						Image(nsImage: icon).resizable().interpolation(.high).frame(width: 28, height: 28)
					}
					Text("Blippy").font(.system(size: 15, weight: .semibold))
					Spacer()
				}
				.padding(.horizontal, 24)
				.padding(.top, 18)
			}

			if !model.isTransferring {
				Group {
					if model.hasFiles || model.mode == .shareSheet {
						FileChip(file: model.file, onClear: model.mode == .window ? model.onClearFiles : nil)
					} else {
						Label(NSLocalizedString("DropHint", value: "Drop files here", comment: ""), systemImage: "arrow.down.doc")
							.font(.system(size: 13, weight: .medium))
							.foregroundStyle(.secondary)
							.padding(.horizontal, 14).padding(.vertical, 8)
							.glass(Capsule())
					}
				}
				.padding(.top, model.mode == .shareSheet ? 14 : 20)
			}

			Group {
				if model.isTransferring {
					TransferView(model: model)
				} else if model.devices.isEmpty {
					SearchingView(model: model)
				} else {
					DeviceGrid(model: model)
				}
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)

			FooterView(model: model)
				.padding(.horizontal, 24)
				.padding(.bottom, 20)
		}
		.frame(width: fixed ? Self.size.width : nil, height: fixed ? Self.size.height : nil)
		.frame(maxWidth: fixed ? nil : .infinity, maxHeight: fixed ? nil : .infinity)
		.background(Color(nsColor: .windowBackgroundColor))
		.overlay {
			if dropTargeted {
				RoundedRectangle(cornerRadius: 18, style: .continuous)
					.strokeBorder(Palette.accent, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
					.padding(8).allowsHitTesting(false)
			}
		}
		.dropDestination(for: URL.self) { urls, _ in
			guard model.mode == .window, !model.isTransferring, !urls.isEmpty else { return false }
			model.onDropFiles(urls)
			return true
		} isTargeted: { dropTargeted = $0 && model.mode == .window && !model.isTransferring }
		.sheet(isPresented: $model.showQRCode) { QRCodeSheet(model: model) }
		.sheet(isPresented: $model.showHelp) { PhoneHelpSheet(model: model) }
	}
}

private struct FileChip: View {
	let file: ShareModel.FileSummary
	var onClear: (() -> Void)?

	var body: some View {
		HStack(spacing: 8) {
			FileThumb(url: file.thumbURL, fallback: file.icon, size: 26)
			Text(file.title).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
			if !file.subtitle.isEmpty {
				Text(file.subtitle).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
			}
			if let onClear {
				Button(action: onClear) {
					Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
				}
				.buttonStyle(.plain)
				.accessibilityLabel(NSLocalizedString("ClearFiles", value: "Remove files", comment: ""))
			}
		}
		.padding(.horizontal, 14).padding(.vertical, 8)
		.glass(Capsule())
		.frame(maxWidth: 380)
	}
}

// MARK: - Searching

/// Two quick pops, then a slow ease back and a short rest, repeating. Only scale/opacity animate,
/// so nothing in the layout can drift.
struct PulseRing: View {
	var size: CGFloat
	var color: Color = Palette.accent
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	private struct Ripple { var scale = 1.0; var opacity = 0.0 }

	var body: some View {
		if reduceMotion {
			Circle().fill(color.opacity(0.14)).frame(width: size, height: size)
		} else {
			KeyframeAnimator(initialValue: Ripple(), repeating: true) { ripple in
				Circle().fill(color.opacity(0.16)).frame(width: size, height: size)
					.scaleEffect(ripple.scale).opacity(ripple.opacity)
			} keyframes: { _ in
				KeyframeTrack(\.scale) {
					CubicKeyframe(1.16, duration: 0.18)  // pop
					CubicKeyframe(1.04, duration: 0.14)
					CubicKeyframe(1.3, duration: 0.2)    // pop
					CubicKeyframe(1.0, duration: 1.1)    // ease back
					CubicKeyframe(1.0, duration: 0.5)    // rest
				}
				KeyframeTrack(\.opacity) {
					CubicKeyframe(1, duration: 0.18)
					CubicKeyframe(0.6, duration: 0.14)
					CubicKeyframe(1, duration: 0.2)
					CubicKeyframe(0, duration: 1.1)
					CubicKeyframe(0, duration: 0.5)
				}
			}
		}
	}
}

/// Inner circle holds the device placeholder; the outer circle pulses.
private struct SearchingView: View {
	@ObservedObject var model: ShareModel
	@State private var needsHelp = false

	/// How long Blippy keeps searching quietly before it shows the QR code and the help buttons. Searching itself never stops.
	private static let patience: UInt64 = 25

	private var hint: String {
		if model.hiddenCount == 1 {
			return NSLocalizedString("HiddenOne", value: "1 phone is nearby but hidden. Open Quick Share on it and choose Everyone, or scan the QR code.", comment: "")
		}
		if model.hiddenCount > 1 {
			return String(format: NSLocalizedString("HiddenMany", value: "%d phones are nearby but hidden. Open Quick Share on one and choose Everyone, or scan the QR code.", comment: ""), model.hiddenCount)
		}
		return needsHelp
			? NSLocalizedString("SearchingHelp", value: "Same Wi-Fi? Phone unlocked, with Quick Share open?", comment: "")
			: NSLocalizedString("SearchingHint", value: "Tap Receive on your phone", comment: "")
	}

	var body: some View {
		VStack(spacing: 18) {
			ZStack {
				PulseRing(size: 150)
				Circle().fill(Palette.accent.opacity(0.2)).frame(width: 104, height: 104)
				PhoneIcon(height: 54).opacity(0.5)
			}
			.frame(width: 200, height: 170)

			VStack(spacing: 4) {
				Text(NSLocalizedString("Searching", value: "Looking for devices", comment: "")).font(.system(size: 15, weight: .semibold))
				Text(hint)
					.font(.system(size: 12))
					.foregroundStyle(needsHelp || model.hiddenCount > 0 ? Palette.warning : .secondary)
					.multilineTextAlignment(.center)
					.frame(maxWidth: 320)
					.fixedSize(horizontal: false, vertical: true)
			}

			if needsHelp || model.hiddenCount > 0 {
				HStack(spacing: 8) {
					Button { model.onShowQRCode() } label: { Label(NSLocalizedString("ShowQR", value: "QR code", comment: ""), systemImage: "qrcode") }
						.buttonStyle(GlassButtonStyle(prominent: true))
					if let cable = model.onShowCable {
						Button { cable() } label: { Label(NSLocalizedString("UseCable", value: "Use cable", comment: ""), systemImage: "cable.connector") }
							.buttonStyle(GlassButtonStyle())
					}
					Button { model.showHelp = true } label: { Label(NSLocalizedString("HelpButton", value: "Help", comment: ""), systemImage: "questionmark.circle") }
						.buttonStyle(GlassButtonStyle())
				}
			}
		}
		.task {
			try? await Task.sleep(nanoseconds: Self.patience * 1_000_000_000)
			needsHelp = true
			// Still nothing after the wait: open the QR code, which works even when the phone is hidden.
			if !model.autoQRShown, model.hasFiles || model.mode == .shareSheet, !model.showQRCode {
				model.autoQRShown = true
				model.onShowQRCode()
			}
		}
		.accessibilityElement(children: .contain)
	}
}

// MARK: - Devices

private struct DeviceGrid: View {
	@ObservedObject var model: ShareModel
	@FocusState private var focused: Bool
	@State private var cursor = 0

	var body: some View {
		let count = model.devices.count
		let columns = min(count, 3)
		let current = min(cursor, count - 1)
		ScrollView {
			LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns), spacing: 20) {
				ForEach(Array(model.devices.enumerated()), id: \.element.id) { index, device in
					DeviceOrb(device: device, model: model, ringed: focused && index == current)
				}
			}
			.frame(maxWidth: CGFloat(columns) * 132)
			.frame(maxWidth: .infinity)
			.padding(.vertical, 24)
		}
		.focusable()
		.focused($focused)
		.focusEffectDisabled()
		.onAppear { focused = true }
		.onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .return, .space]) { press in
			switch press.key {
			case .leftArrow: cursor = max(0, current - 1)
			case .rightArrow: cursor = min(count - 1, current + 1)
			case .upArrow: cursor = max(0, current - columns)
			case .downArrow: cursor = min(count - 1, current + columns)
			case .return: model.onActivate(model.devices[current])
			default: model.onToggle(model.devices[current])
			}
			return .handled
		}
	}
}

/// Click sends right away; with a selection, click toggles. The corner badge adds a device to the selection.
private struct DeviceOrb: View {
	let device: ShareModel.Device
	@ObservedObject var model: ShareModel
	let ringed: Bool

	@State private var hovered = false
	@State private var dropTargeted = false
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	var body: some View {
		let isSelected = model.selected.contains(device.id)
		let lifted = hovered || dropTargeted
		VStack(spacing: 10) {
			DeviceGlyph(device: device, height: 54)
				.frame(width: 96, height: 96)
				.glass(Circle(), interactive: true)
				.overlay(Circle().strokeBorder(Palette.accent, lineWidth: 2.5).opacity(dropTargeted || ringed || isSelected ? 1 : 0))
				.overlay(alignment: .topTrailing) {
					if hovered || !model.selected.isEmpty {
						Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
							.font(.system(size: 22))
							.foregroundStyle(isSelected ? Palette.accent : Color.secondary)
							.background(Circle().fill(Color(nsColor: .windowBackgroundColor)).padding(2))
							.onTapGesture { model.onToggle(device) }
					}
				}
			Text(device.name).font(.system(size: 13, weight: .semibold)).lineLimit(1).frame(maxWidth: 120)
		}
		.transition(.scale(scale: 0.85).combined(with: .opacity))
		.contentShape(Rectangle())
		.onTapGesture { model.selected.isEmpty ? model.onActivate(device) : model.onToggle(device) }
		.scaleEffect(lifted && !reduceMotion ? 1.06 : 1)
		.animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.75), value: lifted)
		.onHover { hovered = $0 }
		.dropDestination(for: URL.self) { urls, _ in
			guard !urls.isEmpty else { return false }
			model.onDropOnDevice(device, urls)
			return true
		} isTargeted: { dropTargeted = $0 }
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(device.name)
		.accessibilityValue(isSelected ? NSLocalizedString("Selected", value: "Selected", comment: "") : "")
		.accessibilityAddTraits(.isButton)
		.accessibilityAction { model.onActivate(device) }
		.accessibilityAction(named: Text(NSLocalizedString("ToggleSelect", value: "Select", comment: ""))) { model.onToggle(device) }
	}
}

// MARK: - Transfer

private struct TransferView: View {
	@ObservedObject var model: ShareModel

	var body: some View {
		let many = model.transfers.count > 1
		VStack(spacing: 18) {
			if many {
				LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12, alignment: .top)], spacing: 18) {
					ForEach(model.transfers) { TransferColumn(transfer: $0, compact: true) }
				}
				.frame(maxWidth: CGFloat(min(model.transfers.count, 4)) * 124)
			} else if let only = model.transfers.first {
				TransferColumn(transfer: only, compact: false)
			}
			Text(model.file.title).font(.system(size: 12)).foregroundStyle(.secondary)
				.lineLimit(1).truncationMode(.middle).frame(maxWidth: 280)
		}
		.padding(.horizontal, 36)
	}
}

private struct TransferColumn: View {
	let transfer: ShareModel.Transfer
	let compact: Bool

	private var status: PhoneIcon.Status {
		switch transfer.phase {
		case .sending: return .sending(transfer.progress)
		case .finished: return .success
		case .failed: return .failed
		default: return .idle
		}
	}

	private var rippling: Bool {
		switch transfer.phase {
		case .connecting, .confirming, .sending: return true
		default: return false
		}
	}

	@State private var pop = false

	var body: some View {
		VStack(spacing: compact ? 6 : 10) {
			ZStack {
				if rippling { PulseRing(size: compact ? 84 : 128) }
				DeviceGlyph(device: transfer.device, height: compact ? 72 : 110, status: status)
					.scaleEffect(pop ? 1.07 : 1)
			}
			.frame(height: compact ? 96 : 150)
			.onChange(of: transfer.phase) { _, phase in
				guard phase == .finished else { return }
				withAnimation(.spring(response: 0.3, dampingFraction: 0.45)) { pop = true }
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
					withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { pop = false }
				}
			}
			Text(transfer.device.name).font(.system(size: compact ? 13 : 17, weight: .semibold)).lineLimit(1)
			detail.font(.system(size: compact ? 11 : 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
		}
		.accessibilityElement(children: .combine)
	}

	@ViewBuilder
	private var detail: some View {
		switch transfer.phase {
		case .connecting:
			HStack(spacing: 6) { ProgressView().controlSize(.small); if !compact { Text(NSLocalizedString("Connecting", value: "Connecting...", comment: "")) } }
		case .confirming(let pin):
			VStack(spacing: 8) {
				Text(pin).font(.system(size: compact ? 16 : 26, weight: .semibold, design: .rounded).monospacedDigit())
					.foregroundStyle(.primary).padding(.horizontal, compact ? 12 : 22).padding(.vertical, compact ? 4 : 8).glass(Capsule())
				if !compact { Text(NSLocalizedString("MatchPin", value: "Match this PIN on your phone", comment: "")) }
			}
		case .sending:
			Text([ "\(Int(transfer.progress * 100))%", compact ? nil : transfer.eta ].compactMap { $0 }.joined(separator: " · ")).monospacedDigit()
				.contentTransition(.numericText())
				.animation(.easeOut(duration: 0.25), value: transfer.progress)
		case .finished:
			Text(NSLocalizedString("Sent", value: "Sent", comment: ""))
		case .failed(let message):
			Text(message).lineLimit(compact ? 2 : 4).fixedSize(horizontal: false, vertical: true)
		}
	}
}

// MARK: - Footer

private struct FooterView: View {
	@ObservedObject var model: ShareModel

	var body: some View {
		VStack(spacing: 10) {
			if let notice = model.notice, !model.isTransferring {
				Text(notice).font(.system(size: 11)).foregroundStyle(Palette.warning)
			}
			HStack(spacing: 10) {
				if !model.isTransferring {
					Button(action: model.onShowQRCode) { Image(systemName: "qrcode") }
						.buttonStyle(GlassButtonStyle())
						.help(NSLocalizedString("QrHelp", value: "Show a QR code for your phone to scan", comment: ""))
						.accessibilityLabel(NSLocalizedString("UseQrCode", value: "Use QR Code", comment: ""))
				}
				Spacer()
				if model.isFinished {
					Button(NSLocalizedString("Done", value: "Done", comment: ""), action: model.onDone)
						.buttonStyle(GlassButtonStyle(prominent: true)).keyboardShortcut(.defaultAction)
				} else if model.isTransferring {
					Button(NSLocalizedString("Cancel", value: "Cancel", comment: ""), action: model.onCancel)
						.buttonStyle(GlassButtonStyle()).keyboardShortcut(.cancelAction)
				} else if !model.selected.isEmpty {
					Button(model.selected.count == 1
						   ? NSLocalizedString("Send", value: "Send", comment: "")
						   : String(format: NSLocalizedString("SendToN", value: "Send to %d", comment: ""), model.selected.count),
						   action: model.onSendSelected)
						.buttonStyle(GlassButtonStyle(prominent: true)).keyboardShortcut(.defaultAction)
				} else if model.mode == .window {
					Button(NSLocalizedString("ChooseFiles", value: "Choose Files…", comment: ""), action: model.onChooseFiles)
						.buttonStyle(GlassButtonStyle(prominent: true))
				} else {
					Button(NSLocalizedString("Cancel", value: "Cancel", comment: ""), action: model.onCancel)
						.buttonStyle(GlassButtonStyle()).keyboardShortcut(.cancelAction)
				}
			}
		}
	}
}

// MARK: - QR code sheet

private struct QRCodeSheet: View {
	@ObservedObject var model: ShareModel

	var body: some View {
		VStack(spacing: 18) {
			VStack(spacing: 6) {
				Text(NSLocalizedString("QrTitle", value: "Scan with your phone", comment: "")).font(.system(size: 18, weight: .semibold))
				Text(NSLocalizedString("QrBody", value: "Open Quick Share on your phone and scan this code (the camera works too). It works even when the phone is hidden.", comment: ""))
					.font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
					.fixedSize(horizontal: false, vertical: true)
			}
			if let image = model.qrImage {
				// White tile on purpose: QR codes need dark-on-light contrast, even in Dark Mode.
				Image(nsImage: image).resizable().interpolation(.none).frame(width: 200, height: 200)
					.padding(16)
					.background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color.white))
					.shadow(color: .black.opacity(0.1), radius: 16, y: 6)
					.accessibilityLabel(NSLocalizedString("QrAccessibility", value: "QR code for Quick Share", comment: ""))
			}
			Button(NSLocalizedString("Cancel", value: "Cancel", comment: "")) { model.showQRCode = false }
				.buttonStyle(GlassButtonStyle()).keyboardShortcut(.cancelAction)
		}
		.padding(28)
		.frame(width: 380)
		.background(Color(nsColor: .windowBackgroundColor))
	}
}

// MARK: - "Can't see your phone?" help

private struct PhoneHelpSheet: View {
	@ObservedObject var model: ShareModel

	private func row(_ number: String, _ text: String) -> some View {
		HStack(alignment: .top, spacing: 12) {
			Text(number).font(.system(size: 12, weight: .semibold)).frame(width: 24, height: 24).glass(Circle())
			Text(text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
		}
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			Text(NSLocalizedString("HelpTitle", value: "Can’t see your phone?", comment: "")).font(.system(size: 18, weight: .semibold))
			VStack(alignment: .leading, spacing: 10) {
				row("1", NSLocalizedString("HelpWifi", value: "Put the Mac and the phone on the same Wi-Fi (not a guest network, no VPN).", comment: ""))
				row("2", NSLocalizedString("HelpAwake", value: "Unlock the phone and keep the screen on. If it locks quickly, turn off auto-lock or set a long screen timeout (Settings → Display → Screen timeout). Samsung also stops sharing when the screen locks.", comment: ""))
				row("3", NSLocalizedString("HelpEveryone", value: "Open Quick Share and set “Who can share with you” to Everyone (Samsung: Anyone nearby, which lasts only 10 minutes). Keep that screen open.", comment: ""))
				row("4", NSLocalizedString("HelpBluetooth", value: "Turn on Bluetooth and Location on the phone.", comment: ""))
			}
			Text(NSLocalizedString("HelpStill", value: "Still not there? Scan the QR code, or use a USB cable.", comment: ""))
				.font(.system(size: 12)).foregroundStyle(.secondary)
			HStack(spacing: 8) {
				Button(NSLocalizedString("ShowQR", value: "QR code", comment: "")) { model.showHelp = false; model.onShowQRCode() }.buttonStyle(GlassButtonStyle(prominent: true))
				if let cable = model.onShowCable {
					Button(NSLocalizedString("UseCable", value: "Use cable", comment: "")) { model.showHelp = false; cable() }.buttonStyle(GlassButtonStyle())
				}
				Spacer()
				Button(NSLocalizedString("Done", value: "Done", comment: "")) { model.showHelp = false }.buttonStyle(GlassButtonStyle()).keyboardShortcut(.cancelAction)
			}
		}
		.padding(26)
		.frame(width: 420)
		.background(Color(nsColor: .windowBackgroundColor))
	}
}
