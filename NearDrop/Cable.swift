// SPDX-License-Identifier: Apache-2.0
//
//  Cable.swift
//  NearDrop
//
//  Sending over USB. Main path: the bundled `adb` pushes files to /sdcard/Download on the phone,
//  checks the size afterwards, and asks the phone to index the file.
//  Fallback: Image Capture (PTP "Photo transfer" mode) for photos and videos only.
//

import AppKit
import IOKit
import ImageCaptureCore
import UniformTypeIdentifiers

// MARK: - adb

enum ADB {
	struct Device { let serial: String; let state: String }

	/// The copy bundled in the app first; a few usual install locations as a fallback.
	static var path: String? {
		[Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/adb").path,
		 NSHomeDirectory() + "/Library/Android/sdk/platform-tools/adb",
		 "/opt/homebrew/bin/adb", "/usr/local/bin/adb"]
			.first { FileManager.default.isExecutableFile(atPath: $0) }
	}

	/// Runs adb. Output goes to a temp file rather than a pipe: `adb start-server` leaves a daemon
	/// running that would keep a pipe open forever.
	static func run(_ args: [String], timeout: TimeInterval? = 20, started: ((Process) -> Void)? = nil) async -> (status: Int32, output: String) {
		guard let path else { return (-1, "adb not found") }
		return await withCheckedContinuation { continuation in
			let log = FileManager.default.temporaryDirectory.appendingPathComponent("adb-\(UUID().uuidString).log")
			FileManager.default.createFile(atPath: log.path, contents: nil)
			let process = Process()
			process.executableURL = URL(fileURLWithPath: path)
			process.arguments = args
			process.standardInput = FileHandle.nullDevice
			if let handle = try? FileHandle(forWritingTo: log) {
				process.standardOutput = handle
				process.standardError = handle
			}
			process.terminationHandler = { proc in
				let output = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
				try? FileManager.default.removeItem(at: log)
				continuation.resume(returning: (proc.terminationStatus, output.trimmingCharacters(in: .whitespacesAndNewlines)))
			}
			do {
				try process.run()
			} catch {
				continuation.resume(returning: (-1, error.localizedDescription))
				return
			}
			started?(process)
			if let timeout {
				DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { if process.isRunning { process.terminate() } }
			}
		}
	}

	static func devices() async -> [Device] {
		await run(["devices"], timeout: 10).output.split(separator: "\n").compactMap { line in
			let parts = line.split(separator: "\t")
			guard parts.count == 2 else { return nil }
			return Device(serial: String(parts[0]), state: String(parts[1]))
		}
	}

	/// Single-quotes a string for the phone's shell.
	static func quote(_ text: String) -> String {
		"'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
	}
}

// MARK: - Model

@MainActor
final class CableModel: ObservableObject {
	static let shared = CableModel()

	enum Link: Equatable {
		case none, noAdb, unauthorized, offline
		case noDebugging(String)
		case ready(serial: String, name: String)
	}

	enum Phase { case idle, sending, finished }

	struct Item: Identifiable {
		enum State: Equatable { case waiting, sending(Double), done, failed(String) }
		let id = UUID()
		let url: URL
		let isFolder: Bool
		let size: Int64
		var state: State = .waiting
	}

	struct Failure: LocalizedError {
		let message: String
		var errorDescription: String? { message }
	}

	@Published private(set) var link: Link = .none
	@Published private(set) var phase: Phase = .idle
	@Published private(set) var items: [Item] = []
	@Published private(set) var progress = 0.0
	@Published private(set) var speedText: String?
	@Published private(set) var targetName = ""
	@Published private(set) var cameraName: String?

	private static let downloads = "/sdcard/Download/"
	private var poll: Task<Void, Never>?
	private var job: Task<Void, Never>?
	private var pushProcess: Process?
	private var canceled = false
	private var modelNames: [String: String] = [:]
	private var port: IONotificationPortRef?
	private var iterators: [io_iterator_t] = []
	private lazy var photos = PhotoBridge { [weak self] name in self?.cameraName = name }

	// MARK: Watching the cable

	/// Starts watching for a phone (USB plug/unplug events plus a light adb poll). Call when the page appears.
	func start() {
		guard poll == nil else { return }
		watchUSB()
		photos.start()
		poll = Task {
			while !Task.isCancelled {
				if phase != .sending { await refresh() }
				try? await Task.sleep(nanoseconds: 2_000_000_000)
			}
		}
	}

	func stop() {
		poll?.cancel()
		poll = nil
	}

