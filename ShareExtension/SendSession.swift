// SPDX-License-Identifier: Apache-2.0
//
//  SendSession.swift
//  Shared by the Share extension and the main app window.
//
//  One "send these files to nearby devices" flow: discovery, device list and selection,
//  zipping folders, one outgoing transfer per device (progress + ETA each), finish cue.
//  Drives a ShareModel that ShareRootView renders.
//

import AppKit
import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers
import NearbyShare

final class SendSession: NSObject, ShareExtensionDelegate {
	typealias Mode = ShareModel.Mode
	typealias Device = ShareModel.Device

	let mode: Mode
	let model = ShareModel()

	private(set) var urls: [URL] = []
	private var tempDirs: [URL] = []
	private var found: [String: RemoteDeviceInfo] = [:]
	private var handles: [String: Handle] = [:]
	private var lastError: Error?
	private var discovering = false
	private var registered = false
	private var reported = false
	private var canceledByUser = false

	private static let lastDeviceKey = "Blippy.lastDevice"

	/// Builds the QR code image for a Quick Share URL.
	var makeQRImage: (String) -> NSImage? = SendSession.plainQRImage
	/// Window mode: asks the user to pick files, then calls back with them.
	var chooseFiles: (@escaping ([URL]) -> Void) -> Void = { _ in }
	/// Share sheet: the user canceled.
	var onCancel: () -> Void = {}
	/// Share sheet: the flow ended (nil error on success).
	var onFinish: (Error?) -> Void = { _ in }
	/// Called once when every transfer has ended and at least one succeeded.
	var onSent: ([ShareModel.Transfer]) -> Void = { _ in }

	init(mode: Mode) {
		self.mode = mode
		super.init()
		model.mode = mode
		model.onActivate = { [weak self] in Chime.tap(); self?.send([$0]) }
		model.onToggle = { [weak self] in Chime.tap(); self?.toggle($0) }
		model.onSendSelected = { [weak self] in
			guard let self else { return }
			self.send(self.model.devices.filter { self.model.selected.contains($0.id) })
		}
		model.onDropOnDevice = { [weak self] device, dropped in
			self?.setFiles(dropped) { self?.send([device]) }
		}
		model.onDropFiles = { [weak self] in self?.setFiles($0) }
		model.onClearFiles = { [weak self] in self?.clearFiles() }
		model.onChooseFiles = { [weak self] in self?.chooseFiles { self?.setFiles($0) } }
		model.onCancel = { [weak self] in self?.cancel() }
		model.onDone = { [weak self] in self?.done() }
		model.onShowQRCode = { [weak self] in self?.showQRCode() }
	}

	// MARK: - Lifecycle

	func start() {
		if !discovering {
			NearbyConnectionManager.shared.startDeviceDiscovery()
			discovering = true
		}
		if !registered {
			NearbyConnectionManager.shared.addShareExtensionDelegate(self)
			registered = true
		}
	}

	func stop() {
		for transfer in model.transfers where !transfer.phase.isDone {
			NearbyConnectionManager.shared.cancelOutgoingTransfer(id: transfer.id)
		}
		stopDiscovery()
		if registered {
			NearbyConnectionManager.shared.removeShareExtensionDelegate(self)
			registered = false
		}
		tempDirs.forEach { try? FileManager.default.removeItem(at: $0) }
		tempDirs = []
	}

	private func stopDiscovery() {
		if discovering {
			NearbyConnectionManager.shared.stopDeviceDiscovery()
			discovering = false
		}
	}

	// MARK: - Files

	/// Stages files to send. Folders are zipped first (Quick Share only sends files).
	func setFiles(_ new: [URL], then: (() -> Void)? = nil) {
		let folders = new.filter(Self.isDirectory)
		guard !folders.isEmpty else {
			apply(new)
			then?()
			return
		}
		model.notice = NSLocalizedString("Zipping", value: "Zipping folder…", comment: "")
		DispatchQueue.global(qos: .userInitiated).async {
			let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Blippy-\(UUID().uuidString)")
			let zips = folders.compactMap { Self.zip($0, into: dir) }
			DispatchQueue.main.async {
				self.tempDirs.append(dir)
				self.model.notice = zips.count < folders.count ? NSLocalizedString("ZipFailed", value: "Couldn’t zip a folder", comment: "") : nil
				self.apply(new.filter { !Self.isDirectory($0) } + zips)
				then?()
			}
		}
	}

	private func apply(_ files: [URL]) {
		guard !files.isEmpty else { return }
		urls = files
		model.file = Self.summary(for: files)
		model.hasFiles = true
	}

	private func clearFiles() {
		urls = []
		model.hasFiles = false
		model.notice = nil
	}

	// MARK: - Sending

	private func toggle(_ device: Device) {
		guard !model.isTransferring else { return }
		if model.selected.contains(device.id) {
			model.selected.remove(device.id)
		} else {
			model.selected.insert(device.id)
		}
	}

