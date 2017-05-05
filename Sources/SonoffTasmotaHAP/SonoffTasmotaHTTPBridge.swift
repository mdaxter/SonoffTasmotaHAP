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
    public let urlBases: [String]
    public let user: String
    public let password: String
    let bag: DisposeBag
    let urlSession: URLSession
    public init<S: Sequence>(devices: S, user name: String = "admin", password p: String) where S.Iterator.Element == String {
        user = name
        password = p
        urlBases = devices.map { "http://\($0)/cm?user=\(name)&password=\(p)&cmnd=" }
        urlSession = URLSession(configuration: URLSessionConfiguration.default)
        bag = DisposeBag()
    }

    /// Asynchronously send a command
    ///
    /// - Parameters:
    ///   - command: the command to send (defaults to `Status`)
    ///   - parameter: the parameter for the command (e.g. `On`)
    ///   - accessories: devices to use (defaults to `nil`, which is `0..<accessories.count`)
    ///   - processEvents: callback to process events
    public func send(command: String = "Status", payload parameter: String? = nil, accessories accs: Range<Int>? = nil, _ processEvents: @escaping (JSONDictionary?) -> Void) {
        let range: Range<Int>
        if let r = accs { range = r }
        else { range = 0..<urlBases.count }
        let payload = parameter == nil ? "" : "%20\(parameter!)"
        let urls = urlBases[range].map { URL(string: "\($0)\(command)\(payload)") }.filter { $0 != nil }.map { $0! }
        let response = Observable.from(urls)
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
    /// - Parameters:
    ///   - accs: devices to use (defaults to `nil`, which is `0..<accessories.count`)
    ///   - processEvents: callback to process asynchronous network status responses
    public func retrieveNetworkStatus(forAccessories accs: Range<Int>? = nil, _ processEvents: @escaping (JSONDictionary?) -> Void) {
        send(command: "Status", payload: "5", accessories: accs) {
            let status = $0.flatMap { $0["StatusNET"] }.flatMap { $0 as? JSONDictionary }
            processEvents(status)
        }
    }

    /// Retrieve the IP address of the given device
    ///
    /// - Parameters:
    ///   - accessory: device to retrieve IP address for
    ///   - processEvents: callback to process asynchronous IP addresses
    public func retrieveIP(forAccessory accessory: Int, _ processEvents: @escaping (String) -> Void) {
        retrieveNetworkStatus(forAccessories: accessory..<accessory+1) {
            let ip = $0?["IP"] as? String ?? ""
            processEvents(ip)
        }
    }
}
