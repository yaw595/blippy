//
//  ShareViewController.swift
//  ShareExtension
//
//  Created by Grishka on 12.09.2023.
//  UI is SwiftUI (ShareView.swift); the send flow lives in SendSession.swift (shared with the app).
//

import Foundation
import Cocoa
import SwiftUI
import UniformTypeIdentifiers
import NearbyShare

class ShareViewController: NSViewController {

	private let session=SendSession(mode: .shareSheet)

	override func loadView() {
		let hostingView=NSHostingView(rootView: ShareRootView(model: session.model))
		let size=ShareRootView.size
		hostingView.frame=NSRect(origin: .zero, size: size)
		self.view=hostingView
		self.preferredContentSize=size

		session.model.headerIcon=NSImage(named: "AppGlyph")
		session.onCancel={ [weak self] in
			let cancelError = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: nil)
			self?.extensionContext?.cancelRequest(withError: cancelError)
		}
		session.onFinish={ [weak self] error in
			if let error{
				self?.extensionContext?.cancelRequest(withError: error)
			}else{
				self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
			}
		}

		let item = self.extensionContext!.inputItems[0] as! NSExtensionItem
		guard let attachments = item.attachments else {
			session.onCancel()
			return
		}
		var urls:[URL]=[]
		var loaded=0
		for attachment in attachments {
			attachment.loadItem(forTypeIdentifier: UTType.url.identifier) { data, err in
				var url:URL?
				if let urlData=data as? Data{
					url=URL(dataRepresentation: urlData, relativeTo: nil, isAbsolute: false)
				}else if let nsurl=data as? NSURL{
					url=nsurl as URL
				}
				DispatchQueue.main.async {
					if let url{
						urls.append(url)
					}
					loaded+=1
					if loaded==attachments.count{
						if urls.isEmpty{
							self.session.onCancel()
						}else{
							self.session.setFiles(urls)
						}
					}
				}
			}
		}
	}
	
	override func viewDidLoad(){
		super.viewDidLoad()
		session.start()
	}

	override func viewWillDisappear() {
		session.stop()
	}
}