	private func send(_ devices: [Device]) {
		guard !devices.isEmpty, !model.isTransferring else { return }
		guard !urls.isEmpty else {
			guard mode == .window else { return }
			chooseFiles { [weak self] picked in
				self?.setFiles(picked) { self?.send(devices) }
			}
			return
		}
		stopDiscovery()
		reported = false
		canceledByUser = false
		lastError = nil
		model.selected = []
		model.showQRCode = false
		UserDefaults.standard.set(devices[0].name, forKey: Self.lastDeviceKey)
		withAnimation(.easeInOut(duration: 0.3)) {
			model.transfers = devices.map { ShareModel.Transfer(device: $0) }
		}
		for device in devices {
			guard found[device.id] != nil else {
				fail(device.id, NearbyError.canceled(reason: .timedOut))
				continue
			}
			let handle = Handle(id: device.id, session: self)
			handles[device.id] = handle
			NearbyConnectionManager.shared.startOutgoingTransfer(deviceID: device.id, delegate: handle, urls: urls)
		}
	}

	private func cancel() {
		canceledByUser = true
		for transfer in model.transfers where !transfer.phase.isDone {
			NearbyConnectionManager.shared.cancelOutgoingTransfer(id: transfer.id)
			update(transfer.id) { $0.phase = .failed(NSLocalizedString("TransferCanceled", value: "Canceled", comment: "")) }
		}
		if mode == .shareSheet { onCancel() }
	}

	private func done() {
		if mode == .shareSheet {
			onFinish(lastError)
			return
		}
		// Window: back to the device list, ready for another send.
		stop()
		handles = [:]
		found = [:]
		lastError = nil
		clearFiles()
		model.devices = []
		model.transfers = []
		start()
	}

	private func showQRCode() {
		let key = NearbyConnectionManager.shared.generateQrCodeKey()
		guard let image = makeQRImage("https://quickshare.google/qrcode#key=\(key)") else { return }
		model.qrImage = image
		model.showQRCode = true
	}

	// MARK: - Transfer state

	fileprivate func update(_ id: String, _ change: @escaping (inout ShareModel.Transfer) -> Void) {
		onMain {
			guard let index = self.model.transfers.firstIndex(where: { $0.id == id }) else { return }
			change(&self.model.transfers[index])
			self.settle()
		}
	}

	fileprivate func fail(_ id: String, _ error: Error) {
		lastError = error
		let message: String
		if let nearby = error as? NearbyError, case let .canceled(reason) = nearby {
			switch reason {
			case .userRejected: message = NSLocalizedString("TransferDeclined", value: "Declined", comment: "")
			case .userCanceled: message = NSLocalizedString("TransferCanceled", value: "Canceled", comment: "")
			case .notEnoughSpace: message = NSLocalizedString("NotEnoughSpace", value: "Not enough disk space", comment: "")
			case .unsupportedType: message = NSLocalizedString("UnsupportedType", value: "Attachment type not supported", comment: "")
			case .timedOut: message = NSLocalizedString("TransferTimedOut", value: "Timed out", comment: "")
			}
		} else {
			message = error.localizedDescription
		}
		update(id) { $0.progress = 0; $0.phase = .failed(message) }
	}

