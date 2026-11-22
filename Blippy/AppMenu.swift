// SPDX-License-Identifier: Apache-2.0
//
//  AppMenu.swift
//  Blippy
//
//  The Mac menu bar. Built in code; it replaces the menu from the nib at launch.
//

import Cocoa

enum AppMenu {
	static func build(target: AppDelegate) -> NSMenu {
		let main = NSMenu()
		let name = "Blippy"

		func add(_ menu: NSMenu, _ title: String, _ action: Selector?, key: String = "", mods: NSEvent.ModifierFlags = .command, target: AnyObject? = nil, tag: Int = 0) {
			let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
			item.keyEquivalentModifierMask = key.isEmpty ? [] : mods
			item.target = target
			item.tag = tag
			menu.addItem(item)
		}

		func submenu(_ title: String, _ build: (NSMenu) -> Void) -> NSMenu {
			let menu = NSMenu(title: title)
			let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
			holder.submenu = menu
			main.addItem(holder)
			build(menu)
			return menu
		}

		// Blippy
		_ = submenu(name) { m in
			add(m, String(format: NSLocalizedString("MenuAbout", value: "About %@", comment: ""), name), #selector(AppDelegate.showAbout(_:)), target: target)
			m.addItem(.separator())
			add(m, NSLocalizedString("MenuSettings", value: "Settings…", comment: ""), #selector(AppDelegate.goToPage(_:)), key: ",", target: target, tag: tag(.settings))
			m.addItem(.separator())
			let services = NSMenu(title: "Services")
			let servicesItem = NSMenuItem(title: NSLocalizedString("MenuServices", value: "Services", comment: ""), action: nil, keyEquivalent: "")
			servicesItem.submenu = services
			m.addItem(servicesItem)
			NSApp.servicesMenu = services
			m.addItem(.separator())
			add(m, String(format: NSLocalizedString("MenuHide", value: "Hide %@", comment: ""), name), #selector(NSApplication.hide(_:)), key: "h")
			add(m, NSLocalizedString("MenuHideOthers", value: "Hide Others", comment: ""), #selector(NSApplication.hideOtherApplications(_:)), key: "h", mods: [.command, .option])
			add(m, NSLocalizedString("MenuShowAll", value: "Show All", comment: ""), #selector(NSApplication.unhideAllApplications(_:)))
			m.addItem(.separator())
			add(m, String(format: NSLocalizedString("Quit", value: "Quit %@", comment: ""), name), #selector(NSApplication.terminate(_:)), key: "q")
		}

		// File
		_ = submenu(NSLocalizedString("MenuFile", value: "File", comment: "")) { m in
			add(m, NSLocalizedString("MenuSendFiles", value: "Send Files…", comment: ""), #selector(AppDelegate.sendFiles(_:)), key: "o", target: target)
			add(m, NSLocalizedString("ShowDownloads", value: "Show Received Files", comment: ""), #selector(AppDelegate.showDownloads(_:)), key: "d", mods: [.command, .shift], target: target)
			m.addItem(.separator())
			add(m, NSLocalizedString("MenuClose", value: "Close Window", comment: ""), #selector(NSWindow.performClose(_:)), key: "w")
		}

		// Edit
		_ = submenu(NSLocalizedString("MenuEdit", value: "Edit", comment: "")) { m in
			add(m, NSLocalizedString("MenuUndo", value: "Undo", comment: ""), Selector(("undo:")), key: "z")
			add(m, NSLocalizedString("MenuRedo", value: "Redo", comment: ""), Selector(("redo:")), key: "z", mods: [.command, .shift])
			m.addItem(.separator())
			add(m, NSLocalizedString("MenuCut", value: "Cut", comment: ""), #selector(NSText.cut(_:)), key: "x")
			add(m, NSLocalizedString("MenuCopy", value: "Copy", comment: ""), #selector(NSText.copy(_:)), key: "c")
			add(m, NSLocalizedString("MenuPaste", value: "Paste", comment: ""), #selector(NSText.paste(_:)), key: "v")
			add(m, NSLocalizedString("MenuSelectAll", value: "Select All", comment: ""), #selector(NSText.selectAll(_:)), key: "a")
		}

		// View: one entry per page (⌘1…⌘5) and full screen
		_ = submenu(NSLocalizedString("MenuView", value: "View", comment: "")) { m in
			for (index, page) in [Page.send, .received, .cable, .history, .devices].enumerated() {
				add(m, page.title, #selector(AppDelegate.goToPage(_:)), key: "\(index + 1)", target: target, tag: tag(page))
			}
			m.addItem(.separator())
			add(m, NSLocalizedString("MenuFullScreen", value: "Enter Full Screen", comment: ""), #selector(NSWindow.toggleFullScreen(_:)), key: "f", mods: [.command, .control])
		}

		// Window
		let windowMenu = submenu(NSLocalizedString("MenuWindow", value: "Window", comment: "")) { m in
			add(m, NSLocalizedString("MenuMinimize", value: "Minimize", comment: ""), #selector(NSWindow.performMiniaturize(_:)), key: "m")
			add(m, NSLocalizedString("MenuZoom", value: "Zoom", comment: ""), #selector(NSWindow.performZoom(_:)))
			m.addItem(.separator())
			add(m, NSLocalizedString("MenuBringToFront", value: "Bring All to Front", comment: ""), #selector(NSApplication.arrangeInFront(_:)))
		}
		NSApp.windowsMenu = windowMenu

		// Help
		let helpMenu = submenu(NSLocalizedString("MenuHelp", value: "Help", comment: "")) { m in
			add(m, String(format: NSLocalizedString("MenuHelpItem", value: "%@ Help", comment: ""), name), #selector(AppDelegate.openHelp(_:)), key: "?", target: target)
			add(m, NSLocalizedString("MenuPrivacy", value: "Privacy Statement", comment: ""), #selector(AppDelegate.showPrivacy(_:)), target: target)
			add(m, NSLocalizedString("MenuLicenses", value: "Open Source Licenses", comment: ""), #selector(AppDelegate.showLicenses(_:)), target: target)
			if AppInfo.issuesURL != nil {
				m.addItem(.separator())
				add(m, NSLocalizedString("MenuReport", value: "Report an Issue…", comment: ""), #selector(AppDelegate.openIssues(_:)), target: target)
			}
			if AppInfo.coffeeURL != nil {
				m.addItem(.separator())
				add(m, NSLocalizedString("MenuCoffee", value: "Buy Me a Coffee…", comment: ""), #selector(AppDelegate.openCoffee(_:)), target: target)
			}
		}
		NSApp.helpMenu = helpMenu

		return main
	}

	/// Menu items carry the page as an integer tag.
	static func tag(_ page: Page) -> Int { Page.allCases.firstIndex(of: page) ?? 0 }
	static func page(forTag tag: Int) -> Page { Page.allCases.indices.contains(tag) ? Page.allCases[tag] : .send }
}
