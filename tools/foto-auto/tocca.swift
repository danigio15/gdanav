// Le foto dello schermo dell'auto fatte dalla CI (foto-auto.yml): trova una
// scritta in una foto e tocca lo schermo del Mac.
//
//   swift tocca.swift trova <foto.png> <scritta>   → «x y» da 0 a 1, dall'alto a sinistra
//   swift tocca.swift clic <x> <y>                 → un clic, in punti dello schermo
//   swift tocca.swift schermo                      → «larghezza altezza» in punti
//
// Le scritte lette finiscono su stderr, per capire dai log cosa c'era.
import AppKit
import Foundation
import Vision

let argomenti = CommandLine.arguments.dropFirst()

func esci(_ messaggio: String) -> Never {
    FileHandle.standardError.write((messaggio + "\n").data(using: .utf8)!)
    exit(1)
}

switch argomenti.first {
case "trova":
    let a = Array(argomenti)
    guard a.count >= 3 else { esci("trova <foto> <scritta>") }
    guard let immagine = NSImage(contentsOfFile: a[1]),
          let cg = immagine.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else { esci("foto illeggibile: \(a[1])") }
    let cercata = a[2].lowercased()
    let richiesta = VNRecognizeTextRequest()
    richiesta.recognitionLevel = .accurate
    richiesta.usesLanguageCorrection = false
    try VNImageRequestHandler(cgImage: cg).perform([richiesta])
    var trovata: CGRect?
    for r in richiesta.results ?? [] {
        guard let t = r.topCandidates(1).first else { continue }
        FileHandle.standardError.write("letto: \(t.string) \(r.boundingBox)\n".data(using: .utf8)!)
        if trovata == nil, t.string.lowercased().contains(cercata) { trovata = r.boundingBox }
    }
    guard let b = trovata else { esci("«\(a[2])» non c'è") }
    // Vision conta dal basso; lo schermo dall'alto.
    print(String(format: "%.4f %.4f", b.midX, 1 - b.midY))
case "clic":
    let a = Array(argomenti)
    guard a.count >= 3, let x = Double(a[1]), let y = Double(a[2]) else { esci("clic <x> <y>") }
    let p = CGPoint(x: x, y: y)
    for tipo in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
        CGEvent(mouseEventSource: nil, mouseType: tipo, mouseCursorPosition: p, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        usleep(120_000)
    }
case "schermo":
    guard let s = NSScreen.main?.frame else { esci("nessuno schermo") }
    print("\(Int(s.width)) \(Int(s.height))")
default:
    esci("trova | clic | schermo")
}