	func refresh() async {
		guard ADB.path != nil else { link = .noAdb; return }
		let devices = await ADB.devices()
		if let device = devices.first(where: { $0.state == "device" }) {
			if modelNames[device.serial] == nil {
				let result = await ADB.run(["-s", device.serial, "shell", "getprop", "ro.product.model"], timeout: 8)
				if result.status == 0, !result.output.isEmpty { modelNames[device.serial] = result.output }
			}
			link = .ready(serial: device.serial, name: modelNames[device.serial] ?? Self.usbPhoneName() ?? NSLocalizedString("CablePhone", value: "Phone", comment: ""))
		} else if devices.contains(where: { $0.state == "unauthorized" }) {
			link = .unauthorized
		} else if devices.contains(where: { $0.state == "offline" }) {
			link = .offline
		} else if let usb = Self.usbPhoneName() {
			link = .noDebugging(usb)
		} else {
			link = .none
		}
	}

	/// Re-checks right when a USB device is plugged in or removed.
	private func watchUSB() {
		guard port == nil else { return }
		port = IONotificationPortCreate(kIOMainPortDefault)
		guard let port else { return }
		IONotificationPortSetDispatchQueue(port, .main)
		let callback: IOServiceMatchingCallback = { context, iterator in
			while case let service = IOIteratorNext(iterator), service != 0 { IOObjectRelease(service) }
			let model = Unmanaged<CableModel>.fromOpaque(context!).takeUnretainedValue()
			Task { @MainActor in await model.refresh() }
		}
		let context = Unmanaged.passUnretained(self).toOpaque()
		for notification in [kIOFirstMatchNotification, kIOTerminatedNotification] {
			var iterator: io_iterator_t = 0
			if IOServiceAddMatchingNotification(port, notification, IOServiceMatching("IOUSBHostDevice"), callback, context, &iterator) == KERN_SUCCESS {
				while case let service = IOIteratorNext(iterator), service != 0 { IOObjectRelease(service) }
				iterators.append(iterator)
			}
		}
	}

