// SPDX-License-Identifier: Apache-2.0
//
//  MainWindow.swift
//  NearDrop
//
//  The app's own window: the same device picker as the Share sheet (ShareRootView),
//  plus drag-and-drop and "Choose Files…". Opened from launch, the menu bar,
//  a click on the app in Finder's sidebar, or files dropped onto the app.
//

import Cocoa
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

final class MainWindowController: NSWindowController, NSWindowDelegate {
	private var session: SendSession?
	private let nav = AppNav()

	init() {
		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 880, height: 580),
			styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
			backing: .buffered,
			defer: false)
		window.title = "Blippy"
		window.isReleasedWhenClosed = false
		window.collectionBehavior = [.moveToActiveSpace, .fullScreenPrimary]
		window.minSize = NSSize(width: 720, height: 500)
		window.setFrameAutosaveName("NearDropAppWindow")
		super.init(window: window)
		window.delegate = self
		if !window.setFrameUsingName("NearDropAppWindow") {
			window.center()
		}
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) is not supported")
	}

	/// Shows the window (creating a fresh send session if needed) and optionally preloads files.
	func show(files: [URL] = []) {
		let session = self.session ?? makeSession()
		if !files.isEmpty {
			nav.page = .send
			session.setFiles(files)
		}
		if let window {
			if window.isMiniaturized {
				window.deminiaturize(nil) // a minimized window ignores makeKeyAndOrderFront
			}
			// To appear on the Space you're in, even another app's full-screen Space, the window must briefly be
			// .fullScreenAuxiliary; once it is there it switches back to .fullScreenPrimary so the green button
			// gives a real full screen. (Not touched while this window is itself full screen.)
			let ownFullScreen = window.styleMask.contains(.fullScreen)
			if !ownFullScreen {
				window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
			}
			showWindow(nil)
			window.makeKeyAndOrderFront(nil)
			if !ownFullScreen {
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
					if !window.styleMask.contains(.fullScreen) {
						window.collectionBehavior = [.moveToActiveSpace, .fullScreenPrimary]
					}
				}
			}
		}
		if #available(macOS 14.0, *) {
			NSApp.activate()
		} else {
			NSApp.activate(ignoringOtherApps: true)
		}
	}

	/// Shows the window on a given page (used by the menu bar).
	func show(page: Page) {
		nav.page = page
		show()
	}

	/// Opens the file picker on the Send page (File → Send Files…).
	func chooseFiles() {
		show(page: .send)
		session?.model.onChooseFiles()
	}

	private func makeSession() -> SendSession {
		let session = SendSession(mode: .window)
		session.onSent = { [weak self, weak session] sent in
			if let files = session?.urls { for transfer in sent { HistoryStore.shared.record(.sent, method: .wifi, device: transfer.device.name, files: files) } }
			self?.notifySent(sent)
		}
		session.chooseFiles = { [weak self] completion in
			self?.presentOpenPanel(completion: completion)
		}
		let hosting = NSHostingView(rootView: AppRoot(model: session.model, nav: nav))
		hosting.sizingOptions = [] // the window decides its size, not the SwiftUI content (otherwise full screen can be capped)
		window?.contentView = hosting
		session.start()
		self.session = session
		return session
	}

	/// A system notification when a send finishes while NearDrop is in the background.
	private func notifySent(_ sent: [ShareModel.Transfer]) {
		guard !(window?.isKeyWindow ?? false) else { return }
		let content = UNMutableNotificationContent()
		content.title = NSLocalizedString("Sent", value: "Sent", comment: "")
		content.body = sent.map { $0.device.name }.joined(separator: ", ")
		UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "sent_" + UUID().uuidString, content: content, trigger: nil))
	}

	private func presentOpenPanel(completion: @escaping ([URL]) -> Void) {
		guard let window else { return }
		let panel = NSOpenPanel()
		panel.canChooseFiles = true
		panel.canChooseDirectories = true
		panel.allowsMultipleSelection = true
		panel.prompt = NSLocalizedString("ChooseFilesPrompt", value: "Choose", comment: "")
		panel.message = NSLocalizedString("ChooseFilesMessage", value: "Choose files to send to a nearby device", comment: "")
		panel.beginSheetModal(for: window) { response in
			if response == .OK {
				completion(panel.urls)
			}
		}
	}

	func windowWillClose(_ notification: Notification) {
		// Closing the window must not cancel a send in progress: leave the session running, hidden.
		guard let session, !session.model.isTransferring || session.model.isFinished else { return }
		session.stop()
		self.session = nil
		window?.contentView = nil
	}
}
