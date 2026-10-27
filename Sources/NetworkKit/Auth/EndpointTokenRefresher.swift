import Foundation

/// Refreshes tokens by calling an app-defined refresh `Endpoint`.
///
/// The call goes straight through the transport — not through `NetworkClient` — so it never
/// carries the expired access token, never runs interceptors and can't recursively trigger
/// another refresh.
///
/// ```swift
/// let refresher = EndpointTokenRefresher(
///     transport: transport,
///     environmentResolver: resolver,
///     makeEndpoint: { refreshToken in RefreshTokenEndpoint(refreshToken: refreshToken) },
///     mapResponse: { dto in AuthTokens(accessToken: dto.accessToken, refreshToken: dto.refreshToken, expiresIn: dto.expiresIn) }
/// )
/// ```
public struct EndpointTokenRefresher<RefreshEndpoint: Endpoint>: TokenRefresher {
    private let transport: any HTTPTransport
    private let environmentResolver: any EnvironmentResolver
    private let builder: RequestBuilder
    private let decoder: ResponseDecoder
    private let makeEndpoint: @Sendable (_ refreshToken: String) -> RefreshEndpoint
    private let mapResponse: @Sendable (RefreshEndpoint.Response) throws -> AuthTokens

    public init(
        transport: any HTTPTransport,
        environmentResolver: any EnvironmentResolver,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder(),
        makeEndpoint: @escaping @Sendable (_ refreshToken: String) -> RefreshEndpoint,
        mapResponse: @escaping @Sendable (RefreshEndpoint.Response) throws -> AuthTokens
    ) {
        self.transport = transport
        self.environmentResolver = environmentResolver
        self.builder = RequestBuilder(encoder: encoder)
        self.decoder = ResponseDecoder(decoder: decoder)
        self.makeEndpoint = makeEndpoint
        self.mapResponse = mapResponse
    }

    public func refresh(using tokens: AuthTokens) async throws -> AuthTokens {
        guard let refreshToken = tokens.refreshToken else {
            throw NetworkError.missingCredentials
        }
        let endpoint = makeEndpoint(refreshToken)
        let environment = await environmentResolver.currentEnvironment()
        let request = try builder.makeRequest(for: endpoint, environment: environment)
        let response = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw NetworkError.httpStatus(HTTPErrorResponse(response))
        }
        let dto = try decoder.decode(RefreshEndpoint.Response.self, from: response)
        return try mapResponse(dto)
    }
}
