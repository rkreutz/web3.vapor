import Foundation
import Fluent
import Vapor
import web3

public protocol Web3ModelAuthenticatable: Model, Authenticatable {
    static var web3AddressKey: KeyPath<Self, Field<String>> { get }
}

public protocol Web3AuthenticationDelegate {
    func verify(message: SiweMessage, in request: Request) async throws -> Bool
    func didLogin(with message: SiweMessage, signature: String, in request: Request) async throws
}

extension Web3ModelAuthenticatable {
    public static func web3Authenticator(
        delegate: Web3AuthenticationDelegate? = nil,
        database: DatabaseID? = nil,
        unsupportedNetworkError: Error = Abort(
            .badRequest,
            reason: "Unsupported network.",
            identifier: "Web3Vapor.unsupportedNetwork",
            suggestedFixes: [
                "Change wallet network to one of the supported networks."
            ]
        )
    ) -> AsyncAuthenticator {
        Web3ModelAuthenticator<Self>(delegate: delegate, database: database, unsupportedNetworkError: unsupportedNetworkError)
    }

    var _$address: Field<String> {
        self[keyPath: Self.web3AddressKey]
    }
}

private struct Web3ModelAuthenticator<User: Web3ModelAuthenticatable>: AsyncRequestAuthenticator {
    let delegate: Web3AuthenticationDelegate?
    let database: DatabaseID?
    let unsupportedNetworkError: Error

    private struct SignInRequest: Content {
        enum CodingKeys: CodingKey {
            case message
            case signature
        }

        var message: SiweMessage
        var signature: String

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.message = try SiweMessage(container.decode(String.self, forKey: .message))
            self.signature = try container.decode(String.self, forKey: .signature)
        }
    }

    func authenticate(request: Request) async throws {
        guard let signInRequest = try? request.content.decode(SignInRequest.self) else { return }
        let (message, signature) = (signInRequest.message, signInRequest.signature)

        guard let ethereumClient = request.ethereumClient(for: message.chainId) else { throw unsupportedNetworkError }

        guard
            case let verifier = SiweVerifier(client: ethereumClient),
            try await verifier.verify(message: message, against: signature)
        else { return }

        guard try await delegate?.verify(message: message, in: request) != false else { return }

        let user = try await User.query(on: request.db(database))
            .filter(\._$address == message.address)
            .first()

        if let user = user {
            request.auth.login(user)
        } else {
            let user = User()
            user._$address.value = message.address
            try await user.create(on: request.db(database))
        }
        try await delegate?.didLogin(with: message, signature: signature, in: request)
    }
}

