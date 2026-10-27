# Getting started with NetworkKit

A step-by-step guide to adding NetworkKit to an app and calling an API.

The examples use **JSONPlaceholder** (`https://jsonplaceholder.typicode.com`), a free public test API,
so you can paste the code and see real results. Then swap in your own server.

**In short:** add the package, create one client, write one small struct per API call, then call
`try await client.request(TheEndpoint(...))`.

---

## 1. Add the package (one time)

1. In Xcode, choose **File ▸ Add Package Dependencies…**
2. Paste `https://github.com/Liji-S/NetworkKit.git`
3. For **Dependency Rule**, choose **Up to Next Major Version**, starting at `0.1.0`
4. Click **Add Package**, then tick the products:
   - **NetworkKit**: add it to your **app** target
   - **NetworkKitTesting**: add it to your **unit test** target only, if you write tests

Then, in any file that makes API calls:

```swift
import NetworkKit
```

Requirements: iOS 16+ and Xcode 16+ (Swift 6).

## 2. Say where the server is (one time)

```swift
import NetworkKit

extension NetworkEnvironment {
    static let jsonPlaceholder = NetworkEnvironment(
        name: "jsonplaceholder",
        baseURL: URL(string: "https://jsonplaceholder.typicode.com")!,
        logLevel: .basic          // prints each call in the Xcode console; use .off for release
    )
}
```

If the API needs a fixed key, add it here and it's sent with every call:

```swift
defaultHeaders: ["X-Api-Key": "your-key"]
```

> Don't hard-code real keys in source. Load them from a config file that isn't committed.

## 3. Create the client (one time, shared by the whole app)

```swift
let client: NetworkClientProtocol = NetworkClient(
    configuration: NetworkClientConfiguration(environment: .jsonPlaceholder)
)
```

Create the client **once**, for example in your app's dependency container, and pass it to whoever
needs it. Don't create a new client for each call.

Store and pass it as `NetworkClientProtocol` (the protocol), not `NetworkClient`. Then tests can swap
in a mock (see step 10).

## 4. Describe what the server returns

A plain `Codable` struct that matches the JSON:

```swift
struct Post: Codable, Sendable {
    let id: Int
    let userId: Int
    let title: String
    let body: String
}
```

## 5. Describe each API call (an "endpoint")

Each API call is a small struct that conforms to `Endpoint`. Only two things are required:

- `Response`: what the call returns
- `path`: the part of the URL after the base URL

Everything else has a sensible default: `GET`, no body, no login, no caching.

**GET a list, with query parameters:** `GET /posts?userId=1`

```swift
struct FetchPostsEndpoint: Endpoint {
    typealias Response = [Post]
    let userId: Int

    var path: String { "posts" }
    var queryItems: [URLQueryItem] { [URLQueryItem(name: "userId", value: "\(userId)")] }
}
```

**GET one item:** `GET /posts/1`

```swift
struct FetchPostEndpoint: Endpoint {
    typealias Response = Post
    let id: Int

    var path: String { "posts/\(id)" }
}
```

**POST with a JSON body:** `POST /posts`

```swift
struct NewPost: Encodable, Sendable {
    let userId: Int
    let title: String
    let body: String
}

struct CreatePostEndpoint: Endpoint {
    typealias Response = Post
    let post: NewPost

    var path: String { "posts" }
    var method: HTTPMethod { .post }
    var body: RequestBody? { .json(post) }
}
```

**DELETE, nothing returned:** `DELETE /posts/1`

```swift
struct DeletePostEndpoint: Endpoint {
    typealias Response = EmptyResponse    // use this when the server returns no body
    let id: Int

    var path: String { "posts/\(id)" }
    var method: HTTPMethod { .delete }
}
```

## 6. Call the API

```swift
let posts = try await client.request(FetchPostsEndpoint(userId: 1))      // [Post]
let post = try await client.request(FetchPostEndpoint(id: 1))            // Post
let created = try await client.request(CreatePostEndpoint(
    post: NewPost(userId: 1, title: "Hello", body: "First post")
))                                                                        // Post
_ = try await client.request(DeletePostEndpoint(id: 1))                  // EmptyResponse
```

The return type comes from the endpoint's `Response`. There's no manual JSON decoding and no casting.

To get the status code and headers as well, for example for pagination, use `response(_:)`:

```swift
let result = try await client.response(FetchPostsEndpoint(userId: 1))
print(result.value.count, result.statusCode, result.headers["Content-Type"] ?? "", result.isFromCache)
```

## 7. Use it from a screen (typical pattern)

```swift
import SwiftUI
import NetworkKit

@Observable
@MainActor
final class PostsViewModel {
    private(set) var posts: [Post] = []
    private(set) var errorMessage: String?
    private(set) var isLoading = false

    private let client: NetworkClientProtocol

    init(client: NetworkClientProtocol) {
        self.client = client
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            posts = try await client.request(FetchPostsEndpoint(userId: 1))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription   // already a user-friendly message
        }
    }
}

struct PostsView: View {
    @State var viewModel: PostsViewModel

    var body: some View {
        List(viewModel.posts, id: \.id) { post in
            Text(post.title)
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            } else if let message = viewModel.errorMessage {
                Text(message)
            }
        }
        .task { await viewModel.load() }
    }
}
```

