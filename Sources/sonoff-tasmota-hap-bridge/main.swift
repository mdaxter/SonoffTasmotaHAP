import Foundation
import Evergreen
import HAP
import RxSwift
import SonoffTasmotaHAP

#if os(macOS)
    import Darwin
#elseif os(Linux)
    import Glibc
    import Dispatch
#endif

let args = CommandLine.arguments
let cmd = args[0]
let base = with(cString: cmd) { String(cString: basename($0)) }
var bridgeName = base
var logLevel = LogLevel.warning

var longopts: [option] = [
    option(name: "debug",           has_arg: 0, flag: nil, val: Int32("d".utf16.first!)),
    option(name: "file-storage",    has_arg: 1, flag: nil, val: Int32("f".utf16.first!)),
    option(name: "name",            has_arg: 1, flag: nil, val: Int32("n".utf16.first!)),
    option(name: "password",        has_arg: 1, flag: nil, val: Int32("p".utf16.first!)),
    option(name: "quiet",           has_arg: 0, flag: nil, val: Int32("q".utf16.first!)),
    option(name: "recreate",        has_arg: 0, flag: nil, val: Int32("r".utf16.first!)),
    option(name: "secret",          has_arg: 1, flag: nil, val: Int32("s".utf16.first!)),
    option(name: "username",        has_arg: 1, flag: nil, val: Int32("u".utf16.first!)),
    option(name: "verbose",         has_arg: 0, flag: nil, val: Int32("v".utf16.first!)),
]

fileprivate func usage() -> Never {
    print("Usage: \(cmd) <options> [devices ...]")
    print("Options:")
    print("  -d, --debug:               print debug output")
    print("  -f, --file-storage=<file>: file storage path for persistent data")
    print("  -n, --name=<bridge-name>:  bridge name [\(base)]")
    print("  -p, --pin=<PIN>:           HomeKit PIN for authentication [123-44-321]")
    print("  -q, --quiet:               turn off all non-critical logging output")
    print("  -r, --recreate:            drop and rebuild all pairings")
    print("  -s, --secret=<pwd>:        secret password for authentication")
    print("  -u, --username=<user>:     user name for authentication [admin]")
    print("  -v, --verbose:             increase logging verbosity")
    exit(EXIT_FAILURE)
}

let fileManager = FileManager.default
var username = "admin"
var password = ""
var pin = "123-44-321"
var recreateDB = false
var fileStoragePath = try! fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent(base).path
while let option = get(options: "df:n:p:qrs:u:v") {
    switch option {
    case "d": logLevel        = .debug
    case "f": fileStoragePath = String(cString: optarg)
    case "n": bridgeName      = String(cString: optarg)
    case "p": pin             = String(cString: optarg)
    case "q": logLevel        = .critical
    case "r": recreateDB      = true
    case "s": password        = String(cString: optarg)
    case "u": username        = String(cString: optarg)
    case "v": let ll = logLevel.rawValue ; logLevel = LogLevel(rawValue: ll-1) ?? .all
    default: usage()
    }
}

fileprivate let logger = getLogger(Logger.KeyPath(string: base))
logger.logLevel = logLevel
getLogger("hap").logLevel = logLevel
getLogger("hap.encryption").logLevel = logLevel
getLogger("hap.pair-verify").logLevel = logLevel

let rebuiltStorage = recreateDB || !fileManager.fileExists(atPath: fileStoragePath)
let storage = try FileStorage(path: fileStoragePath)
if recreateDB {
    logger.info("Dropping all pairings, keys")
    try storage.removeAll()
}

let hostnames = Array(args[Int(optind)..<args.count])
let queues = hostnames.map { DispatchQueue(label: $0, qos: .utility) }
var names = hostnames.map { $0.components(separatedBy: ".").first ?? $0 }
var ips = names.enumerated().map { storage[$0.element] ?? hostnames[$0.offset] }
var temperatures = names.map { storage[$0 + ".temperature"].flatMap { Double($0) } }
var humidities = names.map { storage[$0 + ".humidity"].flatMap { Double($0) } }
let lights = names.map { $0.localizedCaseInsensitiveContains("light") }
let sonoffs = ips.map { SonoffTasmotaHTTPBridge(device: $0, user: username, password: password) }
let update = names.enumerated().map { (i: Int, name: String) -> (TasmotaDictionary?) -> Void in {
        guard let dictionary = $0 else { return }
        let hostname = hostnames[i]
        let status = dictionary.status
        let net = dictionary.networkStatus
        let ip = net.ipAddress
        let friendlyName = status.friendlyName
        let sensors = dictionary.sensorStatus
        let am2301 = sensors.am2301
        DispatchQueue.main.async {
            if !friendlyName.isEmpty && friendlyName != names[i] {
                names[i] = friendlyName
                logger.info("Updated Friendly name to '\(friendlyName)' for \(hostname)")
            }
            if !ip.isEmpty && ip != ips[i] {
                logger.info("Updating IP \(ip) (from \(ips[i])) for \(name)")
                ips[i] = ip
                storage[name] = ip
            }
            if let temperature = am2301.temperature, temperature != temperatures[i] {
                temperatures[i] = temperature
                storage[name + ".temperature"] = temperature
                logger.debug("Updated temperature to \(temperature)°C for \(name)")
            }
            if let humidity = am2301.humidity, humidity != humidities[i] {
                humidities[i] = humidity
                storage[name + ".humidity"] = humidity
                logger.debug("Updated humidity to \(humidity) %rel for \(name)")
            }
        }
    }
}
for i in 0..<ips.count {
    sonoffs[i].updateStatus(update[i])
}
let getNamedOnOff: (String) -> (TasmotaDictionary?) -> Bool? = { name in {
    guard let dictionary = $0, let result = dictionary["POWER"] as? String else {
        logger.warning("\(name): Unsuccessful retrieving power value from \(String(describing: $0))")
        return nil
    }
    logger.debug("\(name) changed to value: \(result)")
    return result == "ON"
}}