	/// When every transfer has ended: play the cue once, report, and close the share sheet if all succeeded.
	private func settle() {
		guard model.isFinished, !reported else { return }
		reported = true
		let sent = model.transfers.filter { $0.phase == .finished }
		guard !sent.isEmpty else {
			if !canceledByUser { Chime.failure() }
			return
		}
		Chime.success()
		onSent(sent)
		if mode == .shareSheet, sent.count == model.transfers.count {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.onFinish(nil) }
		}
	}

	/// Receives one device's progress callbacks and tags them with the device id.
	private final class Handle: NSObject, ShareExtensionDelegate {
		let id: String
		weak var session: SendSession?
		private var start: Date?
		private var smoothed: Double?

		init(id: String, session: SendSession) {
			self.id = id
			self.session = session
		}

		func addDevice(device: RemoteDeviceInfo) {}
		func removeDevice(id: String) {}
		func startTransferWithQrCode(device: RemoteDeviceInfo) {}

		func connectionWasEstablished(pinCode: String) {
			session?.update(id) { $0.progress = 0; $0.phase = .confirming(pin: pinCode) }
		}

		func connectionFailed(with error: Error) {
			session?.fail(id, error)
		}

		func transferAccepted() {
			start = Date()
			session?.update(id) { $0.eta = nil; $0.phase = .sending }
		}

		func transferProgress(progress: Double) {
			let eta = estimate(progress)
			session?.update(id) { $0.progress = progress; if let eta { $0.eta = eta } }
		}

		func transferFinished() {
			session?.update(id) { $0.progress = 1; $0.phase = .finished }
		}

		/// Remaining time from the average speed so far, smoothed so the label doesn't jump.
		private func estimate(_ progress: Double) -> String? {
			guard let start, progress > 0.02, progress < 1 else { return nil }
			let elapsed = Date().timeIntervalSince(start)
			guard elapsed > 1 else { return nil }
			let raw = elapsed * (1 - progress) / progress
			let remaining = smoothed.map { $0 * 0.8 + raw * 0.2 } ?? raw
			smoothed = remaining
			let seconds = Int(remaining.rounded())
			if seconds < 10 { return NSLocalizedString("EtaSoon", value: "A few seconds left", comment: "") }
			if seconds < 60 { return String(format: NSLocalizedString("EtaSeconds", value: "%d sec left", comment: ""), (seconds + 2) / 5 * 5) }
			return String(format: NSLocalizedString("EtaMinutes", value: "%d min left", comment: ""), (seconds + 30) / 60)
		}
	}

	// MARK: - Discovery (ShareExtensionDelegate)

	func addDevice(device: RemoteDeviceInfo) {
		onMain {
			let new = Device(device)
			guard self.found[new.id] == nil else { return }
			self.found[new.id] = device
			// The device you used last goes first.
			let isLast = new.name == UserDefaults.standard.string(forKey: Self.lastDeviceKey)
			withAnimation(.easeOut(duration: 0.25)) {
				self.model.devices.insert(new, at: isLast ? 0 : self.model.devices.count)
			}
		}
	}

	func removeDevice(id: String) {
		onMain {
			guard !self.model.isTransferring else { return }
			self.found[id] = nil
			self.model.selected.remove(id)
			withAnimation(.easeOut(duration: 0.25)) {
				self.model.devices.removeAll { $0.id == id }
			}
		}
	}

	func startTransferWithQrCode(device: RemoteDeviceInfo) {
		onMain {
			self.model.showQRCode = false
			self.found[Device(device).id] = device
			self.send([Device(device)])
		}
	}

	// Per-device callbacks arrive through Handle; these are unused on the session itself.
	func connectionWasEstablished(pinCode: String) {}
	func connectionFailed(with error: Error) {}
	func transferAccepted() {}
	func transferProgress(progress: Double) {}
	func transferFinished() {}

	// MARK: - Helpers

	private func onMain(_ block: @escaping () -> Void) {
		if Thread.isMainThread { block() } else { DispatchQueue.main.async(execute: block) }
	}

	private static func isDirectory(_ url: URL) -> Bool {
		var isDir: ObjCBool = false
		return url.isFileURL && FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
	}

	/// Zips a folder in-process (no child process, so it works inside the sandbox).
	private static func zip(_ folder: URL, into dir: URL) -> URL? {
		var result: URL?
		var error: NSError?
		NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &error) { zipped in
			try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
			let dest = dir.appendingPathComponent(folder.lastPathComponent + ".zip")
			if (try? FileManager.default.copyItem(at: zipped, to: dest)) != nil { result = dest }
		}
		return result
	}

	static func summary(for urls: [URL]) -> ShareModel.FileSummary {
		if urls.count == 1 {
			let url = urls[0]
			guard url.isFileURL else {
				return .init(title: url.absoluteString, subtitle: url.host ?? "", icon: NSImage(named: NSImage.networkName) ?? NSImage())
			}
			var parts: [String] = []
			if let kind = UTType(filenameExtension: url.pathExtension)?.localizedDescription { parts.append(kind.capitalized) }
			if let size = fileSize(of: url) { parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) }
			return .init(title: url.lastPathComponent, subtitle: parts.joined(separator: " · "), icon: NSWorkspace.shared.icon(forFile: url.path), thumbURL: url)
		}
		let total = urls.compactMap { fileSize(of: $0) }.reduce(0, +)
		return .init(
			title: String.localizedStringWithFormat(NSLocalizedString("NFiles", value: "%d files", comment: ""), urls.count),
			subtitle: total > 0 ? ByteCountFormatter.string(fromByteCount: total, countStyle: .file) : "",
			icon: NSImage(named: NSImage.multipleDocumentsName) ?? NSImage())
	}

	private static func fileSize(of url: URL) -> Int64? {
		guard url.isFileURL, let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return nil }
		return Int64(size)
	}

	static func openDownloads() {
		guard let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return }
		NSWorkspace.shared.open(downloads.resolvingSymlinksInPath())
	}

	static func plainQRImage(_ text: String) -> NSImage? {
		let filter = CIFilter.qrCodeGenerator()
		filter.message = Data(text.utf8)
		filter.correctionLevel = "M"
		guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)) else { return nil }
		let rep = NSCIImageRep(ciImage: output)
		let image = NSImage(size: rep.size)
		image.addRepresentation(rep)
		return image
	}
}

/// Completion sounds. The sound object is kept in a static: a sound that is released stops playing at once.
enum Chime {
	static let enabledKey = "Blippy.sounds"
	private static var current: NSSound?

	static var enabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

	static func success() { play("Glass"); haptic(.levelChange) }
	static func failure() { play("Basso"); haptic(.generic) }
	/// A light tick when you pick a device (trackpad only; independent of the sound setting).
	static func tap() { haptic(.alignment) }

	private static func haptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
		NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
	}

	private static func play(_ name: String) {
		guard enabled else { return }
		DispatchQueue.main.async {
			current = NSSound(named: NSSound.Name(name))
			current?.play()
		}
	}
}
