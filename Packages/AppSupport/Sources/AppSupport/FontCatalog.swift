import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// System font families for the text style bar. Families are picked by
/// display name but STORED as the family's first member's PostScript name
/// (D13) — matching the contract's `StyledText.fontName` convention;
/// "" remains "book default".
public enum FontCatalog {

    public struct Family: Identifiable, Equatable {
        public let displayName: String
        public let postScriptName: String
        public var id: String { postScriptName }

        public init(displayName: String, postScriptName: String) {
            self.displayName = displayName
            self.postScriptName = postScriptName
        }
    }

    public static func families() -> [Family] {
        #if os(macOS)
        return NSFontManager.shared.availableFontFamilies.sorted().compactMap { family in
            guard let members = NSFontManager.shared.availableMembers(ofFontFamily: family),
                  let first = members.first,
                  let postScriptName = first.first as? String,
                  !postScriptName.isEmpty
            else { return nil }
            return Family(displayName: family, postScriptName: postScriptName)
        }
        #else
        return UIFont.familyNames.sorted().compactMap { family in
            guard let postScriptName = UIFont.fontNames(forFamilyName: family).sorted().first,
                  !postScriptName.isEmpty
            else { return nil }
            return Family(displayName: family, postScriptName: postScriptName)
        }
        #endif
    }
}
