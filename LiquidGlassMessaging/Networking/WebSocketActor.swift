import Foundation

/// Swift Actor managing URLSessionWebSocketTask with automatic reconnection, heartbeat pings,
/// and asynchronous event streaming.
public actor WebSocketActor {
    // MARK: - State Properties
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession
    private var serverURL: URL?
    private var authToken: String?
    public private(set) var roundTripMs = 0
    private var currentUser: UserProfile?
    
    public enum ConnectionState: Sendable, Equatable {
        case disconnected
        case connecting
        case connected
        case reconnecting(attempt: Int)
    }
    
    public private(set) var state: ConnectionState = .disconnected
    private var isIntentionallyDisconnected: Bool = false
    
    // Exponential backoff parameters
    private var reconnectAttempt: Int = 0
    private let maxReconnectInterval: TimeInterval = 30.0
    private let baseReconnectInterval: TimeInterval = 1.0
    
    // Heartbeat timer task
    private var pingTask: Task<Void, Never>?
    private var receiveLoopTask: Task<Void, Never>?
    
    // AsyncStream continuation for outward subscribers
    private var eventContinuations: [UUID: AsyncStream<ServerMessageEnvelope>.Continuation] = [:]
    
    // MARK: - Initialization
    public init(configuration: URLSessionConfiguration = .default) {
        self.urlSession = URLSession(configuration: configuration)
    }
    
    // MARK: - Public Subscription
    
    /// Provides a continuous stream of decoded server messages.
    public func eventStream() -> AsyncStream<ServerMessageEnvelope> {
        let id = UUID()
        return AsyncStream { continuation in
            continuation.onTermination = { [weak self] _ in
                Task { [weak self] in
                    await self?.removeContinuation(id: id)
                }
            }
            self.eventContinuations[id] = continuation
        }
    }
    
    private func removeContinuation(id: UUID) {
        eventContinuations.removeValue(forKey: id)
    }
    
    private func broadcast(_ envelope: ServerMessageEnvelope) {
        for continuation in eventContinuations.values {
            continuation.yield(envelope)
        }
    }
    
    // MARK: - Connection Management
    
    /// Connects to the real-time WebSocket server.
    public func connect(url: URL, token: String?, user: UserProfile? = nil) {
        disconnect()
        self.serverURL = url
        self.authToken = token
        self.currentUser = user
        self.isIntentionallyDisconnected = false
        self.reconnectAttempt = 0
        
        initiateSocketConnection()
    }
    
    /// Gracefully closes connection.
    public func disconnect() {
        self.isIntentionallyDisconnected = true
        self.state = .disconnected
        self.pingTask?.cancel()
        self.pingTask = nil
        self.receiveLoopTask?.cancel()
        self.receiveLoopTask = nil
        
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
    }
    
    private func initiateSocketConnection() {
        guard let serverURL, !isIntentionallyDisconnected, webSocketTask == nil else { return }
        
        self.state = reconnectAttempt > 0 ? .reconnecting(attempt: reconnectAttempt) : .connecting
        
        var request = URLRequest(url: serverURL)
        request.timeoutInterval = 15
        if let authToken {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
        
        let task = urlSession.webSocketTask(with: request)
        self.webSocketTask = task
        task.resume()
        
        startReceiveLoop()
        startHeartbeat()
        
        // Authenticate immediately upon socket connect
        if let authToken {
            let authEnvelope = ClientMessageEnvelope(type: .auth, token: authToken)
            Task {
                try? await self.send(envelope: authEnvelope)
            }
        }
        

    }
    
    // MARK: - Outbound Transmission
    
    /// Sends a strongly-typed client message envelope.
    public func send(envelope: ClientMessageEnvelope) async throws {
        guard let webSocketTask, state == .connected || envelope.type == .auth else {
            throw URLError(.notConnectedToInternet)
        }
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(envelope)
        let message = URLSessionWebSocketTask.Message.data(data)
        
        try await webSocketTask.send(message)
    }
    
    // MARK: - Inbound Receive Loop
    
    private func startReceiveLoop() {
        receiveLoopTask?.cancel()
        receiveLoopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }
                do {
                    guard let task = await self.webSocketTask else { break }
                    let message = try await task.receive()
                    await self.processIncoming(message: message)
                } catch {
                    if !Task.isCancelled {
                        await self.handleConnectionFailure(error: error)
                    }
                    break
                }
            }
        }
    }
    
    private func processIncoming(message: URLSessionWebSocketTask.Message) {
        let decoder = AccountCodec.decoder()
        
        do {
            let envelope: ServerMessageEnvelope
            switch message {
            case .data(let data):
                envelope = try decoder.decode(ServerMessageEnvelope.self, from: data)
            case .string(let text):
                guard let data = text.data(using: .utf8) else { return }
                envelope = try decoder.decode(ServerMessageEnvelope.self, from: data)
            @unknown default:
                return
            }
            if envelope.type == .authenticated { state = .connected; reconnectAttempt = 0 }
            if envelope.type == .error, let reason = envelope.reason,
               reason.lowercased().contains("session") || reason == "Authentication required" {
                isIntentionallyDisconnected = true
            }
            broadcast(envelope)
        } catch {
            print("Failed to decode server WebSocket message: \(error)")
        }
    }
    
    // MARK: - Ping / Pong Heartbeat
    
    private func startHeartbeat() {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 25 * 1_000_000_000)
                guard let self = self else { break }
                
                await self.sendPing()
            }
        }
    }
    
    private func sendPing() {
        guard let webSocketTask, state == .connected else { return }
        let started = Date()
        webSocketTask.sendPing { [weak self] error in
            Task { [weak self] in
                if let error { await self?.handleConnectionFailure(error: error) }
                else { await self?.recordPing(Int(Date().timeIntervalSince(started) * 1000)) }
            }
        }
    }
    
    private func recordPing(_ value: Int) { roundTripMs = max(0, value) }

    // MARK: - Reconnection Logic with Exponential Backoff
    
    private func handleConnectionFailure(error: Error) {
        guard !isIntentionallyDisconnected else { return }
        
        pingTask?.cancel()
        pingTask = nil
        receiveLoopTask?.cancel()
        receiveLoopTask = nil
        webSocketTask = nil
        
        reconnectAttempt += 1
        
        let delayFactor = pow(2.0, Double(min(reconnectAttempt, 5)))
        let jitter = Double.random(in: 0.1...0.5)
        let calculatedInterval = min((baseReconnectInterval * delayFactor) + jitter, maxReconnectInterval)
        
        state = .reconnecting(attempt: reconnectAttempt)
        
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(calculatedInterval * 1_000_000_000))
            await self?.initiateSocketConnection()
        }
    }
}
