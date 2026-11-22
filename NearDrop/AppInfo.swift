// SPDX-License-Identifier: Apache-2.0
//
//  AppInfo.swift
//  Blippy
//
//  The few facts about the project that the app shows in its menus and Settings.
//  Run `scripts/set-identity.sh` to fill these in; until then the GitHub items stay hidden.
//

import AppKit

enum AppInfo {
	static let placeholderOwner = "YOUR-GITHUB-USERNAME"

	/// Your GitHub username or organization.
	static let githubOwner = "yaw595"
	static let repoName = "blippy"
	/// Your support link (Buy Me a Coffee, Paystack, anything). Empty hides the support section.
	static let coffeeLink = "https://paystack.shop/pay/igugouqwlf"

	static var repoURL: URL? {
		githubOwner == placeholderOwner ? nil : URL(string: "https://github.com/\(githubOwner)/\(repoName)")
	}

	static var issuesURL: URL? { repoURL?.appendingPathComponent("issues") }
	static var coffeeURL: URL? { coffeeLink.isEmpty ? nil : URL(string: coffeeLink) }

	static var version: String {
		Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
	}

	static let privacyStatement = NSLocalizedString(
		"PrivacyStatement",
		value: "Blippy collects no data and has no analytics, tracking or accounts. Files go straight between your devices over your own Wi-Fi or a USB cable, and nothing is sent to any server. Your transfer history stays on this Mac, and you can delete it any time from the History page.",
		comment: "")
}

/// Light, Dark, or follow the Mac.
enum AppearanceMode: String, CaseIterable, Identifiable {
	case system, light, dark

	static let key = "Blippy.appearance"
	var id: String { rawValue }

	var title: String {
		switch self {
		case .system: return NSLocalizedString("AppearanceSystem", value: "System", comment: "")
		case .light: return NSLocalizedString("AppearanceLight", value: "Light", comment: "")
		case .dark: return NSLocalizedString("AppearanceDark", value: "Dark", comment: "")
		}
	}

	static var current: AppearanceMode {
		AppearanceMode(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .system
	}

	/// Applies the choice to every Blippy window (nil follows the system setting).
	func apply() {
		switch self {
		case .system: NSApp.appearance = nil
		case .light: NSApp.appearance = NSAppearance(named: .aqua)
		case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
		}
	}
}
