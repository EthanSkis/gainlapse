import Foundation

/// Where the app sends check-in requests.
/// The anon key is safe to ship in the app. The Anthropic key lives only on the server.
enum Backend {
    static let supabaseURL = "https://fotiygfugeeznttkfhuf.supabase.co"
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZvdGl5Z2Z1Z2Vlem50dGtmaHVmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTM4NTA1MDMsImV4cCI6MjEwOTQyNjUwM30.WzttD3wxAHFpydvD-DGTzhLgdNbQub3TooxDMY2Q3sM"

    static var isConfigured: Bool { !supabaseURL.isEmpty && !supabaseAnonKey.isEmpty }
    static let privacyURL = URL(string: "https://gainlapse.vercel.app/privacy")!
    static let supportURL = URL(string: "https://gainlapse.vercel.app/support")!
    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    static var checkInURL: URL? { URL(string: "\(supabaseURL)/functions/v1/check-in") }
}

/// Switches for simulator testing. These do nothing in Release builds.
enum DebugFlags {
    static var mockCheckIn: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-mockCheckIn")
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
        #endif
        return nil
    }
}
