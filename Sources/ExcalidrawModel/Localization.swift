import Foundation

/// Text layout direction for a locale.
public enum TextDirection: String, Sendable {
    case ltr
    case rtl
}

/// A single locale: its code, layout direction, and string table
/// (`packages/excalidraw/locales`).
public struct Locale: Equatable, Sendable {
    public let code: String
    public let direction: TextDirection
    public let strings: [String: String]

    public init(code: String, direction: TextDirection, strings: [String: String]) {
        self.code = code
        self.direction = direction
        self.strings = strings
    }

    public var isRTL: Bool {
        direction == .rtl
    }
}

/// Lightweight localization infrastructure: locale registry, language-tag
/// resolution, and key lookup with English fallback.
public enum Localization {
    public static let english = Locale(code: "en", direction: .ltr, strings: [
        "labels.selectAll": "Select all",
        "labels.copy": "Copy",
        "labels.cut": "Cut",
        "labels.paste": "Paste",
        "labels.delete": "Delete",
        "labels.duplicate": "Duplicate",
        "labels.link": "Link",
        "labels.library": "Library",
        "labels.bringToFront": "Bring to front",
        "labels.sendToBack": "Send to back",
        "toolBar.selection": "Selection",
        "toolBar.rectangle": "Rectangle",
        "toolBar.arrow": "Arrow",
        "toolBar.text": "Text"
    ])

    public static let spanish = Locale(code: "es", direction: .ltr, strings: [
        "labels.selectAll": "Seleccionar todo",
        "labels.copy": "Copiar",
        "labels.cut": "Cortar",
        "labels.paste": "Pegar",
        "labels.delete": "Eliminar",
        "labels.duplicate": "Duplicar",
        "labels.link": "Enlace",
        "labels.library": "Biblioteca",
        "labels.bringToFront": "Traer al frente",
        "labels.sendToBack": "Enviar al fondo",
        "toolBar.selection": "Selección",
        "toolBar.rectangle": "Rectángulo",
        "toolBar.arrow": "Flecha",
        "toolBar.text": "Texto"
    ])

    /// Arabic — a right-to-left locale, to exercise RTL layout.
    public static let arabic = Locale(code: "ar", direction: .rtl, strings: [
        "labels.selectAll": "تحديد الكل",
        "labels.copy": "نسخ",
        "labels.cut": "قص",
        "labels.paste": "لصق",
        "labels.delete": "حذف",
        "labels.duplicate": "تكرار",
        "labels.link": "رابط",
        "labels.library": "المكتبة",
        "labels.bringToFront": "إحضار إلى الأمام",
        "labels.sendToBack": "إرسال إلى الخلف",
        "toolBar.selection": "تحديد",
        "toolBar.rectangle": "مستطيل",
        "toolBar.arrow": "سهم",
        "toolBar.text": "نص"
    ])

    public static let all: [Locale] = [english, spanish, arabic]

    /// Resolve a BCP-47-ish language tag (e.g. `"ar"`, `"es-ES"`) to a known
    /// locale, matching on the primary language subtag and falling back to
    /// English.
    public static func locale(for tag: String) -> Locale {
        let language = tag.lowercased().split(separator: "-").first.map(String.init) ?? tag.lowercased()
        return all.first { $0.code == language } ?? english
    }

    /// Translate `key` in `locale`, falling back to English then the raw key so
    /// a missing translation never renders blank.
    public static func string(_ key: String, in locale: Locale) -> String {
        locale.strings[key] ?? english.strings[key] ?? key
    }
}
