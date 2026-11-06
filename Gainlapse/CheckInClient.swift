import Foundation
import UIKit

enum CheckInError: Error {
    case notConfigured
    case declined
    case unusable(String)
    case unavailable
    case subscriptionRequired
    case limitReached
}

enum CheckInClient {
    private struct RequestBody: Encodable {
        let goal: String
        let pose: String
        let week: Int
        let current: String
        let previous: String?
        let signed_transaction: String
    }

    private struct ResponseBody: Decodable {
        let usable: Bool
        let feedback: String
        let focus_tip: String
    }

    static func request(goal: Goal, pose: Pose, week: Int, current: UIImage, previous: UIImage?) async throws -> CheckIn {
        if DebugFlags.mockCheckIn {
            try await Task.sleep(for: .seconds(2))
            return CheckIn(
                feedback: "Sample feedback from a test build. A real check-in compares your two photos and points out what's visibly changing, along with how consistent you've been.",
                focusTip: "Sample tip: real check-ins give you one focus for the week.",
                createdAt: .now, isSample: true)
        }
        guard Backend.isConfigured, let url = Backend.checkInURL else { throw CheckInError.notConfigured }
        guard let signedTransaction = await Subscriptions.signedTransaction() else {
            throw CheckInError.subscriptionRequired
        }

        let body = await Task.detached(priority: .userInitiated) {
            RequestBody(goal: goal.rawValue, pose: pose.rawValue, week: week,
                        current: encode(current) ?? "", previous: previous.flatMap(encode),
                        signed_transaction: signedTransaction)
        }.value

        var request = URLRequest(url: url, timeoutInterval: 90)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(Backend.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(Backend.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw CheckInError.unavailable
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 422 { throw CheckInError.declined }
        if status == 402 { throw CheckInError.subscriptionRequired }
        if status == 429 { throw CheckInError.limitReached }
        guard status == 200, let result = try? JSONDecoder().decode(ResponseBody.self, from: data) else {
            throw CheckInError.unavailable
        }
        guard result.usable else { throw CheckInError.unusable(result.feedback) }
        return CheckIn(feedback: result.feedback, focusTip: result.focus_tip, createdAt: .now)
    }

    /// Scales a photo down before it leaves the phone: enough detail to compare, and no more.
    private nonisolated static func encode(_ image: UIImage) -> String? {
        let longest: CGFloat = 1024
        let scale = min(1, longest / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.72)?.base64EncodedString()
    }
}
