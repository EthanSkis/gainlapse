import Foundation

/// Where the app sends check-in requests.
/// The anon key is safe to ship in the app. The Anthropic key lives only on the server.
enum Backend {
    static let supabaseURL = "https://fotiygfugeeznttkfhuf.supabase.co"
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZvdGl5Z2Z1Z2Vlem50dGtmaHVmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTM4NTA1MDMsImV4cCI6MjEwOTQyNjUwM30.WzttD3wxAHFpydvD-DGTzhLgdNbQub3TooxDMY2Q3sM"

    static var isConfigured: Bool { !supabaseURL.isEmpty && !supabaseAnonKey.isEmpty }
    static let privacyURL = URL(string: "https://gainlapse.com/privacy")!
    static let supportURL = URL(string: "https://gainlapse.com/support")!
    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    static var checkInURL: URL? { URL(string: "\(supabaseURL)/functions/v1/check-in") }
}

/// Switches for simulator testing. These do nothing in Release builds.
enum DebugFlags {
    /// The App Store screenshot run: sample data, representative check-in text and no test labels.
    /// On with the -cleanPaywall launch argument or the debug.storeShots default.
    static var storeShots: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-cleanPaywall")
            || UserDefaults.standard.bool(forKey: "debug.storeShots")
        #else
        return false
        #endif
    }

    /// A folder of 1.jpg, 2.jpg… used as the sample progress photos in a screenshot run.
    static var photoDirectory: String? {
        #if DEBUG
        // A plain folder name is looked up inside the app's Caches folder, which the simulator can always read.
        guard let value = UserDefaults.standard.string(forKey: "debug.photoDir") else { return nil }
        return value.hasPrefix("/") ? value : URL.cachesDirectory.appending(path: value).path
        #else
        return nil
        #endif
    }

    static var mockCheckIn: Bool {
        #if DEBUG
        return storeShots || ProcessInfo.processInfo.arguments.contains("-mockCheckIn")
        #else
        return false
        #endif
    }

    static var demoWeeks: Int? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-demoWeeks"), index + 1 < args.count {
            return Int(args[index + 1])
        }
        if storeShots {
            // One week per sample photo provided, or eight weeks of the illustrated figure.
            if let directory = photoDirectory {
                let count = (1...52).prefix { FileManager.default.fileExists(atPath: "\(directory)/\($0).jpg") }.count
                if count >= 1 { return count }
            }
            return 8
        }
        #endif
        return nil
    }
}
