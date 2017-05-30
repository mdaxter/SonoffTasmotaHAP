# SonoffTasmotaHAP

A [HAP](https://github.com/Bouke/HAP) bridge for [Sonoff](https://www.itead.cc/smart-home.html) devices running [Tasmota](https://github.com/arendst/Sonoff-Tasmota).

## Usage
```
Usage: \(cmd) <options> [devices ...]
    Options:
      -d, --debug:               print debug output
      -f, --file-storage=<file>: file storage path for persistent data
      -n, --name=<bridge-name>:  bridge name [\(base)]
      -p, --pin=<PIN>:           HomeKit PIN for authentication [123-44-321]
      -q, --quiet:               turn off all non-critical logging output
      -r, --recreate:            drop and rebuild all pairings
      -s, --secret=<pwd>:        secret password for authentication
      -u, --username=<user>:     user name for authentication [admin]
      -v, --verbose:             increase logging verbosity
```

### Example

The following invocation creates a bridge named `SonoffBridge` (with the pin `987-65-432`) that connects to two devices (`lights.local` and `power.local`) using the password `TopSecret`:
```
sonoff-tasmota-hap-bridge -p 987-65-432 -s TopSecret -n SonoffBridge lights.local power.local
```

## Pre-requisites

For this project to work, you need a working Swift 3 installation, including the Swift Package Manager.

## Building

To compile using the Swift Package manager, clone this repository, then (from inside the cloned folder) run
```
swift build -c release
```