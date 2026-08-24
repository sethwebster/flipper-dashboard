import Darwin
import Foundation

public protocol FlipperCommanding: AnyObject {
    func command(_ command: String, timeout: TimeInterval) throws -> String
}

public enum FlipperSerialError: LocalizedError {
    case noDevice
    case multipleDevices([String])
    case systemCall(operation: String, code: Int32)
    case timeout(command: String)
    case rejected(String)

    public var errorDescription: String? {
        switch self {
        case .noDevice:
            return "Connect the Flipper Zero over USB"
        case let .multipleDevices(ports):
            return "Multiple Flippers found: \(ports.joined(separator: ", "))"
        case let .systemCall(operation, code):
            return "\(operation) failed: \(String(cString: strerror(code)))"
        case let .timeout(command):
            return "The Flipper timed out while running \"\(command)\""
        case let .rejected(message):
            return message
        }
    }
}

public final class FlipperSerialSession: FlipperCommanding {
    public let port: String

    private let descriptor: Int32
    private let prompt = Data(">: ".utf8)

    public init() throws {
        port = try Self.findPort()
        descriptor = Darwin.open(port, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard descriptor >= 0 else {
            throw FlipperSerialError.systemCall(operation: "Opening \(port)", code: errno)
        }

        do {
            guard ioctl(descriptor, TIOCEXCL) == 0 else {
                throw FlipperSerialError.systemCall(operation: "Locking \(port)", code: errno)
            }
            try configureSerialPort()
            try write("\r")
            _ = try readUntilPrompt(command: "connecting", timeout: 5)
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    deinit {
        Darwin.close(descriptor)
    }

    public func command(_ command: String, timeout: TimeInterval = 10) throws -> String {
        tcflush(descriptor, TCIFLUSH)
        try write(command + "\r")
        let data = try readUntilPrompt(command: command, timeout: timeout)
        return String(decoding: data, as: UTF8.self)
    }

    private static func findPort() throws -> String {
        if let configuredPort = ProcessInfo.processInfo.environment["FLIPPER_PORT"] {
            guard FileManager.default.fileExists(atPath: configuredPort) else {
                throw FlipperSerialError.noDevice
            }
            return configuredPort
        }

        let deviceNames = try FileManager.default.contentsOfDirectory(atPath: "/dev")
        let ports = deviceNames
            .filter { $0.hasPrefix("cu.usbmodemflip_") }
            .map { "/dev/\($0)" }
            .sorted()

        guard let port = ports.first else {
            throw FlipperSerialError.noDevice
        }
        guard ports.count == 1 else {
            throw FlipperSerialError.multipleDevices(ports)
        }
        return port
    }

    private func configureSerialPort() throws {
        var configuration = termios()
        guard tcgetattr(descriptor, &configuration) == 0 else {
            throw FlipperSerialError.systemCall(operation: "Reading serial settings", code: errno)
        }

        cfmakeraw(&configuration)
        guard cfsetspeed(&configuration, speed_t(B115200)) == 0 else {
            throw FlipperSerialError.systemCall(operation: "Setting serial speed", code: errno)
        }
        configuration.c_cflag |= tcflag_t(CLOCAL | CREAD | CS8)

        guard tcsetattr(descriptor, TCSANOW, &configuration) == 0 else {
            throw FlipperSerialError.systemCall(operation: "Configuring serial port", code: errno)
        }
        tcflush(descriptor, TCIOFLUSH)
    }

    private func write(_ text: String) throws {
        let bytes = Array(text.utf8)
        var written = 0

        while written < bytes.count {
            let result = bytes.withUnsafeBytes { buffer -> Int in
                guard let baseAddress = buffer.baseAddress else {
                    return 0
                }
                return Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: written),
                    bytes.count - written
                )
            }

            if result > 0 {
                written += result
            } else if result < 0, errno == EAGAIN || errno == EINTR {
                usleep(10_000)
            } else {
                throw FlipperSerialError.systemCall(operation: "Writing to Flipper", code: errno)
            }
        }
    }

    private func readUntilPrompt(command: String, timeout: TimeInterval) throws -> Data {
        let deadline = Date().addingTimeInterval(timeout)
        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)

        while Date() < deadline {
            let remaining = max(0, deadline.timeIntervalSinceNow)
            let timeoutMilliseconds = Int32(min(250, remaining * 1_000))
            var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let pollResult = Darwin.poll(&pollDescriptor, 1, timeoutMilliseconds)

            if pollResult < 0 {
                if errno == EINTR {
                    continue
                }
                throw FlipperSerialError.systemCall(operation: "Polling Flipper", code: errno)
            }
            if pollResult == 0 {
                continue
            }

            let count = buffer.withUnsafeMutableBytes { rawBuffer in
                Darwin.read(descriptor, rawBuffer.baseAddress, rawBuffer.count)
            }

            if count > 0 {
                response.append(contentsOf: buffer.prefix(count))
                if response.suffix(prompt.count) == prompt {
                    return response
                }
            } else if count < 0, errno != EAGAIN, errno != EINTR {
                throw FlipperSerialError.systemCall(operation: "Reading from Flipper", code: errno)
            }
        }

        throw FlipperSerialError.timeout(command: command)
    }
}