When the user leaves the screen, `.task` cancels the request automatically.

> `@Observable` needs iOS 17. If your app still supports iOS 16, use `final class PostsViewModel: ObservableObject`
> with `@Published private(set) var` properties, and `@StateObject` in the view. The NetworkKit calls are the same.

## 8. Handling errors

Every error from NetworkKit is a `NetworkError`. Most screens only need `error.localizedDescription`,
which gives messages like "You appear to be offline. Check your connection and try again."

To react to specific cases:

```swift
do {
    let post = try await client.request(FetchPostEndpoint(id: 999))
    print(post.title)
} catch .noConnection {
    // show an offline banner
} catch .httpStatus(let response) where response.statusCode == 404 {
    // show "not found"
} catch {
    print(error.localizedDescription)
}
```

The cases you'll see most often:

| Error | Meaning |
|---|---|
| `.noConnection` | The device is offline |
| `.timedOut` | The server took too long |
| `.httpStatus(response)` | The server replied with an error code (`response.statusCode`, e.g. 404, 500) |
| `.decodingFailed(message)` | The JSON didn't match your struct; the message names the field |
| `.cancelled` | The request was cancelled (e.g. the user left the screen); usually ignore it |

If your server sends error details as JSON, decode them from the response body:

```swift
struct APIErrorDTO: Decodable { let message: String }

catch .httpStatus(let response) {
    let details = try? response.decodeBody(APIErrorDTO.self)
}
```

## 9. Useful extras (all optional)

| Want to… | Add to the endpoint |
|---|---|
| Cache the result for 5 minutes | `var cachePolicy: CachePolicy { .cacheFirst(ttl: 300) }` |
| Show cached data when offline | `var cachePolicy: CachePolicy { .networkFirst(ttl: 300) }` |
| Give a slow call more time (seconds) | `var timeout: TimeInterval? { 60 }` |
| Send an extra header for one call | `var headers: HTTPHeaders { ["X-Custom": "value"] }` |
| Get the raw bytes (e.g. an image) | `typealias Response = Data` |
| Upload a file | `var body: RequestBody? { .multipart(form) }` (see [README](README.md)) |
| Require the user's login token | `var auth: AuthRequirement { .bearer }` (needs an `AuthManager`; see [README](README.md#authentication)) |

Retries happen automatically for temporary failures: server errors like 503, timeouts and dropped
connections. Only safe-to-repeat requests (`GET`, `PUT`, `DELETE`) are retried, so a `POST` is never
sent twice by accident.

## 10. Writing tests (optional)

In your test target, import `NetworkKitTesting` and use the mock client. No internet is needed:

```swift
import Testing
import NetworkKit
import NetworkKitTesting

@MainActor
@Test func loadsPosts() async {
    let client = MockNetworkClient()
    await client.stub(FetchPostsEndpoint.self, with: [
        Post(id: 1, userId: 1, title: "Test", body: "Body")
    ])
    let viewModel = PostsViewModel(client: client)

    await viewModel.load()

    #expect(viewModel.posts.first?.title == "Test")
}

@MainActor
@Test func showsOfflineMessage() async {
    let client = MockNetworkClient()
    await client.stub(FetchPostsEndpoint.self, error: .noConnection)
    let viewModel = PostsViewModel(client: client)

    await viewModel.load()

    #expect(viewModel.errorMessage?.contains("offline") == true)
}
```

---

## When do I need interceptors?

Most apps don't. They're optional and empty by default.

Use an interceptor only when **every** API call needs the same extra step, and that step can't be
written down once as a fixed value. Ask yourself:

1. **Does it apply to all (or most) calls?** If not, put it in those endpoints.
2. **Is it the same value every time** (API key, app name)? Then use the environment's `defaultHeaders`
   instead.
3. **Is it worked out at the moment of sending** (a new request ID, the current time, a signature)?
   Then use a **request interceptor**.
4. **Do you want to check every response** (count failures, detect "please update the app")? Then use a
   **response interceptor**.

| You want to… | Use |
|---|---|
| Send your API key with every call | `defaultHeaders`, not an interceptor |
| Give every call a unique ID for debugging | Request interceptor (`CorrelationIDInterceptor` is built in) |
| Add the current time or a signature to every call | Request interceptor |
| Count how many calls fail, for analytics | Response interceptor |
| Show "Please update the app" if any call says the app is too old | Response interceptor |
| Send the user's login token | `auth: .bearer`, not an interceptor (built in, including token refresh) |

How to write one is in the [README](README.md#interceptors).

---

## Next steps

The [README](README.md) covers the advanced topics:

- login tokens with automatic refresh
- file uploads
- caching details
- retry settings
- interceptors
- switching between dev, staging and production servers
