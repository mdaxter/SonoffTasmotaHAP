//
//  SonoffTasmotaHTTPBridge
//  SonoffTasmotaHAP
//
import Foundation
import RxSwift
import RxCocoa
import Dispatch

public typealias JSONDictionary = [String: Any]
public typealias TasmotaDictionary = JSONDictionary

public extension Dictionary where Dictionary.Key == String {
    public var ipAddress:       String { return self["IP"]                  as? String ?? "" }
    public var friendlyName:    String { return self["FriendlyName"]        as? String ?? "" }
    public var ssid:            String { return self["SSID"]                as? String ?? "" }
    public var apMac:           String { return self["APMac"]               as? String ?? "" }
    public var accessPoint:     Int?   { return self["AP"]                  as? Int }
    public var rssi:            Int?   { return self["RSSI"]                as? Int }
    public var module:          Int?   { return self["Module"]              as? Int }
    public var upTime:          Int?   { return self["Uptime"]              as? Int }
    public var vcc:             Double?{ return self["Vcc"]                 as? Double }
    public var temperature:     Double?{ return self["Temperature"]         as? Double }
    public var humidity:        Double?{ return self["Humidity"]            as? Double }
    public var status:          JSONDictionary { return self["Status"]      as? JSONDictionary ?? [:] }
    public var networkStatus:   JSONDictionary { return self["StatusNET"]   as? JSONDictionary ?? [:] }
    public var sensorStatus:    JSONDictionary { return self["StatusSNS"]   as? JSONDictionary ?? [:] }
    public var systemStatus:    JSONDictionary { return self["StatusSTS"]   as? JSONDictionary ?? [:] }
    public var wifi:            JSONDictionary { return self["Wifi"]        as? JSONDictionary ?? [:] }
    public var am2301:          JSONDictionary { return self["AM2301"]      as? JSONDictionary ?? [:] }
}

/// Sonoff Tasmota HTTP Bridge
public class SonoffTasmotaHTTPBridge {
    public let urlBase: String
    public let user: String
    public let password: String
    public var status: TasmotaDictionary?
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
    public func send(command: String = "Status", payload parameter: String? = nil, _ processEvents: @escaping (TasmotaDictionary?) -> Void) {
        let payload = parameter == nil ? "" : "%20\(parameter!)"
        guard let url = URL(string: "\(urlBase)\(command)\(payload)") else { return }
        let maxAttempts = 3
        let response = Observable.from([url])
            .map { URLRequest(url: $0) }
            .flatMap {
                self.urlSession.rx.response(request: $0).retryWhen {
                    $0.flatMapWithIndex { (e, a) -> Observable<Int> in
                        let doneRetrying = a > maxAttempts
                        DispatchQueue.main.async {
                            fputs("\(url) error: \(e) -- attempt \(a) - \(doneRetrying ? "retrying" : "giving up")\n", stderr)
                        }
                        return doneRetrying ? Observable.error(e) :
                            Observable<Int>.timer(Double(a * 2 + 1), scheduler: MainScheduler.instance)
                            .take(1)
                    }
                }
            }
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
                guard let response = String(data: $1, encoding: e) else { return nil }
                let results = NSString(string: response).components(separatedBy: .newlines)
                let rv = results.reduce(TasmotaDictionary()) { (dict: TasmotaDictionary, result: String) -> TasmotaDictionary in
                    let components = result.components(separatedBy: "=").map { $0.trimmingCharacters(in: .whitespaces) }
                    guard components.count > 1 else { return dict }
                    var d = dict
                    guard let data = components[1].data(using: .utf8),
                          let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
                          let dictionary = jsonObject as? TasmotaDictionary else {
                            d[components[0]] = components[1]
                            return d
                    }
                    d[components[0]] = dictionary
                    for (key, value) in dictionary {
                        d[key] = value
                    }
                    return d
                }
                return rv
            }
            .subscribe(onNext: { processEvents($0) })
            .addDisposableTo(bag)
    }

    /// Retrieve the status from a Tasmota device
    ///
    /// - Parameters processEvents: callback to process asynchronous network status responses
    public func retrieveStatus(_ number: String? = nil, key: String = "Status", _ processEvents: @escaping (TasmotaDictionary?) -> Void) {
        send(command: "Status", payload: number) {
            let status = $0.flatMap { $0[key] }.flatMap { $0 as? JSONDictionary }
            processEvents(status)
        }
    }

    /// Update the status cache
    ///
    /// - Parameter processEvents: callback when results are received
    public func updateStatus(_ processEvents: @escaping (TasmotaDictionary?) -> Void = { _ in }) {
        send(command: "Status", payload: "0") {
            if let dictionary = $0 { self.status = dictionary }
            processEvents($0)
        }
    }
    
    /// Retrieve the network status (STATUS5) from a Tasmota device
    ///
    /// - Parameters processEvents: callback to process asynchronous network status responses
    public func retrieveNetworkStatus(_ processEvents: @escaping (TasmotaDictionary?) -> Void) {
        retrieveStatus("5", key: "StatusNET", processEvents)
    }

    /// Retrieve the IP address of the given device
    ///
    /// - Parameter processEvents: callback to process asynchronous IP addresses
    public func retrieveIP(_ processEvents: @escaping (String) -> Void) {
        retrieveNetworkStatus {
            let ip = $0?.ipAddress ?? ""
            processEvents(ip)
        }
    }
    
    /// Retrieve the human-readable name of the given device
    ///
    /// - Parameter processEvents: callback to process asynchronous responses
    public func retrieveFriendlyName(_ processEvents: @escaping (String) -> Void) {
        retrieveStatus {
            let ip = $0?.friendlyName ?? ""
            processEvents(ip)
        }
    }
}