if rebuiltStorage { RunLoop.main.run(until: Date(timeIntervalSinceNow: 10)) }

let accessories = names.enumerated().map { (i: Int, name: String) -> Accessory in
    let serviceInfo = Service.Info(name: name)
    let accessory: Accessory
    let setOnOff: (Bool?) -> Void = {
        logger.verbose("\(name) changing value: \(String(describing: $0))")
        guard let value = $0 else { return }
        sonoffs[i].send(command: "Power", payload: value ? "On" : "Off") {
            guard let dictionary = $0, let result = dictionary["POWER"] else {
                logger.warning("\(name): Unsuccessful setting value \(value)")
                return
            }
            logger.debug("\(name) changed to value: \(result)")
        }
    }
    let getOnOff = getNamedOnOff(name)
    if lights[i] {
        if let temperature = temperatures[i] {
            let a = Accessory.THLight(info: serviceInfo)
            a.temperature.currentTemperature.value = temperature
            if let humidity = humidities[i] {
                a.humidity.currentRelativeHumidity.value = humidity
            }
            accessory = a
        } else {
            accessory = Accessory.Lightbulb(info: serviceInfo)
        }
        let l = accessory as! Lightbulb
        l.lightbulb.on.onValueChange.append(setOnOff)
        sonoffs[i].send(command: "Power") {
            guard let value = getOnOff($0) else { return }
            DispatchQueue.main.async { l.lightbulb.on.value = value }
        }
    } else {
        if let temperature = temperatures[i] {
            let a = Accessory.THOutlet(info: serviceInfo)
            a.temperature.currentTemperature.value = temperature
            if let humidity = humidities[i] {
                a.humidity.currentRelativeHumidity.value = humidity
            }
            accessory = a
        } else {
            accessory = Accessory.Outlet(info: serviceInfo)
        }
        let o = accessory as! Outlet
        o.outlet.on.onValueChange.append(setOnOff)
        sonoffs[i].send(command: "Power") {
            guard let value = getOnOff($0) else { return }
            DispatchQueue.main.async { o.outlet.on.value = value }
        }
    }
    return accessory
}

let timers = names.enumerated().map { (i: Int, name: String) -> DispatchSourceTimer in
    let accessory = accessories[i]
    let getOnOff = getNamedOnOff(name)
    let timer = DispatchSource.makeTimerSource()
    timer.scheduleRepeating(deadline: .now() + .seconds(i+20), interval: 20)
    timer.setEventHandler {
        sonoffs[i].updateStatus {
            update[i]($0)
            DispatchQueue.main.async {
                if let temperature = temperatures[i], let sensor = accessory as? Thermometer {
                    if temperature != sensor.temperature.currentTemperature.value {
                        sensor.temperature.currentTemperature.value = temperature
                    }
                }
                if let humidity = humidities[i], let sensor = accessory as? Hygrometer {
                    if humidity != sensor.humidity.currentRelativeHumidity.value {
                        sensor.humidity.currentRelativeHumidity.value = humidity
                    }
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
            sonoffs[i].send(command: "Power") {
                guard let value = getOnOff($0) else { return }
                DispatchQueue.main.async {
                    if let l = accessory as? Lightbulb {
                        l.lightbulb.on.value = value
                    }
                    if let o = accessory as? Outlet {
                        o.outlet.on.value = value
                    }
                }
            }
        }
    }
    timer.resume()
    return timer
}

let device = Device(name: bridgeName, pin: pin, storage: storage, accessories: accessories)
device.onIdentify.append {
    guard let accessory = $0 else {
        logger.warning("Bridge '\(bridgeName)' was identified")
        return
    }
    guard let i = accessories.index(where: { $0 === accessory }) else {
        logger.warning("Unknown accessory \(accessory) for \(bridgeName)")
        return
    }
    let name = names[i]
    if let l = accessory as? Lightbulb {
        logger.warning("Blinking \(name)")
        let value = l.lightbulb.on.value ?? false
        sonoffs[i].send(command: "Power", payload: !value ? "On" : "Off") {
            guard let dictionary = $0, let result = dictionary["POWER"] else {
                logger.warning("\(name): Unsuccessful setting value \(!value)")
                return
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500)) {
            sonoffs[i].send(command: "Power", payload: value ? "On" : "Off") {
                guard let dictionary = $0, let result = dictionary["POWER"] else {
                    logger.warning("\(name): Unsuccessful setting value \(value)")
                    return
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500)) {
                sonoffs[i].send(command: "Power", payload: !value ? "On" : "Off") {
                    guard let dictionary = $0, let result = dictionary["POWER"] else {
                        logger.warning("\(name): Unsuccessful setting value \(!value)")
                        return
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500)) {
                    sonoffs[i].send(command: "Power", payload: value ? "On" : "Off") {
                        guard let dictionary = $0, let result = dictionary["POWER"] else {
                            logger.warning("\(name): Unsuccessful setting value \(value)")
                            return
                        }
                    }
                }
            }
        }
    } else if let o = accessory as? Outlet {
        logger.warning("Identified outlet \(name)")
    } else {
        logger.warning("Identified unknown accessory \(i): \(name)")
    }
}

var keepRunning = true
signal(SIGINT) { _ in
    DispatchQueue.main.async {
        keepRunning = false
        logger.info("Caught interrupt, stopping...")
    }
}

let server = try Server(device: device, port: 0)
server.start()

while keepRunning {
    RunLoop.current.run(until: Date().addingTimeInterval(2))
}

server.stop()
logger.info("Stopped")
