import Foundation
import Vapor
import web3

public typealias EthereumClientID = Int

public extension EthereumClientID {
    static let mainnet = 1
    static let ropsten = 3
    static let rinkeby = 4
    static let goerli = 5
    static let sepolia = 11155111
}

public struct EthereumClientConfiguration {
    var rpc: URL
}

extension EthereumClientConfiguration: ExpressibleByStringLiteral {
    public typealias StringLiteralType = String

    public init(stringLiteral: StringLiteralType) {
        guard let url = URL(string: stringLiteral) else {
            fatalError("Invalid RPC url")
        }
        self.init(rpc: url)
    }
}

public struct EthereumClients {
    let app: Application

    public func use(
        _ configuration: EthereumClientConfiguration,
        for id: EthereumClientID,
        isDefault: Bool? = nil
    ) {
        self.storage.lock.lock()
        defer { self.storage.lock.unlock() }
        self.storage.configurations[id] = configuration
        self.storage.clients.removeValue(forKey: id)
        if isDefault == true || (self.storage.defaultID == nil && isDefault != false) {
            self.storage.defaultID = id
        }
    }

    public func ethereumClient(
        _ id: EthereumClientID? = nil,
        logger: Logger
    ) -> EthereumClientProtocol? {
        self.storage.lock.lock()
        defer { self.storage.lock.unlock() }
        let id = id ?? self._requireDefaultID()
        if let client = self.storage.clients[id] { return client }
        var clientLogger = logger
        clientLogger[metadataKey: "ethereum-client-id"] = .string("\(id)")
        guard let configuration = self.storage.configurations[id] else { return nil }
        let client = EthereumHttpClient(
            url: configuration.rpc,
            logger: clientLogger,
            network: .init(intValue: id)
        )
        self.storage.clients[id] = client
        return client
    }

    public func `default`(to id: EthereumClientID) {
        self.storage.lock.lock()
        defer { self.storage.lock.unlock() }
        self.storage.defaultID = id
    }

    public func ids() -> Set<EthereumClientID> {
        return self.storage.lock.withLock { Set(self.storage.configurations.keys) }
    }

    private final class Storage {
        var configurations: [EthereumClientID: EthereumClientConfiguration] = [:]
        var clients: [EthereumClientID: EthereumClientProtocol] = [:]
        var defaultID: EthereumClientID?
        var lock: Lock = .init()
    }

    private struct Key: StorageKey {
        typealias Value = Storage
    }

    private var storage: Storage {
        if app.storage[Key.self] == nil {
            app.storage[Key.self] = .init()
        }

        return app.storage[Key.self].unsafelyUnwrapped
    }

    private func _requireDefaultID() -> EthereumClientID {
        guard let id = self.storage.defaultID else {
            fatalError("No default EVM client configured.")
        }
        return id
    }
}

public extension Application {
    var ethereumClients: EthereumClients {
        EthereumClients(app: self)
    }

    var ethereumClient: EthereumClientProtocol {
        guard let client = ethereumClients.ethereumClient(nil, logger: self.logger) else {
            fatalError("No Ethereum client configured, use app.ethereumClients.use()")
        }
        return client
    }

    func ethereumClient(for networkId: EthereumClientID) -> EthereumClientProtocol? {
        ethereumClients.ethereumClient(networkId, logger: self.logger)
    }
}

public extension Request {
    var ethereumClients: EthereumClients {
        EthereumClients(app: self.application)
    }

    var ethereumClient: EthereumClientProtocol {
        guard let client = ethereumClients.ethereumClient(nil, logger: self.logger) else {
            fatalError("No Ethereum client configured, use app.ethereumClients.use()")
        }
        return client
    }

    func ethereumClient(for networkId: EthereumClientID) -> EthereumClientProtocol? {
        ethereumClients.ethereumClient(networkId, logger: self.logger)
    }
}

private extension EthereumNetwork {
    init(intValue: Int) {
        switch intValue {
        case 1:
            self = .mainnet
        case 3:
            self = .ropsten
        case 4:
            self = .rinkeby
        case 5:
            self = .goerli
        case 42:
            self = .kovan
        case 11155111:
            self = .sepolia
        default:
            self = .custom("\(intValue)")
        }
    }
}
