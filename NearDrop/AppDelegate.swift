//
//  AppDelegate.swift
//  NearDrop
//
//  Created by Grishka on 08.04.2023.
//

import Cocoa
import Combine
import Carbon.HIToolbox
import UserNotifications
import NearbyShare

@main
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, MainAppDelegate{
	private var statusItem:NSStatusItem?
	private var activeIncomingTransfers:[String:TransferInfo]=[:]
	private lazy var mainWindow=MainWindowController()
	private var pendingOpenURLs:[URL]=[]
	private var didFinishLaunching=false
	private var hotKey:EventHotKeyRef?
	private var badgeWatcher:AnyCancellable?

	func applicationWillFinishLaunching(_ notification: Notification) {
		NSWindow.allowsAutomaticWindowTabbing=false // one window: no "Show Tab Bar" items in the View menu
		NSApp.mainMenu=AppMenu.build(target: self)
		AppearanceMode.current.apply()
		// Must be read here: by didFinishLaunching the launch Apple event is gone.
		launchedAsLoginItem=Self.isLaunchedAsLoginItem()
	}
	private var launchedAsLoginItem=false

    func applicationDidFinishLaunching(_ aNotification: Notification) {
		let menu=NSMenu()
		let openItem=NSMenuItem(title: NSLocalizedString("OpenNearDrop", value: "Open Blippy…", comment: ""), action: #selector(openMainWindow(_:)), keyEquivalent: "o")
		openItem.target=self
		menu.addItem(openItem)
		let downloadsItem=NSMenuItem(title: NSLocalizedString("ShowDownloads", value: "Show Received Files", comment: ""), action: #selector(showDownloads(_:)), keyEquivalent: "")
		downloadsItem.target=self
		menu.addItem(downloadsItem)
		menu.addItem(NSMenuItem.separator())
		menu.addItem(withTitle: NSLocalizedString("VisibleToEveryone", value: "Visible to everyone", comment: ""), action: nil, keyEquivalent: "")
		menu.addItem(withTitle: String(format: NSLocalizedString("DeviceName", value: "Device name: %@", comment: ""), arguments: [Host.current().localizedName!]), action: nil, keyEquivalent: "")
		menu.addItem(NSMenuItem.separator())
		menu.addItem(withTitle: NSLocalizedString("Quit", value: "Quit Blippy", comment: ""), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
		statusItem=NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
		statusItem?.button?.image=NSImage(named: "MenuBarIcon")
		statusItem?.menu=menu
		statusItem?.behavior = .removalAllowed
		if let button=statusItem?.button{
			let drop=StatusDropView(frame: button.bounds)
			drop.autoresizingMask=[.width, .height]
			drop.onDrop={ [weak self] urls in self?.mainWindow.show(files: urls) }
			button.addSubview(drop)
		}
		registerHotKey()
		registerShareExtension()
		// Dock badge: how many incoming transfers are waiting for an answer.
		badgeWatcher=ReceivedStore.shared.$items.sink { items in
			let waiting=items.filter { $0.state == .waiting }.count
			NSApp.dockTile.badgeLabel=waiting>0 ? "\(waiting)" : nil
		}
		ReceivedStore.shared.respond={ [weak self] id, accept in self?.respond(to: id, accept: accept) }
		
		let nc=UNUserNotificationCenter.current()
		nc.requestAuthorization(options: [.alert, .sound]) { granted, err in
			if !granted{
				DispatchQueue.main.async {
					self.showNotificationsDeniedAlert()
				}
			}
		}
		nc.delegate=self
		let incomingTransfersCategory=UNNotificationCategory(identifier: "INCOMING_TRANSFERS", actions: [
			UNNotificationAction(identifier: "ACCEPT", title: NSLocalizedString("Accept", comment: ""), options: UNNotificationActionOptions.authenticationRequired),
			UNNotificationAction(identifier: "DECLINE", title: NSLocalizedString("Decline", comment: ""))
		], intentIdentifiers: [])
		let errorsCategory=UNNotificationCategory(identifier: "ERRORS", actions: [], intentIdentifiers: [])
		nc.setNotificationCategories([incomingTransfersCategory, errorsCategory])
		NearbyConnectionManager.shared.mainAppDelegate=self
		NearbyConnectionManager.shared.becomeVisible()

		didFinishLaunching=true
		// Open the window when the user launches NearDrop (not when it starts at login),
		// or when files were dropped onto the app to launch it.
		if !pendingOpenURLs.isEmpty || !launchedAsLoginItem{
			mainWindow.show(files: pendingOpenURLs)
			pendingOpenURLs=[]
		}
	}

	func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
		return false // keep receiving from the menu bar
	}

	func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
		// Clicking NearDrop again (Finder sidebar, Applications, Spotlight) brings up the window.
		statusItem?.isVisible=true
		mainWindow.show()
		return true
	}

	/// Files dropped onto NearDrop (e.g. its Finder sidebar item) or opened with it.
	func application(_ application: NSApplication, open urls: [URL]) {
		let files=urls.filter { $0.isFileURL }
		guard !files.isEmpty else {return}
		if didFinishLaunching{
			mainWindow.show(files: files)
		}else{
			pendingOpenURLs.append(contentsOf: files)
		}
	}

	@objc func openMainWindow(_ sender: Any?){
		mainWindow.show()
	}
	
	@objc func showDownloads(_ sender: Any?){
		SendSession.openDownloads()
	}
	
	// MARK: - Menu bar actions
	
	@objc func goToPage(_ sender: NSMenuItem){
		mainWindow.show(page: AppMenu.page(forTag: sender.tag))
	}
	
	@objc func sendFiles(_ sender: Any?){
		mainWindow.chooseFiles()
	}
	
	@objc func showAbout(_ sender: Any?){
		let paragraph=NSMutableParagraphStyle()
		paragraph.alignment = .center
		let base:[NSAttributedString.Key:Any]=[.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: paragraph]
		let credits=NSMutableAttributedString(string: NSLocalizedString("AboutCredits", value: "Send files between your Mac and Android phone over Wi-Fi or a USB cable.\nNo accounts, no tracking, no data collected.\n\nOpen source under the Apache License 2.0.\nBuilt on NearDrop by Grishka. Cable transfer uses adb from the Android SDK.", comment: ""), attributes: base)
		func link(_ title:String, _ url:URL?){
			guard let url else {return}
			var attrs=base
			attrs[.link]=url
			credits.append(NSAttributedString(string: "\n"+title, attributes: attrs))
		}
		credits.append(NSAttributedString(string: "\n", attributes: base))
		link(NSLocalizedString("AboutGitHub", value: "Source code on GitHub", comment: ""), AppInfo.repoURL)
		link(NSLocalizedString("AboutCoffee", value: "Buy me a coffee", comment: ""), AppInfo.coffeeURL)
		NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Blippy", .credits: credits])
		NSApp.activate(ignoringOtherApps: true)
	}
	
	@objc func openHelp(_ sender: Any?){
		if let repo=AppInfo.repoURL{
			NSWorkspace.shared.open(repo)
			return
		}
		let alert=NSAlert()
		alert.messageText=NSLocalizedString("HelpTitle", value: "Getting started", comment: "")
		alert.informativeText=NSLocalizedString("HelpBody", value: "Send: pick files, then click a nearby phone. On the phone, open Quick Share and tap Receive.\n\nReceive: share from your phone with Quick Share and choose this Mac.\n\nCable: connect a USB cable and turn on USB debugging; Blippy copies files to Downloads on the phone.", comment: "")
		alert.runModal()
	}
	
	@objc func showPrivacy(_ sender: Any?){
		let alert=NSAlert()
		alert.messageText=NSLocalizedString("MenuPrivacy", value: "Privacy Statement", comment: "")
		alert.informativeText=AppInfo.privacyStatement
		alert.runModal()
	}
	
	@objc func showLicenses(_ sender: Any?){
		if let url=Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "txt"){
			NSWorkspace.shared.open(url)
		}
	}
	
	@objc func openIssues(_ sender: Any?){
		if let url=AppInfo.issuesURL{ NSWorkspace.shared.open(url) }
	}
	
	@objc func openCoffee(_ sender: Any?){
		if let url=AppInfo.coffeeURL{ NSWorkspace.shared.open(url) }
	}
	
	/// Makes sure the Share menu entry shows up after a plain drag-to-Applications install:
	/// register the extension with the system, and turn it on the first time only (so a user who switches it off stays switched off).
	private func registerShareExtension(){
		guard let appex=Bundle.main.builtInPlugInsURL?.appendingPathComponent("ShareExtension.appex"), let id=Bundle(url: appex)?.bundleIdentifier else {return}
		let firstRun = !UserDefaults.standard.bool(forKey: "Blippy.shareExtensionEnabled")
		UserDefaults.standard.set(true, forKey: "Blippy.shareExtensionEnabled")
		DispatchQueue.global(qos: .utility).async {
			func pluginkit(_ args:[String]){
				let process=Process()
				process.executableURL=URL(fileURLWithPath: "/usr/bin/pluginkit")
				process.arguments=args
				process.standardOutput=FileHandle.nullDevice
				process.standardError=FileHandle.nullDevice
				try? process.run()
				process.waitUntilExit()
			}
			pluginkit(["-a", appex.path])
			if firstRun{ pluginkit(["-e", "use", "-i", id]) }
		}
	}

	/// Global shortcut ⌃⌥N: open NearDrop on the current Space.
	private func registerHotKey(){
		var spec=EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
		InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
			let me=Unmanaged<AppDelegate>.fromOpaque(context!).takeUnretainedValue()
			DispatchQueue.main.async { me.mainWindow.show() }
			return noErr
		}, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
		RegisterEventHotKey(UInt32(kVK_ANSI_N), UInt32(controlKey|optionKey), EventHotKeyID(signature: OSType(0x4E445250), id: 1), GetApplicationEventTarget(), 0, &hotKey)
	}

	private static func isLaunchedAsLoginItem() -> Bool{
		guard let event=NSAppleEventManager.shared().currentAppleEvent,
			  event.eventID==AEEventID(kAEOpenApplication),
			  let prop=event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData)) else {return false}
		return prop.enumCodeValue==OSType(keyAELaunchedAsLogInItem)
	}

    func applicationWillTerminate(_ aNotification: Notification) {
		UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
	
	func showNotificationsDeniedAlert(){
		let alert=NSAlert()
		alert.alertStyle = .critical
		alert.messageText=NSLocalizedString("NotificationsDenied.Title", value: "Notification Permission Required", comment: "")
		alert.informativeText=NSLocalizedString("NotificationsDenied.Message", value: "Blippy needs to be able to display notifications for incoming file transfers. Please allow notifications in System Settings.", comment: "")
		alert.addButton(withTitle: NSLocalizedString("NotificationsDenied.OpenSettings", value: "Open settings", comment: ""))
		alert.addButton(withTitle: NSLocalizedString("Quit", value: "Quit Blippy", comment: ""))
		let result=alert.runModal()
		if result==NSApplication.ModalResponse.alertFirstButtonReturn{
			NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
		}else if result==NSApplication.ModalResponse.alertSecondButtonReturn{
			NSApplication.shared.terminate(nil)
		}
	}
	
	func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
		let transferID=response.notification.request.content.userInfo["transferID"]! as! String
		respond(to: transferID, accept: response.actionIdentifier=="ACCEPT")
		completionHandler()
	}
	
	/// Accept or decline an incoming transfer (from the notification or the Received page).
	private func respond(to transferID:String, accept:Bool){
		NearbyConnectionManager.shared.submitUserConsent(transferID: transferID, accept: accept)
		UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["transfer_"+transferID])
		ReceivedStore.shared.set(transferID, accept ? .receiving : .declined)
		if !accept{
			activeIncomingTransfers.removeValue(forKey: transferID)
		}
	}
	
	func obtainUserConsent(for transfer: TransferMetadata, from device: RemoteDeviceInfo) {
		let fileStr:String
		if let textTitle=transfer.textDescription{
			fileStr=textTitle
		}else if transfer.files.count==1{
			fileStr=transfer.files[0].name
		}else{
			fileStr=String.localizedStringWithFormat(NSLocalizedString("NFiles", value: "%d files", comment: ""), transfer.files.count)
		}
		let notificationContent=UNMutableNotificationContent()
		notificationContent.title="Blippy"
		notificationContent.subtitle=String(format:NSLocalizedString("PinCode", value: "PIN: %@", comment: ""), arguments: [transfer.pinCode!])
		notificationContent.body=String(format: NSLocalizedString("DeviceSendingFiles", value: "%1$@ is sending you %2$@", comment: ""), arguments: [device.name, fileStr])
		notificationContent.sound = .default
		notificationContent.categoryIdentifier="INCOMING_TRANSFERS"
		notificationContent.userInfo=["transferID": transfer.id]
		if #available(macOS 11.0, *){
			NDNotificationCenterHackery.removeDefaultAction(notificationContent)
		}
		let notificationReq=UNNotificationRequest(identifier: "transfer_"+transfer.id, content: notificationContent, trigger: nil)
		UNUserNotificationCenter.current().add(notificationReq)
		self.activeIncomingTransfers[transfer.id]=TransferInfo(device: device, transfer: transfer)
		ReceivedStore.shared.add(.init(id: transfer.id, device: device.name, title: fileStr, date: Date(), state: .waiting))
		if !NSApp.isActive{
			NSApp.requestUserAttention(.informationalRequest)
		}
	}
	
	func incomingTransfer(id: String, progress: Double) {
		ReceivedStore.shared.setProgress(id, progress)
	}
	
	func incomingTransfer(id: String, didFinishWith error: Error?, files: [URL]) {
		if let item=ReceivedStore.shared.finish(id, error: error, files: files){
			if item.state == .done{
				Chime.success()
				HistoryStore.shared.record(.received, method: .wifi, device: item.device, files: item.urls)
				if !NSApp.isActive{
					let content=UNMutableNotificationContent()
					content.title=NSLocalizedString("Received", value: "Received", comment: "")
					content.body=String(format: NSLocalizedString("ReceivedBody", value: "%1$@ from %2$@", comment: ""), item.title, item.device)
					UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "received_"+id, content: content, trigger: nil))
				}
			}else{
				Chime.failure()
			}
		}
		guard let transfer=self.activeIncomingTransfers[id] else {return}
		if let error=error{
			let notificationContent=UNMutableNotificationContent()
			notificationContent.title=String(format: NSLocalizedString("TransferError", value: "Failed to receive files from %@", comment: ""), arguments: [transfer.device.name])
			if let ne=(error as? NearbyError){
				switch ne{
				case .inputOutput:
					notificationContent.body="I/O Error";
				case .protocolError(_):
					notificationContent.body=NSLocalizedString("Error.Protocol", value: "Communication error", comment: "")
				case .requiredFieldMissing:
					notificationContent.body=NSLocalizedString("Error.Protocol", value: "Communication error", comment: "")
				case .ukey2:
					notificationContent.body=NSLocalizedString("Error.Crypto", value: "Encryption error", comment: "")
				case .canceled(reason: _):
					break; // can't happen for incoming transfers
				}
			}else{
				notificationContent.body=error.localizedDescription
			}
			notificationContent.categoryIdentifier="ERRORS"
			UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "transferError_"+id, content: notificationContent, trigger: nil))
		}
		UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["transfer_"+id])
		self.activeIncomingTransfers.removeValue(forKey: id)
	}
}

struct TransferInfo{
	let device:RemoteDeviceInfo
	let transfer:TransferMetadata
}

/// Lets files be dropped on the menu-bar icon; plain clicks still reach the status button.
final class StatusDropView: NSView{
	var onDrop:(([URL])->Void)?
	
	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		registerForDraggedTypes([.fileURL])
	}
	
	required init?(coder: NSCoder) {
		fatalError("init(coder:) is not supported")
	}
	
	override func mouseDown(with event: NSEvent) { superview?.mouseDown(with: event) }
	override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
	
	override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
		guard let urls=sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty else {return false}
		onDrop?(urls)
		return true
	}
}
