import Foundation

enum FeedbackError: Error {
    case serverError
}

/// Posts feedback to a backend. `endpoint` is a placeholder — no backend exists yet,
/// so calls will fail until a real one is stood up and this is pointed at it.
enum FeedbackService {
    static let endpoint = URL(string: "https://example.com/api/feedback")!

    static func submit(message: String) async throws {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: String] = [
            "message": message,
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        ]
        request.httpBody = try JSONEncoder().encode(payload)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw FeedbackError.serverError
        }
    }
}