	/// Name of a USB device from a common Android maker (Google, Samsung, Xiaomi, OnePlus, Huawei, Motorola, Sony, LG, HTC, Oppo, Nothing).
	private static func usbPhoneName() -> String? {
		let vendors: Set<Int> = [0x18d1, 0x04e8, 0x2717, 0x2a70, 0x12d1, 0x22b8, 0x054c, 0x1004, 0x0bb4, 0x22d9, 0x2b0e]
		var iterator: io_iterator_t = 0
		guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"), &iterator) == KERN_SUCCESS else { return nil }
		defer { IOObjectRelease(iterator) }
		while case let service = IOIteratorNext(iterator), service != 0 {
			defer { IOObjectRelease(service) }
			guard let vendor = IORegistryEntryCreateCFProperty(service, "idVendor" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int,
				  vendors.contains(vendor) else { continue }
			return (IORegistryEntryCreateCFProperty(service, "USB Product Name" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String)
				?? NSLocalizedString("CablePhone", value: "Phone", comment: "")
		}
		return nil
	}

	// MARK: Sending (adb)

	func send(_ urls: [URL]) {
		guard case let .ready(serial, name) = link, phase != .sending, !urls.isEmpty else { return }
		begin(urls, target: name)
		job = Task { await runJob(serial: serial) }
	}

	func cancel() {
		canceled = true
		job?.cancel()
		pushProcess?.terminate()
		photos.cancel()
	}

	func reset() {
		items = []
		phase = .idle
		progress = 0
		speedText = nil
		canceled = false
	}

	private func begin(_ urls: [URL], target: String) {
		items = urls.map { Item(url: $0, isFolder: Self.isDirectory($0), size: Self.size(of: $0)) }
		targetName = target
		progress = 0
		speedText = nil
		canceled = false
		phase = .sending
	}

	private func runJob(serial: String) async {
		let start = Date()
		let total = max(1, items.reduce(0) { $0 + $1.size })
		var finishedBytes: Int64 = 0
		for index in items.indices {
			if canceled {
				items[index].state = .failed(NSLocalizedString("TransferCanceled", value: "Canceled", comment: ""))
				continue
			}
			items[index].state = .sending(0)
			do {
				try await push(index: index, serial: serial) { sent in
					self.report(finishedBytes + sent, of: total, since: start)
				}
				items[index].state = .done
			} catch {
				items[index].state = .failed(error.localizedDescription)
			}
			finishedBytes += items[index].size
			report(finishedBytes, of: total, since: start)
		}
		speedText = nil
		phase = .finished
		finishChime()
	}

	private func finishChime() {
		let sent = items.filter { $0.state == .done }.map(\.url)
		if sent.isEmpty {
			if !canceled { Chime.failure() }
		} else {
			Chime.success()
			HistoryStore.shared.record(.sent, method: .cable, device: targetName, files: sent)
		}
	}

	private final class Box { var done = false; var result: (status: Int32, output: String) = (-1, "") }

	/// Push one file or folder, watching the file grow on the phone for progress, then verify it.
	private func push(index: Int, serial: String, progress report: @escaping (Int64) -> Void) async throws {
		let item = items[index]
		let name = await uniqueName(item.url.lastPathComponent, serial: serial)
		let remote = Self.downloads + name
		let box = Box()
		let task = Task { @MainActor in
			box.result = await ADB.run(["-s", serial, "push", item.url.path, item.isFolder ? Self.downloads : remote], timeout: nil) { self.pushProcess = $0 }
			box.done = true
		}
		var lastSize: Int64 = 0
		var lastChange = Date()
		while !box.done {
			try? await Task.sleep(nanoseconds: 600_000_000)
			if box.done { break }
			if !item.isFolder, let size = await remoteSize(remote, serial: serial), size != lastSize {
				lastSize = size
				lastChange = Date()
				items[index].state = .sending(Double(size) / Double(max(1, item.size)))
				report(size)
			}
			// A transfer that makes no progress for 90 s is stuck (phone locked, cable loose): stop it.
			if Date().timeIntervalSince(lastChange) > 90 { pushProcess?.terminate() }
		}
		await task.value
		pushProcess = nil
		if canceled || Task.isCancelled {
			await remove(remote, serial: serial)
			throw Failure(message: NSLocalizedString("TransferCanceled", value: "Canceled", comment: ""))
		}
		guard box.result.status == 0 else {
			await remove(remote, serial: serial)
			throw Failure(message: Self.explain(box.result.output))
		}
		// Verify: the file on the phone must be exactly as big as the original.
		if item.isFolder {
			let check = await ADB.run(["-s", serial, "shell", "test -d \(ADB.quote(remote)) && echo yes"], timeout: 10)
			guard check.output.contains("yes") else { throw Failure(message: NSLocalizedString("VerifyFailed", value: "Couldn’t confirm the copy on the phone", comment: "")) }
		} else {
			guard await remoteSize(remote, serial: serial) == item.size else {
				await remove(remote, serial: serial)
				throw Failure(message: NSLocalizedString("SizeMismatch", value: "The copy on the phone is incomplete", comment: ""))
			}
			// Ask the phone to index it so it shows up in Files and Downloads (best effort).
			_ = await ADB.run(["-s", serial, "shell", "am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d \(ADB.quote(URL(fileURLWithPath: remote).absoluteString))"], timeout: 10)
		}
	}

	private func uniqueName(_ name: String, serial: String) async -> String {
		let base = (name as NSString).deletingPathExtension
		let ext = (name as NSString).pathExtension
		var candidate = name
		var counter = 1
		while counter < 100, await ADB.run(["-s", serial, "shell", "test -e \(ADB.quote(Self.downloads + candidate)) && echo yes"], timeout: 10).output.contains("yes") {
			candidate = ext.isEmpty ? "\(base) (\(counter))" : "\(base) (\(counter)).\(ext)"
			counter += 1
		}
		return candidate
	}

	private func remoteSize(_ path: String, serial: String) async -> Int64? {
		let result = await ADB.run(["-s", serial, "shell", "stat -c %s \(ADB.quote(path))"], timeout: 10)
		return result.status == 0 ? Int64(result.output) : nil
	}

	private func remove(_ path: String, serial: String) async {
		_ = await ADB.run(["-s", serial, "shell", "rm -rf \(ADB.quote(path))"], timeout: 10)
	}

	private func report(_ sent: Int64, of total: Int64, since start: Date) {
		progress = min(1, Double(sent) / Double(total))
		let elapsed = Date().timeIntervalSince(start)
		guard elapsed > 1.5, sent > 0 else { return }
		let speed = Double(sent) / elapsed
		let remaining = Int(Double(total - sent) / speed)
		let rate = ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .file) + "/s"
		speedText = remaining < 5 ? rate : remaining < 60
			? "\(rate) · " + String(format: NSLocalizedString("EtaSeconds", value: "%d sec left", comment: ""), (remaining + 2) / 5 * 5)
			: "\(rate) · " + String(format: NSLocalizedString("EtaMinutes", value: "%d min left", comment: ""), (remaining + 30) / 60)
	}

	/// adb's messages are terse; say what to do.
	private static func explain(_ output: String) -> String {
		let text = output.lowercased()
		if text.contains("no space") { return NSLocalizedString("PhoneFull", value: "Not enough space on the phone", comment: "") }
		if text.contains("unauthorized") { return NSLocalizedString("AllowDebugging", value: "Allow USB debugging on the phone", comment: "") }
		if text.contains("no devices") || text.contains("not found") || text.contains("offline") || text.contains("closed") {
			return NSLocalizedString("PhoneGone", value: "The phone disconnected", comment: "")
		}
		return output.split(separator: "\n").last.map(String.init) ?? NSLocalizedString("TransferFailed", value: "Failed", comment: "")
	}

	// MARK: Sending (Image Capture, photos and videos)

	func sendPhotos(_ urls: [URL]) {
		guard let camera = cameraName, phase != .sending, !urls.isEmpty else { return }
		begin(urls, target: camera)
		job = Task {
			for index in items.indices {
				if canceled { items[index].state = .failed(NSLocalizedString("TransferCanceled", value: "Canceled", comment: "")); continue }
				let type = UTType(filenameExtension: items[index].url.pathExtension)
				guard let type, type.conforms(to: .image) || type.conforms(to: .movie) else {
					items[index].state = .failed(NSLocalizedString("PhotosOnly", value: "Photos and videos only", comment: ""))
					continue
				}
				items[index].state = .sending(0)
				items[index].state = await photos.upload(items[index].url) ? .done : .failed(NSLocalizedString("TransferFailed", value: "Failed", comment: ""))
				progress = Double(index + 1) / Double(items.count)
			}
			phase = .finished
			finishChime()
		}
	}

	// MARK: Helpers

	private static func isDirectory(_ url: URL) -> Bool {
		(try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
	}

	private static func size(of url: URL) -> Int64 {
		guard isDirectory(url) else { return Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
		let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])?.compactMap { ($0 as? URL)?.fileSizeValue } ?? []
		return Int64(files.reduce(0, +))
	}
}

private extension URL {
	var fileSizeValue: Int? { try? resourceValues(forKeys: [.fileSizeKey]).fileSize }
}

// MARK: - Image Capture (phone in "Photo transfer" mode)

/// Finds a phone that shows up as a camera and uploads photos and videos to it.
final class PhotoBridge: NSObject, ICDeviceBrowserDelegate, ICCameraDeviceDelegate {
	private let browser = ICDeviceBrowser()
	private var camera: ICCameraDevice?
	private let onChange: (String?) -> Void

