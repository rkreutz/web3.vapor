# web3.vapor
[![Platforms](https://img.shields.io/badge/platforms-macOS%2011%20|%20Linux%20-ff0000.svg?style=flat)](https://github.com/rkreutz/web3.vapor)
[![Swift Package Manager](https://img.shields.io/badge/SPM-compatible-4BC51D.svg?style=flat)](https://swift.org/package-manager/)
[![MIT license](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/rkreutz/web3.vapor/blob/master/LICENSE)
[![Swift 5.5](https://img.shields.io/badge/Swift-5.5-brightgreen.svg)](http://swift.org)
[![Vapor 4](https://img.shields.io/badge/Vapor-4-e040fb.svg)](https://vapor.codes)
[![codebeat badge](https://codebeat.co/badges/17a02a88-9a1c-471f-9c55-762007e5a4cf)](https://codebeat.co/projects/github-com-rkreutz-web3-vapor-main)


Integrates [web3.swift](https://github.com/argentlabs/web3.swift) into Vapor and provide some utilities around Web3 on you server.

## Installation

Add the package declaration to your project's manifest dependencies array:

```swift
.package(url: "https://github.com/rkreutz/web3.vapor.git", from: "0.1.0")
```

Then add the library to the dependencies array of any target you want to access the module in:

```swift
.product(name: "web3.vapor", package: "web3.vapor"),
```

## Usage

### Accessing `EthereumClient`s

First, make sure to register an `EthereumClient` configuration somewhere in `configure(_:)` method:
```swift
public func configure(_ app: Application) throws {
    app.ethereumClients.use("<RPC_URL>", for: .mainnet, isDefault: true)
    app.ethereumClients.use("<RPC_URL>", for: .ropsten)
    ...
}
```

You can then access registered `EthereumClient`s from an `Application` or `Request` instance:
```swift
let client = app.ethereumClient // Retrieves default client
let ropstenClient = app.ethereumClient(for: .ropsten)
let unregisteredClient = app.ethereumClient(for: 12345) // nil since it was registered using use(_:for:isDefault)
```

Optionally these methods can all be accessed through `EthereumClients` service, like:
```swift
let client = app.ethereumClients.ethereumClient
let ropstenClient = app.ethereumClients.ethereumClient(for: .ropsten)
app.ethereumClients.default(to: .ropsten) // Changes default EthereumClient
app.ethereumClients.ids() // A list of all the registered clients
```

### Web3 Authentication using Sign-In with Ethereum (SIWE)

Sign-In with Ethereum ([EIP-4361](https://eips.ethereum.org/EIPS/eip-4361)) is a new form of authentication that enables users to control their digital identity with their Ethereum account.

To start using SIWE in your Vapor instance first you must register some `EthereumClient`s on your `Application` instance.

Then you must have a `Model` conforming to `Web3ModelAuthenticatable`, this is very similar to `Fluent`s `ModelAuthenticatable`.

The only requirement is for the model to provide a keypath to where the user's address is stored in the model, so we can login a user purely through their EVM address.
```swift
public protocol Web3ModelAuthenticatable: Model, Authenticatable {
    static var web3AddressKey: KeyPath<Self, Field<String>> { get }
}
```

With a model conforming to `Web3ModelAuthenticatable` we can now access the authenticator for that given model and pass it along in routes:
```swift
func routes(_ app: Application) throws {
    let api = app.grouped("api")
    let siwe = api.grouped(
        User.web3Authenticator(
            delegate: Web3AuthenticatorDelegate.shared, // optional delegate
            database: nil, // identifier of the database where your users are stored
            unsupportedNetworkError: Abort( // Error to be thrown in case a sign in request came from a network the server don't have clients for
                .badRequest,
                reason: "Unsupported network please use either one of these chain IDs: \(app.ethereumClients.ids())"
            )
        )
    )

    siwe.post("login") { req in
        let user = req.auth.require(User.self)
        return "Welcome \(user.name)"
    }
}

private class Web3AuthenticatorDelegate: Web3AuthenticationDelegate {
    let shared = Web3AuthenticatorDelegate()

    func verify(message: SiweMessage, in request: Request) async throws -> Bool {
        // Additional business related checks can be done here prior to authenticating the user,
        // at this point we have already validated the message's signature
        // but you might block the user from logging in if some property in the
        // message is not what you had expected it to be.

        // Returning false will prevent the user from logging in
        guard message.domain == "mydomain.com" else { return false }

        // Returning true will allow the login to proceed
        return true
    }

    func didLogin(with message: SiweMessage, signature: String, in request: Request) async throws {
        // This is the opportunity to make any cleanup after the user has successfully logged in (like invalidating nonces), or maybe save the signature as proof of acknowledgement of TnC
        try await request.nonces.invalidate(id: message.nonce)
    }
}
```

The expected payload for SIWE is:
```json
{
    "message": "mydomain.com wants you to sign in with your.....", // String the user has signed
    "signature": "0x00000000...." // The signature of the user
}
```