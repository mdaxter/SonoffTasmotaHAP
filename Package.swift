// swift-tools-version:3.1

import PackageDescription

let package = Package(
    name: "SonoffTasmotaHAP",
    targets: [
        Target(name: "SonoffTasmotaHAP", dependencies: []),
        Target(name: "sonoff-tasmota-hap-bridge", dependencies: ["SonoffTasmotaHAP"]),
    ],
    dependencies: [
        .Package(url: "https://github.com/Bouke/HAP.git", majorVersion: 0),
    ]
)
