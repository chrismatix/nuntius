import AppKit
import Carbon
import ApplicationServices
import os

struct OutputContent {
    let plainText: String
    let richText: NSAttributedString?

    static func plain(_ text: String) -> OutputContent {
        OutputContent(plainText: text, richText: nil)
    }
}

@MainActor
final class OutputManager {
    enum OutputMode: String {
        case clipboard
        case pasteInPlace = "paste"
    }

    private let logger = Logger(subsystem: "com.chrismatix.nuntius", category: "OutputManager")
    private static let pasteDelay: TimeInterval = 0.05

    var mode: OutputMode {
        let modeString = UserDefaults.standard.string(forKey: "outputMode") ?? "paste"
        return OutputMode(rawValue: modeString) ?? .pasteInPlace
    }

    func output(_ content: OutputContent) {
        copyToClipboard(content)

        if mode == .pasteInPlace {
            guard checkAccessibilityPermission() else {
                logger.warning("Accessibility permission not granted, text copied to clipboard only")
                Task { @MainActor in
                    NotificationService.shared.showWarning(
                        title: "Accessibility Permission Required",
                        message: "Text was copied to clipboard. Grant accessibility permission in System Settings to enable auto-paste."
                    )
                }
                return
            }

            // Check if there's a text field to paste into
            guard isTextFieldFocused() else {
                logger.info("No text field focused, copied to clipboard only")
                OverlayWindow.shared.showMessage("Copied to clipboard", icon: "doc.on.clipboard", autoDismissAfter: 2.0)
                return
            }

            sendPaste()
        }
    }

    /// Checks if a text input field is currently focused in the frontmost application
    private func isTextFieldFocused() -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            logger.debug("No frontmost application found")
            return false
        }

        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)

        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        guard result == .success, let element = focusedElement else {
            logger.debug("Could not get focused element: \(result.rawValue)")
            return false
        }

        // Check if the focused element is a text input type
        var role: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(element as! AXUIElement, kAXRoleAttribute as CFString, &role)

        guard roleResult == .success, let roleString = role as? String else {
            logger.debug("Could not get role of focused element")
            return false
        }

        // Text input roles
        let textInputRoles: Set<String> = [
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            kAXComboBoxRole as String,
            "AXSearchField"  // kAXSearchFieldRole
        ]

        if textInputRoles.contains(roleString) {
            return true
        }

        // Also check if the element has AXValue attribute that's editable (for web content)
        var isEditable: CFTypeRef?
        let editableResult = AXUIElementCopyAttributeValue(element as! AXUIElement, "AXEditable" as CFString, &isEditable)
        if editableResult == .success, let editable = isEditable as? Bool, editable {
            return true
        }

        logger.debug("Focused element role '\(roleString)' is not a text input")
        return false
    }

    func checkAccessibilityPermission() -> Bool {
        let trusted = AXIsProcessTrusted()

        if !trusted {
            // Prompt user to grant permission
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)

            // Check again - permission might be granted now
            // Note: If just granted, may require app relaunch to take effect
            return AXIsProcessTrusted()
        }

        return true
    }

    private func copyToClipboard(_ content: OutputContent) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if let richText = content.richText, let rtfData = richText.rtfData() {
            let item = NSPasteboardItem()
            item.setData(rtfData, forType: .rtf)
            item.setString(content.plainText, forType: .string)
            let success = pasteboard.writeObjects([item])
            if !success {
                logger.warning("Failed to copy rich text to clipboard")
            }
        } else {
            let success = pasteboard.setString(content.plainText, forType: .string)
            if !success {
                logger.warning("Failed to copy text to clipboard")
            }
        }
    }

    private func sendPaste() {
        // Small delay to ensure the target app is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pasteDelay) { [weak self] in
            guard let self else { return }

            // Synthesize Cmd+V
            let src = CGEventSource(stateID: .hidSystemState)

            guard let keyDown = CGEvent(keyboardEventSource: src, virtualKey: KeyCode.v, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: src, virtualKey: KeyCode.v, keyDown: false) else {
                self.logger.error("Failed to create CGEvent for paste operation")
                Task { @MainActor in
                    NotificationService.shared.showError(
                        title: "Paste Failed",
                        message: "Could not simulate paste command. Text is in clipboard.",
                        critical: false
                    )
                }
                return
            }

            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand

            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }
}

private extension NSAttributedString {
    func rtfData() -> Data? {
        let range = NSRange(location: 0, length: length)
        return try? data(from: range, documentAttributes: [.documentType: DocumentType.rtf])
    }
}

// Virtual key codes for keyboard events
private enum KeyCode {
    static let v: CGKeyCode = 0x09
}
