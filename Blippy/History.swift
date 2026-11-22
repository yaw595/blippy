// SPDX-License-Identifier: Apache-2.0
//
//  History.swift
//  Blippy
//
//  History (what was sent and received, kept on disk) and Devices (who you've exchanged files with,
//  and who is reachable right now).
//

import SwiftUI
import AppKit
import NearbyShare

// MARK: - Store

struct HistoryEntry: Codable, Identifiable {
	enum Direction: String, Codable { case sent, received }
	enum Method: String, Codable { case wifi, cable }

	let id: UUID
	let direction: Direction
	let method: Method
	let device: String
	let title: String
	let date: Date
	let paths: [String]
	let size: Int64

	var urls: [URL] { paths.map { URL(fileURLWithPath: $0) } }
	var existingURLs: [URL] { urls.filter { FileManager.default.fileExists(atPath: $0.path) } }
}

final class HistoryStore: ObservableObject {
	static let shared = HistoryStore()

	@Published private(set) var entries: [HistoryEntry] = []
	private let file: URL

	private init() {
		let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Blippy", isDirectory: true)
		try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		file = dir.appendingPathComponent("history.json")
		if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
			entries = saved
		}
	}

	func record(_ direction: HistoryEntry.Direction, method: HistoryEntry.Method, device: String, files: [URL]) {
		guard !files.isEmpty else { return }
		let size = files.reduce(Int64(0)) { $0 + Self.size(of: $1) }
		let title = files.count == 1 ? files[0].lastPathComponent
			: String.localizedStringWithFormat(NSLocalizedString("NFiles", value: "%d files", comment: ""), files.count)
		entries.insert(HistoryEntry(id: UUID(), direction: direction, method: method, device: device, title: title,
									date: Date(), paths: files.map(\.path), size: size), at: 0)
		if entries.count > 500 { entries.removeLast(entries.count - 500) }
		save()
	}

	/// Takes the entry off the list. The files are left alone.
	func remove(_ id: UUID) {
		entries.removeAll { $0.id == id }
		save()
	}

	/// Deletes the files from disk for good (no Trash), then removes the entry.
	func deleteFiles(_ entry: HistoryEntry) {
		for url in entry.existingURLs { try? FileManager.default.removeItem(at: url) }
		remove(entry.id)
	}

	private func save() {
		let snapshot = entries
		DispatchQueue.global(qos: .utility).async {
			if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: self.file, options: .atomic) }
		}
	}

	private static func size(of url: URL) -> Int64 {
		let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
		if values?.isDirectory == true {
			let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])?.compactMap { ($0 as? URL).flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize } } ?? []
			return Int64(files.reduce(0, +))
		}
		return Int64(values?.fileSize ?? 0)
	}
}

// MARK: - History page

struct HistoryPage: View {
	@ObservedObject var store: HistoryStore
	@State private var pending: HistoryEntry?

	var body: some View {
		Group {
			if store.entries.isEmpty {
				VStack(spacing: 6) {
					Image(systemName: "clock").font(.system(size: 34, weight: .light)).foregroundStyle(.secondary).padding(.bottom, 10)
					Text(NSLocalizedString("NoHistory", value: "No history yet", comment: "")).font(.system(size: 15, weight: .semibold))
					Text(NSLocalizedString("NoHistoryHint", value: "Files you send and receive show up here.", comment: ""))
						.font(.system(size: 12)).foregroundStyle(.secondary)
				}
				.frame(maxWidth: .infinity, maxHeight: .infinity)
			} else {
				ScrollView {
					LazyVStack(spacing: 10) {
						ForEach(store.entries) { entry in
							HistoryRow(entry: entry) { pending = entry }
						}
					}
					.padding(20)
				}
			}
		}
		.background(Color(nsColor: .windowBackgroundColor))
		.confirmationDialog(
			NSLocalizedString("RemoveTitle", value: "Remove from history?", comment: ""),
			isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
			presenting: pending
		) { entry in
			Button(NSLocalizedString("RemoveFromHistory", value: "Remove from History", comment: "")) { store.remove(entry.id) }
			// Only files received on this Mac can be deleted here. Sent files are the originals; they're never touched.
			if entry.direction == .received && !entry.existingURLs.isEmpty {
				Button(NSLocalizedString("DeletePermanently", value: "Delete File Permanently", comment: ""), role: .destructive) { store.deleteFiles(entry) }
			}
		} message: { entry in
			Text(entry.direction == .received && !entry.existingURLs.isEmpty
				 ? NSLocalizedString("RemoveMessageReceived", value: "Delete the file from your Mac for good, or just take it off this list.", comment: "")
				 : NSLocalizedString("RemoveMessageSent", value: "The files themselves aren’t affected.", comment: ""))
		}
	}
}

private struct HistoryRow: View {
	let entry: HistoryEntry
	let onRemove: () -> Void

	var body: some View {
		HStack(spacing: 12) {
			FileThumb(url: entry.urls.first, size: 38)
			VStack(alignment: .leading, spacing: 3) {
				Text(entry.title).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.middle)
				Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
			}
			Spacer(minLength: 8)
			if !entry.existingURLs.isEmpty {
				Button(NSLocalizedString("ShowInFinder", value: "Show", comment: "")) { NSWorkspace.shared.activateFileViewerSelecting(entry.existingURLs) }
					.buttonStyle(GlassButtonStyle())
			}
			Button(action: onRemove) { Image(systemName: "trash") }
				.buttonStyle(GlassButtonStyle())
				.accessibilityLabel(NSLocalizedString("RemoveFromHistory", value: "Remove from History", comment: ""))
		}
		.padding(12)
		.card()
	}

	private var subtitle: String {
		let who = String(format: entry.direction == .sent
						 ? NSLocalizedString("HistorySentTo", value: "Sent to %@", comment: "")
						 : NSLocalizedString("HistoryReceivedFrom", value: "Received from %@", comment: ""), entry.device)
		let how = entry.method == .cable ? NSLocalizedString("MethodCable", value: "Cable", comment: "") : NSLocalizedString("MethodWifi", value: "Wi-Fi", comment: "")
		return [who, how, ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file), entry.date.formatted(.relative(presentation: .named))]
			.joined(separator: " · ")
	}
}

