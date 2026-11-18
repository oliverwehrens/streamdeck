import Foundation
import HTTPTypes
import Hummingbird
import NIOCore

/// Per-request context: the paired client, once authenticated, and the peer address for logs.
public struct WebContext: RequestContext {
    public var coreContext: CoreRequestContextStorage
    /// Set by `AuthMiddleware`.
    var clientID: String?
    let remoteAddress: String

    public init(source: ApplicationRequestContextSource) {
        coreContext = .init(source: source)
        remoteAddress = source.channel.remoteAddress?.ipAddress ?? "unknown"
    }

    /// Request bodies are config documents and small commands.
    public var maxUploadSize: Int { WebServer.maxBodySize }
}

/// Adds the security headers to every response, errors included. See design "Request hardening".
struct SecurityHeadersMiddleware: RouterMiddleware {
    typealias Context = WebContext

    static let contentSecurityPolicy =
        "default-src 'self'; img-src 'self' data:; style-src 'self'; script-src 'self'; font-src 'self'; connect-src 'self'; frame-ancestors 'none'"

    func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
        var response: Response
        do {
            response = try await next(request, context)
        } catch let error as any HTTPResponseError {
            response = try error.response(from: request, context: context)
        }
        response.headers[.contentSecurityPolicy] = Self.contentSecurityPolicy
        response.headers[.xContentTypeOptions] = "nosniff"
        response.headers[HTTPField.Name("Referrer-Policy")!] = "no-referrer"
        return response
    }
}

/// State-changing requests must come from our own page, as JSON, and be small.
struct RequestHardeningMiddleware: RouterMiddleware {
    typealias Context = WebContext

    func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
        switch request.method {
        case .get, .head, .options:
            return try await next(request, context)
        default:
            break
        }
        if let length = request.headers[.contentLength].flatMap(Int.init), length > WebServer.maxBodySize {
            throw HTTPError(.contentTooLarge)
        }
        guard let host = request.head.authority, request.headers[.origin] == "http://\(host)" else {
            throw HTTPError(.forbidden, message: "cross-origin request refused")
        }
        guard let type = request.headers[.contentType], type.lowercased().hasPrefix("application/json") else {
            throw HTTPError(.forbidden, message: "requests must be JSON")
        }
        return try await next(request, context)
    }
}

/// Lets requests through only with a valid token cookie; sets `context.clientID`.
struct AuthMiddleware: RouterMiddleware {
    typealias Context = WebContext
    static let cookieName = "streamdeck_token"

    let web: WebEditor

    func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
        guard let token = request.cookies[Self.cookieName]?.value,
              let client = await MainActor.run(body: { web.tokens.validate(token) })
        else {
            throw HTTPError(.unauthorized, message: "not paired")
        }
        var context = context
        context.clientID = client.id
        return try await next(request, context)
    }
}
