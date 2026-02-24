import Foundation
import NetFS

class NetworkShareMonitor {
    private let mountPath: String
    private let shareURL: String
    private let keychainAccount: String
    private let maxAttempts: Int

    private var pollTimer: DispatchSourceTimer?
    private var isReconnecting = false
    private var reconnectAttempt = 0

    var onDisconnected: (() -> Void)?
    var onReconnected: (() -> Void)?
    var onReconnectFailed: ((String) -> Void)?

    init(mountPath: String, config: NetworkShareConfig) {
        self.mountPath = mountPath
        self.shareURL = config.serverURL
        self.keychainAccount = config.keychainAccount
        self.maxAttempts = config.maxReconnectAttempts
    }

    func startMonitoring() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now(), repeating: .seconds(5))
        timer.setEventHandler { [weak self] in self?.checkMount() }
        timer.resume()
        pollTimer = timer
    }

    func stopMonitoring() {
        pollTimer?.cancel()
        pollTimer = nil
    }

    private func checkMount() {
        let mounted = FileManager.default.fileExists(atPath: mountPath)
        if !mounted {
            if !isReconnecting {
                isReconnecting = true
                reconnectAttempt = 0
                onDisconnected?()
                attemptReconnect()
            }
        } else if isReconnecting {
            isReconnecting = false
            reconnectAttempt = 0
            onReconnected?()
        }
    }

    private func attemptReconnect() {
        guard reconnectAttempt < maxAttempts else {
            onReconnectFailed?("Failed after \(maxAttempts) attempts")
            return
        }
        reconnectAttempt += 1
        let delay = min(5.0 * pow(2.0, Double(reconnectAttempt - 1)), 120.0)
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.mountShare()
        }
    }

    private func mountShare() {
        guard let url = URL(string: shareURL) as CFURL? else {
            onReconnectFailed?("Invalid share URL")
            return
        }
        let server = URL(string: shareURL)?.host ?? ""
        let password = KeychainService.shared.retrieve(account: keychainAccount, server: server)

        var requestID: AsyncRequestID?
        NetFSMountURLAsync(
            url, nil,
            keychainAccount as CFString,
            (password ?? "") as CFString,
            nil, nil,
            &requestID,
            DispatchQueue.global()
        ) { [weak self] status, _, _ in
            if status == 0 {
                // Poll timer will detect reconnection
            } else {
                self?.attemptReconnect()
            }
        }
    }
}
