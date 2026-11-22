import Foundation

public enum JoinLink {
    private static let pattern =
        #"https://[A-Za-z0-9.\-]*(zoom\.us|meet\.google\.com|teams\.microsoft\.com|teams\.live\.com|webex\.com|whereby\.com|around\.co)[^\s<>"')]*"#

    /// The first video-call link found in any of the given texts (location, notes, URL).
    public static func find(in texts: [String?]) -> URL? {
        for text in texts.compactMap({ $0 }) {
            if let range = text.range(of: pattern, options: .regularExpression),
               let url = URL(string: String(text[range])) {
                return url
            }
        }
        return nil
    }
}
