//
//  SonoffTHAccessory.swift
//  SonoffTasmotaHAP
//
import HAP

public protocol Lightbulb {
    var lightbulb: Service.Lightbulb { get }
}

public protocol Outlet {
    var outlet: Service.Outlet { get }
}

public protocol Thermometer {
    var temperature: Service.TemperatureSensor { get }
}

public protocol Hygrometer {
    var humidity: Service.HumiditySensor { get }
}

extension Accessory {
    open class THLight: Accessory {
        public let lightbulb = Service.Lightbulb()
        public let temperature = Service.TemperatureSensor()
        public let humidity = Service.HumiditySensor()

        public init(info: Service.Info) {
            super.init(info: info, type: .lightbulb, services: [lightbulb, temperature, humidity])
        }
    }

    open class THOutlet: Accessory {
        public let outlet = Service.Outlet()
        public let temperature = Service.TemperatureSensor()
        public let humidity = Service.HumiditySensor()

        public init(info: Service.Info) {
            super.init(info: info, type: .outlet, services: [outlet, temperature, humidity])
        }
    }
}

extension Accessory.Lightbulb: Lightbulb {}
extension Accessory.THLight: Lightbulb, Thermometer, Hygrometer {}

extension Accessory.Outlet: Outlet {}
extension Accessory.THOutlet: Outlet, Thermometer, Hygrometer {}
