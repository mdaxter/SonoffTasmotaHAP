//
//  SonoffTasmotaHTTPBridge
//  SonoffTasmotaHAP
//
import Foundation
import RxSwift
import RxCocoa

public typealias JSONDictionary = [String: Any]

/// Sonoff Tasmota HTTP Bridge
public class SonoffTasmotaHTTPBridge {
    public let urlBase: String
    public let user: String
    public let password: String
    let bag: DisposeBag
    let urlSession: URLSession
    public init(device: String, user name: String = "admin", password p: String) {
        user = name
        password = p
        urlBase = "http://\(device)/cm?user=\(name)&password=\(p)&cmnd="
        urlSession = URLSession(configuration: URLSessionConfiguration.default)
        bag = DisposeBag()
    }

    /// Asynchronously send a command
    ///
    /// - Parameters:
    ///   - command: the command to send (defaults to `Status`)
    ///   - parameter: the parameter for the command (e.g. `On`)
    ///   - processEvents: callback to process events
    public func send(command: String = "Status", payload parameter: String? = nil, _ processEvents: @escaping (JSONDictionary?) -> Void) {
        let payload = parameter == nil ? "" : "%20\(parameter!)"
        guard let url = URL(string: "\(urlBase)\(command)\(payload)") else { return }
        let response = Observable.from([url])
            .map { URLRequest(url: $0) }
            .flatMap { self.urlSession.rx.response(request: $0) }
        //.shareReplay(1)

        response.filter { 200..<300 ~= $0.0.statusCode }
            .map {
                #if os(macOS)
                    let e = $0.textEncodingName.map {
                        String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringConvertIANACharSetNameToEncoding($0 as CFString)))
                    } ?? String.Encoding.utf8
                #else
                    let e = String.Encoding.utf8
                #endif
                guard let response = String(data: $1, encoding: e),
                      let result = NSString(string: response).components(separatedBy: .newlines).first?.components(separatedBy: "=").last?.trimmingCharacters(in: .whitespaces),
                      let data = result.data(using: .utf8),
                      let jsonObject = try? JSONSerialization.jsonObject(with: data, options:  []),
                      let dictionary = jsonObject as? JSONDictionary else { return nil }
                return dictionary
            }
            .subscribe(onNext: { processEvents($0) })
            .addDisposableTo(bag)
    }

    /// Retrieve the network status (STATUS5) from a Tasmota device
    ///
    /// - Parameters processEvents: callback to process asynchronous network status responses
    public func retrieveNetworkStatus(_ processEvents: @escaping (JSONDictionary?) -> Void) {
        send(command: "Status", payload: "5") {
            let status = $0.flatMap { $0["StatusNET"] }.flatMap { $0 as? JSONDictionary }
            processEvents(status)
        }
    }

    /// Retrieve the IP address of the given device
    ///
    /// - Parameter processEvents: callback to process asynchronous IP addresses
    public func retrieveIP(_ processEvents: @escaping (String) -> Void) {
        retrieveNetworkStatus {
            let ip = $0?["IP"] as? String ?? ""
            processEvents(ip)
        }
    }
}