	init(onChange: @escaping (String?) -> Void) {
		self.onChange = onChange
		super.init()
	}

	func start() {
		browser.delegate = self
		browser.browsedDeviceTypeMask = ICDeviceTypeMask(rawValue: ICDeviceTypeMask.camera.rawValue | ICDeviceLocationTypeMask.local.rawValue) ?? .camera
		browser.start()
	}

	func cancel() {}

	private var pending: [String: CheckedContinuation<Bool, Never>] = [:]

	func upload(_ url: URL) async -> Bool {
		guard let camera else { return false }
		return await withCheckedContinuation { continuation in
			pending[url.path] = continuation
			camera.requestUploadFile(url, options: [:], uploadDelegate: self, didUploadSelector: #selector(didUploadFile(_:error:contextInfo:)), contextInfo: nil)
		}
	}

	@objc(didUploadFile:error:contextInfo:)
	func didUploadFile(_ url: URL, error: NSError?, contextInfo: UnsafeMutableRawPointer?) {
		pending.removeValue(forKey: url.path)?.resume(returning: error == nil)
	}

	// MARK: ICDeviceBrowserDelegate

	func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
		guard let camera = device as? ICCameraDevice else { return }
		self.camera = camera
		camera.delegate = self
		camera.requestOpenSession()
		DispatchQueue.main.async { self.onChange(camera.name) }
	}

	func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
		guard device == camera else { return }
		camera = nil
		DispatchQueue.main.async { self.onChange(nil) }
	}

	// MARK: ICCameraDeviceDelegate (nothing to do; we only upload)

	func didRemove(_ device: ICDevice) {}
	func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {}
	func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {}
	func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {}
	func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) {}
	func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {}
	func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {}
	func cameraDevice(_ camera: ICCameraDevice, didReceiveThumbnail thumbnail: CGImage?, for item: ICCameraItem, error: Error?) {}
	func cameraDevice(_ camera: ICCameraDevice, didReceiveMetadata metadata: [AnyHashable: Any]?, for item: ICCameraItem, error: Error?) {}
	func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) {}
	func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {}
	func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {}
	func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {}
}