// MARK: - Devices

/// Phones reachable over Wi-Fi right now (only while the Devices page is open).
private final class NearbyWatcher: NSObject, ObservableObject, ShareExtensionDelegate {
	@Published private(set) var names: Set<String> = []
	private var byID: [String: String] = [:]
	private var running = false

	func start() {
		guard !running else { return }
		running = true
		NearbyConnectionManager.shared.startDeviceDiscovery()
		NearbyConnectionManager.shared.addShareExtensionDelegate(self)
	}

	func stop() {
		guard running else { return }
		running = false
		NearbyConnectionManager.shared.removeShareExtensionDelegate(self)
		NearbyConnectionManager.shared.stopDeviceDiscovery()
		byID = [:]
		names = []
	}

	func addDevice(device: RemoteDeviceInfo) {
		DispatchQueue.main.async { self.byID[device.id ?? device.name] = device.name; self.names = Set(self.byID.values) }
	}

	func removeDevice(id: String) {
		DispatchQueue.main.async { self.byID[id] = nil; self.names = Set(self.byID.values) }
	}

	func startTransferWithQrCode(device: RemoteDeviceInfo) {}
	func connectionWasEstablished(pinCode: String) {}
	func connectionFailed(with error: Error) {}
	func transferAccepted() {}
	func transferProgress(progress: Double) {}
	func transferFinished() {}
}

struct DevicesPage: View {
	@ObservedObject var history: HistoryStore
	@ObservedObject private var cable = CableModel.shared
	@StateObject private var nearby = NearbyWatcher()
	let openSend: () -> Void
	let openCable: () -> Void

	private struct Known: Identifiable {
		let name: String
		var onWifi = false
		var onCable = false
		var sent = 0
		var received = 0
		var last: Date?
		var id: String { name }
	}

	private var devices: [Known] {
		var byName: [String: Known] = [:]
		for entry in history.entries {
			var known = byName[entry.device] ?? Known(name: entry.device)
			if entry.direction == .sent { known.sent += 1 } else { known.received += 1 }
			known.last = max(known.last ?? .distantPast, entry.date)
			byName[entry.device] = known
		}
		for name in nearby.names { byName[name, default: Known(name: name)].onWifi = true }
		if let name = cable.link.readyName { byName[name, default: Known(name: name)].onCable = true }
		return byName.values.sorted { ($0.onWifi || $0.onCable ? 1 : 0, $0.last ?? .distantPast) > ($1.onWifi || $1.onCable ? 1 : 0, $1.last ?? .distantPast) }
	}

	var body: some View {
		Group {
			if devices.isEmpty {
				VStack(spacing: 6) {
					Image(systemName: Page.devices.symbol).font(.system(size: 34, weight: .light)).foregroundStyle(.secondary).padding(.bottom, 10)
					Text(NSLocalizedString("NoDevices", value: "No devices yet", comment: "")).font(.system(size: 15, weight: .semibold))
					Text(NSLocalizedString("NoDevicesHint", value: "Phones you connect or exchange files with show up here.", comment: ""))
						.font(.system(size: 12)).foregroundStyle(.secondary)
				}
				.frame(maxWidth: .infinity, maxHeight: .infinity)
			} else {
				ScrollView {
					LazyVStack(spacing: 10) {
						ForEach(devices) { device in
							DeviceRow(device: device, send: device.onCable ? openCable : openSend)
						}
					}
					.padding(20)
				}
			}
		}
		.background(Color(nsColor: .windowBackgroundColor))
		.onAppear { nearby.start(); cable.start() }
		.onDisappear { nearby.stop(); cable.stop() }
	}

	private struct DeviceRow: View {
		let device: Known
		let send: () -> Void

		var body: some View {
			HStack(spacing: 14) {
				PhoneIcon(height: 46).frame(width: 40)
				VStack(alignment: .leading, spacing: 4) {
					Text(device.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
					HStack(spacing: 6) {
						Circle().fill(online ? Palette.success : Color.secondary.opacity(0.5)).frame(width: 7, height: 7)
						Text(status).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
					}
					if device.sent + device.received > 0 {
						Text(String(format: NSLocalizedString("DeviceStats", value: "%d sent · %d received", comment: ""), device.sent, device.received))
							.font(.system(size: 11)).foregroundStyle(.tertiary)
					}
				}
				Spacer(minLength: 8)
				if online {
					Button(NSLocalizedString("PageSend", value: "Send", comment: ""), action: send).buttonStyle(GlassButtonStyle(prominent: true))
				}
			}
			.padding(14)
			.card()
		}

		private var online: Bool { device.onWifi || device.onCable }

		private var status: String {
			if device.onCable { return NSLocalizedString("StatusCable", value: "Connected by cable", comment: "") }
			if device.onWifi { return NSLocalizedString("StatusWifi", value: "Nearby on Wi-Fi", comment: "") }
			return device.last.map { String(format: NSLocalizedString("StatusLastSeen", value: "Last used %@", comment: ""), $0.formatted(.relative(presentation: .named))) }
				?? NSLocalizedString("StatusOffline", value: "Not connected", comment: "")
		}
	}
}
