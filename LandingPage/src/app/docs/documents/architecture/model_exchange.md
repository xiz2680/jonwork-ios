# Model Exchange Protocol

The Model Exchange Protocol enables your application to securely request and receive configured language models from FlowDown. Instead of asking users to copy-paste sensitive credentials, you can use the `FlowDownModelExchange` framework to handle the secure handshake and data transfer.

![Model Exchange interface](../../../res/screenshots/imgs/model-exchange-interface.png)

::: info Version Requirement
This protocol requires FlowDown version **4.1.4** or later installed on the user's device.
:::

## Installation

Currently, `FlowDownModelExchange` is distributed as part of the FlowDown source tree and not hosted on a separate public repository. You need to integrate it manually.

1.  Locate the directory `Frameworks/FlowDownModelExchange` in the FlowDown repository.
2.  Copy the entire folder into your project workspace.
3.  Add it as a **Local Package** in Xcode (File -> Add Package Dependencies -> Add Local...), or directly include the source files in your target.

## Usage

### 1. Initialization

First, initialize a key pair. You should persist this key pair if you want to maintain the same identity across sessions, or generate a new one for each session.

```swift
import FlowDownModelExchange

// Generate a new key pair for encryption and signing
let keyPair = ModelExchangeKeyPair()

// Initialize the request builder
let builder = ModelExchangeRequestBuilder(
    callbackScheme: "my-app-scheme", // Your app's URL scheme
    keyPair: keyPair
)
```

### 2. Start the Handshake

The protocol requires a handshake before requesting models. First, open FlowDown with the handshake URL to establish a verified session.

```swift
func startHandshake() {
    guard let url = builder.makeHandshakeURL() else {
        print("Handshake URL unavailable")
        return
    }
    // Open FlowDown to begin verification
    UIApplication.shared.open(url)
}
```

### 3. Handle Callbacks

Configure your app to handle the callback URL (e.g., in `onOpenURL` or `AppDelegate`). The protocol has three stages: `verification`, `completed`, and `cancelled`.

```swift
var sessionId: String?

func handleCallback(url: URL) {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          let queryItems = components.queryItems else { return }

    let params = Dictionary(uniqueKeysWithValues: queryItems.compactMap { item -> (String, String)? in
        guard let value = item.value else { return nil }
        return (item.name.lowercased(), value)
    })

    switch params["stage"]?.lowercased() {
    case "verification":
        handleVerification(params: params)
    case "completed":
        handleCompletion(params: params)
    case "cancelled":
        sessionId = nil
        print("User cancelled in FlowDown")
    default:
        print("Unknown callback stage")
    }
}
```

### 4. Handle Verification and Request Models

When FlowDown calls back with `stage=verification`, validate the session and public key, then send the actual exchange request.

```swift
func handleVerification(params: [String: String]) {
    guard let session = params["session"] else {
        print("Missing session in verification")
        return
    }
    guard let pk = params["pk"], pk == keyPair.encodedPublicKey else {
        print("Public key mismatch in verification")
        return
    }

    sessionId = session

    do {
        let signed = try builder.makeExchangeURL(
            session: session,
            appName: "My Awesome App",
            reason: "To assist with coding tasks",
            capabilities: [.audio, .developerRole],
            multipleSelection: false
        )
        UIApplication.shared.open(signed.url)
    } catch {
        print("Failed to build request: \(error)")
    }
}
```

### 5. Decrypt Payload

Once you receive the `completed` callback, use the framework to decode and decrypt the payload.

```swift
func handleCompletion(params: [String: String]) {
    guard let payloadString = params["payload"],
          let session = params["session"],
          session == sessionId else { return }

    do {
        // 1. Decode the encrypted payload wrapper
        let encryptedPayload = try ModelExchangeEncryptedPayload.decode(from: payloadString)

        // 2. Decrypt the data using your key pair
        let decryptedData = try ModelExchangeCrypto.decrypt(
            encryptedPayload,
            with: keyPair
        )

        // 3. Parse the model data (format is indicated by params["format"], usually "plist")
        let models = try PropertyListSerialization.propertyList(
            from: decryptedData,
            options: [],
            format: nil
        )

        print("Received models: \(models)")
    } catch {
        print("Decryption failed: \(error)")
    }
    sessionId = nil
}
```

## Security

The framework handles the security details for you:

- **Signatures**: Requests are signed with your private key to prevent tampering.
- **Encryption**: Data is encrypted using `ChaChaPoly` (Symmetric) and `Curve25519` (Key Agreement).
- **Forward Secrecy**: Ephemeral keys are used for the exchange session.

## Data Format

The decrypted data is a serialized Property List (Plist) containing:

- Model display names
- Endpoint URLs
- Authentication headers (including sensitive credentials)
- Model capabilities

Treat this data with the highest level of security. **Do not log sensitive fields** in production.
