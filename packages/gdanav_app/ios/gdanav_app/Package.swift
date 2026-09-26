// swift-tools-version: 5.9

import PackageDescription

// Il pezzo nativo di gdanav su iPhone: i permessi Bluetooth per il dongle
// OBD e CarPlay, con la stessa mappa MapLibre del telefono. Lo portano
// dentro sia l'app gdanav sia gdahome.
let package = Package(
    name: "gdanav_app",
    platforms: [
        .iOS("15.0"),
    ],
    products: [
        .library(name: "gdanav-app", targets: ["gdanav_app"])
    ],
    dependencies: [
        // La stessa versione di maplibre_gl (vedi il suo Package.swift): due
        // versioni diverse nella stessa app non si possono avere.
        .package(url: "https://github.com/maplibre/maplibre-gl-native-distribution.git", exact: "6.28.0"),
    ],
    targets: [
        .target(
            name: "gdanav_app",
            dependencies: [
                .product(name: "MapLibre", package: "maplibre-gl-native-distribution")
            ]
        )
    ]
)
