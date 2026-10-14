import Foundation

/// File-name slugs for screen files.
public enum Slug {
    /// Lowercases `name`, folds accents, turns each run of characters other than ASCII letters and digits into
    /// `-`, and trims dashes from the ends. An empty result becomes `screen`.
    public static func make(_ name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        var slug = ""
        var pendingDash = false
        for scalar in folded.unicodeScalars {
            let isAlphanumeric = ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar)
            if isAlphanumeric {
                if pendingDash, !slug.isEmpty {
                    slug += "-"
                }
                pendingDash = false
                slug.unicodeScalars.append(scalar)
            } else {
                pendingDash = true
            }
        }
        return slug.isEmpty ? "screen" : slug
    }

    /// Unique slugs for `names` in order. A repeated slug gets `-2`, `-3`, and so on, so earlier names keep the
    /// plain slug.
    public static func unique(_ names: [String]) -> [String] {
        var used = Set<String>()
        return names.map { name in
            let base = make(name)
            var candidate = base
            var suffix = 2
            while used.contains(candidate) {
                candidate = "\(base)-\(suffix)"
                suffix += 1
            }
            used.insert(candidate)
            return candidate
        }
    }
}
