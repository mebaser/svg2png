//
//  svg2png — SVG 를 PNG 로 변환하는 명령줄 도구
//
//  WebKit(WKWebView) 로 렌더링하므로 CSS·필터·그라디언트·웹폰트·내장 이미지 등
//  SVG 사양 전반을 Safari 와 동일한 품질로 처리한다. 외부 의존성이 없다.
//

import Cocoa
import WebKit
import ImageIO
import UniformTypeIdentifiers

let kVersion = "1.0.0"

// MARK: - 출력

var gQuiet = false
var gPorcelain = false

func say(_ s: String) {
    guard !gQuiet, !gPorcelain else { return }
    FileHandle.standardOutput.write((s + "\n").data(using: .utf8)!)
}

func emit(_ s: String) {
    FileHandle.standardOutput.write((s + "\n").data(using: .utf8)!)
}

func warn(_ s: String) {
    FileHandle.standardError.write((s + "\n").data(using: .utf8)!)
}

let gDebug = ProcessInfo.processInfo.environment["SVG2PNG_DEBUG"] != nil
func dbg(_ s: String) {
    guard gDebug else { return }
    FileHandle.standardError.write(("[svg2png] " + s + "\n").data(using: .utf8)!)
}

// MARK: - 옵션

struct Options {
    var inputs: [URL] = []
    var scale: Double = 2
    var width: Int? = nil
    var height: Int? = nil
    var maxSide: Int? = nil
    var background: CGColor? = nil      // nil = 투명
    var output: String? = nil
    var force = false
    var timeout: Double = 45
}

let usage = """
svg2png \(kVersion) — SVG → PNG 변환기

사용법:
  svg2png [옵션] <파일.svg> [파일2.svg ...]

크기 옵션 (하나만 지정, 지정 없으면 --scale 2):
  -s, --scale <배율>       원본 크기의 배수로 출력. 예: -s 3
  -w, --width <픽셀>       가로를 이 크기로. 세로는 비율 유지
  -H, --height <픽셀>      세로를 이 크기로. 가로는 비율 유지
  -m, --max <픽셀>         긴 변을 이 크기에 맞춤

기타:
  -b, --background <색>    배경색. 기본은 투명.
                           #RGB · #RRGGBB · #RRGGBBAA · white · black · transparent
  -o, --output <경로>      출력 파일 경로(입력 1개일 때) 또는 출력 폴더
  -f, --force              같은 이름이 있으면 덮어씀 (기본: name-1.png 로 저장)
      --timeout <초>       파일당 최대 대기 시간. 기본 45
      --porcelain          기계 판독용 출력 (탭 구분)
  -q, --quiet              조용히
  -v, --version            버전 출력
  -h, --help               이 도움말

예시:
  svg2png logo.svg                    # logo.png 를 2배 크기로
  svg2png -w 1024 icon.svg            # 가로 1024px
  svg2png -b white -s 1 *.svg         # 흰 배경, 원본 크기로 일괄 변환
"""

func parseColor(_ raw: String) -> CGColor?? {
    let s = raw.trimmingCharacters(in: .whitespaces).lowercased()
    if s == "transparent" || s == "none" || s == "clear" { return .some(nil) }

    let named: [String: (Double, Double, Double)] = [
        "white": (1, 1, 1), "black": (0, 0, 0), "red": (1, 0, 0), "green": (0, 0.5, 0),
        "blue": (0, 0, 1), "gray": (0.5, 0.5, 0.5), "grey": (0.5, 0.5, 0.5),
    ]
    if let c = named[s] {
        return .some(CGColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1))
    }

    var hex = s.hasPrefix("#") ? String(s.dropFirst()) : s
    if hex.count == 3 || hex.count == 4 {                       // #RGB / #RGBA 확장
        hex = hex.map { "\($0)\($0)" }.joined()
    }
    guard hex.count == 6 || hex.count == 8,
          hex.allSatisfy({ $0.isHexDigit }),
          let v = UInt64(hex, radix: 16) else { return nil }     // nil = 파싱 실패

    let hasAlpha = hex.count == 8
    let r = Double((v >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
    let g = Double((v >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
    let b = Double((v >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
    let a = hasAlpha ? Double(v & 0xFF) / 255 : 1
    return .some(CGColor(srgbRed: r, green: g, blue: b, alpha: a))
}

func parseArgs() -> Options {
    var o = Options()
    var args = Array(CommandLine.arguments.dropFirst())
    var sizeFlagsUsed: [String] = []

    func next(_ flag: String) -> String {
        guard !args.isEmpty else {
            warn("오류: \(flag) 에 값이 필요합니다.")
            exit(2)
        }
        return args.removeFirst()
    }
    func intVal(_ flag: String) -> Int {
        let raw = next(flag)
        guard let n = Int(raw), n > 0 else {
            warn("오류: \(flag) 값은 1 이상의 정수여야 합니다. (받은 값: \(raw))")
            exit(2)
        }
        return n
    }

    while !args.isEmpty {
        let a = args.removeFirst()
        switch a {
        case "-h", "--help":
            print(usage); exit(0)
        case "-v", "--version":
            print(kVersion); exit(0)
        case "-q", "--quiet":
            gQuiet = true
        case "--porcelain":
            gPorcelain = true
        case "-f", "--force":
            o.force = true
        case "-s", "--scale":
            sizeFlagsUsed.append(a)
            let raw = next(a)
            guard let d = Double(raw), d > 0, d <= 100 else {
                warn("오류: --scale 값은 0 초과 100 이하의 수여야 합니다. (받은 값: \(raw))")
                exit(2)
            }
            o.scale = d
        case "-w", "--width":
            sizeFlagsUsed.append(a); o.width = intVal(a)
        case "-H", "--height":
            sizeFlagsUsed.append(a); o.height = intVal(a)
        case "-m", "--max":
            sizeFlagsUsed.append(a); o.maxSide = intVal(a)
        case "-b", "--background":
            let raw = next(a)
            guard let parsed = parseColor(raw) else {
                warn("오류: 색을 해석할 수 없습니다: \(raw)")
                exit(2)
            }
            o.background = parsed
        case "-o", "--output":
            o.output = next(a)
        case "--timeout":
            let raw = next(a)
            guard let d = Double(raw), d > 0 else {
                warn("오류: --timeout 값이 올바르지 않습니다. (받은 값: \(raw))")
                exit(2)
            }
            o.timeout = d
        case "--":
            o.inputs += args.map { URL(fileURLWithPath: $0) }; args = []
        default:
            if a.hasPrefix("-") && a.count > 1 {
                warn("오류: 알 수 없는 옵션 \(a)\n\n\(usage)")
                exit(2)
            }
            o.inputs.append(URL(fileURLWithPath: a))
        }
    }

    // --scale 은 기본값이므로, 다른 크기 옵션과 함께 쓰지 않은 경우에만 충돌로 본다.
    let explicitSize = sizeFlagsUsed.filter { $0 != "-s" && $0 != "--scale" }
    if explicitSize.count > 1 {
        warn("오류: 크기 옵션은 하나만 지정할 수 있습니다. (\(explicitSize.joined(separator: ", ")))")
        exit(2)
    }
    if o.inputs.isEmpty {
        warn(usage)
        exit(2)
    }
    if o.inputs.count > 1, let out = o.output {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: out, isDirectory: &isDir)
        if exists && !isDir.boolValue {
            warn("오류: 입력이 여러 개일 때 --output 은 폴더여야 합니다.")
            exit(2)
        }
    }
    return o
}

// MARK: - 결과

struct Outcome {
    let input: URL
    let output: URL?
    let pixels: (Int, Int)?
    let error: String?
}

// MARK: - 렌더러

final class Renderer: NSObject, WKNavigationDelegate {

    private let opts: Options
    private var queue: [URL]
    private var outcomes: [Outcome] = []
    private let window: NSWindow
    private var webView: WKWebView!
    private var current: URL!
    private var timeoutItem: DispatchWorkItem?
    private var settled = false          // 파일 하나당 한 번만 마무리되도록 보장

    init(options: Options) {
        self.opts = options
        self.queue = options.inputs
        // 화면 밖에 둔 보이지 않는 창. WebKit 은 창에 붙어 있어야 실제로 그린다.
        self.window = NSWindow(contentRect: NSRect(x: -30000, y: -30000, width: 1024, height: 1024),
                               styleMask: [.borderless], backing: .buffered, defer: false)
        super.init()
        window.isReleasedWhenClosed = false
        window.orderBack(nil)
    }

    func run() { startNext() }

    // MARK: 큐 진행

    private func startNext() {
        guard !queue.isEmpty else { return finishAll() }
        current = queue.removeFirst()
        settled = false

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: current.path, isDirectory: &isDir), !isDir.boolValue else {
            return settle(error: "파일을 찾을 수 없습니다")
        }
        guard FileManager.default.isReadableFile(atPath: current.path) else {
            return settle(error: "파일을 읽을 권한이 없습니다")
        }

        // 파일마다 새 WebView 를 만든다. 한 파일이 WebContent 프로세스를 죽여도
        // 다음 파일이 영향을 받지 않는다.
        let cfg = WKWebViewConfiguration()
        cfg.suppressesIncrementalRendering = true
        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 1024, height: 1024), configuration: cfg)
        if wv.responds(to: NSSelectorFromString("_setDrawsBackground:"))
            || wv.responds(to: NSSelectorFromString("setDrawsBackground:")) {
            wv.setValue(false, forKey: "drawsBackground")       // 페이지 기본 흰 배경 제거
        }
        wv.underPageBackgroundColor = .clear
        wv.navigationDelegate = self
        webView = wv
        window.contentView = wv

        let item = DispatchWorkItem { [weak self] in
            self?.settle(error: "시간 초과 (\(Int(self?.opts.timeout ?? 0))초)")
        }
        timeoutItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + opts.timeout, execute: item)

        dbg("load 시작: \(current.lastPathComponent)")
        wv.loadFileURL(current, allowingReadAccessTo: current.deletingLastPathComponent())
    }

    private func settle(error: String) {
        guard !settled else { return }
        settled = true
        timeoutItem?.cancel(); timeoutItem = nil
        webView?.navigationDelegate = nil
        outcomes.append(Outcome(input: current, output: nil, pixels: nil, error: error))
        DispatchQueue.main.async { [weak self] in self?.startNext() }
    }

    private func settle(output: URL, pixels: (Int, Int)) {
        guard !settled else { return }
        settled = true
        timeoutItem?.cancel(); timeoutItem = nil
        webView?.navigationDelegate = nil
        outcomes.append(Outcome(input: current, output: output, pixels: pixels, error: nil))
        DispatchQueue.main.async { [weak self] in self?.startNext() }
    }

    // MARK: WKNavigationDelegate

    func webView(_ wv: WKWebView, didFinish nav: WKNavigation!) {
        dbg("didFinish")
        measure(wv)
    }

    func webView(_ wv: WKWebView, didFail nav: WKNavigation!, withError e: Error) {
        settle(error: "읽기 실패: \(e.localizedDescription)")
    }

    func webView(_ wv: WKWebView, didFailProvisionalNavigation nav: WKNavigation!, withError e: Error) {
        settle(error: "읽기 실패: \(e.localizedDescription)")
    }

    func webViewWebContentProcessDidTerminate(_ wv: WKWebView) {
        settle(error: "렌더링 엔진이 종료되었습니다 (SVG 가 너무 크거나 손상됨)")
    }

    // MARK: 1단계 — 원본 크기 측정

    private static let measureJS = """
    const s = document.documentElement;
    if (!s || String(s.tagName).toLowerCase() !== 'svg') {
      return { ok: false, err: 'SVG 문서가 아닙니다' };
    }
    const PERCENT = 2;                       // SVGLength.SVG_LENGTHTYPE_PERCENTAGE
    const len = (a) => {
      try {
        if (!a || !a.baseVal) return 0;
        // 퍼센트 단위는 뷰포트에 의존하므로 고유 크기로 쓸 수 없다.
        if (a.baseVal.unitType === PERCENT || a.baseVal.unitType === 0) return 0;
        const v = a.baseVal.value;
        return (isFinite(v) && v > 0) ? v : 0;
      } catch (e) { return 0; }
    };
    let vbw = 0, vbh = 0;
    try {
      const vb = s.viewBox && s.viewBox.baseVal;
      if (vb && isFinite(vb.width) && isFinite(vb.height) && vb.width > 0 && vb.height > 0) {
        vbw = vb.width; vbh = vb.height;
      }
    } catch (e) {}
    let bw = 0, bh = 0;
    try {
      const b = s.getBBox();
      if (isFinite(b.width) && isFinite(b.height)) {
        bw = b.width + Math.max(0, b.x);
        bh = b.height + Math.max(0, b.y);
      }
    } catch (e) {}
    return {
      ok: true,
      w: len(s.width), h: len(s.height),
      vbw: vbw, vbh: vbh, bw: bw, bh: bh,
      hasViewBox: !!s.getAttribute('viewBox')
    };
    """

    private func measure(_ wv: WKWebView) {
        dbg("measure JS 호출")
        wv.callAsyncJavaScript(Self.measureJS, arguments: [:], in: nil, in: .page) { [weak self] result in
            guard let self else { return }
            dbg("measure JS 반환: \(result)")
            switch result {
            case .failure(let e):
                self.settle(error: "측정 실패: \(e.localizedDescription)")
            case .success(let value):
                guard let d = value as? [String: Any], (d["ok"] as? Bool) == true else {
                    let msg = (value as? [String: Any])?["err"] as? String ?? "SVG 를 해석할 수 없습니다"
                    return self.settle(error: msg)
                }
                let num = { (k: String) -> Double in (d[k] as? NSNumber)?.doubleValue ?? 0 }
                let intrinsic = Self.intrinsicSize(w: num("w"), h: num("h"),
                                                   vbw: num("vbw"), vbh: num("vbh"),
                                                   bw: num("bw"), bh: num("bh"))
                let hasViewBox = (d["hasViewBox"] as? Bool) ?? false
                self.render(wv, intrinsic: intrinsic, hasViewBox: hasViewBox)
            }
        }
    }

    /// width/height · viewBox · 실제 내용 경계를 순서대로 살펴 원본 크기를 정한다.
    static func intrinsicSize(w: Double, h: Double, vbw: Double, vbh: Double,
                              bw: Double, bh: Double) -> (Double, Double) {
        let vbAspect = (vbw > 0 && vbh > 0) ? vbw / vbh : nil
        if w > 0 && h > 0 { return (w, h) }
        if w > 0, let ar = vbAspect { return (w, w / ar) }
        if h > 0, let ar = vbAspect { return (h * ar, h) }
        if vbw > 0 && vbh > 0 { return (vbw, vbh) }
        if w > 0 && h <= 0 { return (w, w) }
        if h > 0 && w <= 0 { return (h, h) }
        if bw > 0 && bh > 0 { return (bw, bh) }
        return (512, 512)                                   // 아무 단서도 없을 때
    }

    /// 옵션에 따라 실제 출력 픽셀 크기를 정한다. 비율은 항상 유지된다.
    static func targetSize(intrinsic: (Double, Double), opts: Options) -> (Int, Int) {
        let (iw, ih) = intrinsic
        let ar = iw / ih
        var tw: Double, th: Double
        if let w = opts.width {
            tw = Double(w); th = Double(w) / ar
        } else if let h = opts.height {
            th = Double(h); tw = Double(h) * ar
        } else if let m = opts.maxSide {
            if iw >= ih { tw = Double(m); th = Double(m) / ar }
            else { th = Double(m); tw = Double(m) * ar }
        } else {
            tw = iw * opts.scale; th = ih * opts.scale
        }
        // 지나치게 큰 출력은 메모리를 폭발시키므로 잘라낸다.
        let cap = 20000.0
        if tw > cap || th > cap {
            let k = min(cap / tw, cap / th)
            tw *= k; th *= k
        }
        return (max(1, Int(tw.rounded())), max(1, Int(th.rounded())))
    }

    // MARK: 2단계 — 뷰포트에 맞춰 늘린 뒤 스냅샷

    private static let fitJS = """
    const s = document.documentElement;
    if (!s.getAttribute('viewBox') && vb) s.setAttribute('viewBox', vb);
    s.setAttribute('width', '100%');
    s.setAttribute('height', '100%');
    s.style.width = '100%';
    s.style.height = '100%';
    s.style.margin = '0';
    s.style.padding = '0';
    s.style.background = 'transparent';
    // 화면 밖 창에서는 requestAnimationFrame 이 발화하지 않으므로 쓰지 않는다.
    // 폰트가 준비되기를 기다린 뒤, 크기를 읽어 동기 레이아웃을 강제한다.
    try { if (document.fonts && document.fonts.ready) await document.fonts.ready; } catch (e) {}
    const r = s.getBoundingClientRect();
    return { w: r.width, h: r.height };
    """

    private func render(_ wv: WKWebView, intrinsic: (Double, Double), hasViewBox: Bool) {
        let (tw, th) = Self.targetSize(intrinsic: intrinsic, opts: opts)

        // 창의 backing scale 만큼 픽셀이 늘어나므로, 포인트 크기를 그만큼 나눠
        // 스냅샷 픽셀이 목표 크기에 정확히 떨어지게 한다.
        let bsf = max(1.0, window.backingScaleFactor)
        let pw = Double(tw) / bsf, ph = Double(th) / bsf
        window.setContentSize(NSSize(width: pw, height: ph))
        wv.frame = NSRect(x: 0, y: 0, width: pw, height: ph)

        dbg("목표 크기 \(tw)x\(th), bsf=\(bsf)")
        let vb = hasViewBox ? "" : "0 0 \(intrinsic.0) \(intrinsic.1)"
        wv.callAsyncJavaScript(Self.fitJS, arguments: ["vb": vb], in: nil, in: .page) { [weak self] result in
            guard let self else { return }
            if case .failure(let e) = result {
                return self.settle(error: "레이아웃 실패: \(e.localizedDescription)")
            }
            dbg("fit JS 완료: \(result)")
            dbg("fit JS 완료, 스냅샷 시작")
            let cfg = WKSnapshotConfiguration()
            cfg.rect = wv.bounds
            cfg.afterScreenUpdates = true
            wv.takeSnapshot(with: cfg) { [weak self] image, err in
                guard let self else { return }
                guard let image,
                      let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    return self.settle(error: "화면 캡처 실패: \(err?.localizedDescription ?? "알 수 없음")")
                }
                dbg("스냅샷 완료 \(cg.width)x\(cg.height)")
                self.write(cg, target: (tw, th), intrinsic: intrinsic)
            }
        }
    }

    // MARK: 3단계 — 정확한 크기·색공간으로 다시 그린 뒤 PNG 로 저장

    private func write(_ snapshot: CGImage, target: (Int, Int), intrinsic: (Double, Double)) {
        let (tw, th) = target
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: tw, height: th, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return settle(error: "이미지 버퍼를 만들 수 없습니다 (\(tw)×\(th))")
        }
        ctx.interpolationQuality = .high
        let rect = CGRect(x: 0, y: 0, width: tw, height: th)
        if let bg = opts.background {
            ctx.setFillColor(bg)
            ctx.fill(rect)
        }
        ctx.draw(snapshot, in: rect)
        guard let final = ctx.makeImage() else {
            return settle(error: "이미지를 만들 수 없습니다")
        }

        let dest: URL
        do { dest = try resolveOutput(for: current) }
        catch { return settle(error: (error as? RuntimeError)?.message ?? "출력 경로 오류") }

        guard let sink = CGImageDestinationCreateWithURL(dest as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            return settle(error: "저장할 수 없습니다: \(dest.path)")
        }
        // 원본과 실제 물리 크기가 같도록 DPI 를 기록해 둔다.
        let dpi = 72.0 * (Double(tw) / max(1, intrinsic.0))
        let props: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi,
        ]
        CGImageDestinationAddImage(sink, final, props as CFDictionary)
        guard CGImageDestinationFinalize(sink) else {
            return settle(error: "PNG 쓰기에 실패했습니다: \(dest.path)")
        }
        settle(output: dest, pixels: (tw, th))
    }

    struct RuntimeError: Error { let message: String }

    private func resolveOutput(for input: URL) throws -> URL {
        let fm = FileManager.default
        var base: URL

        if let out = opts.output {
            let u = URL(fileURLWithPath: (out as NSString).expandingTildeInPath)
            var isDir: ObjCBool = false
            let exists = fm.fileExists(atPath: u.path, isDirectory: &isDir)
            if (exists && isDir.boolValue) || opts.inputs.count > 1 {
                if !exists {
                    try? fm.createDirectory(at: u, withIntermediateDirectories: true)
                }
                base = u.appendingPathComponent(input.deletingPathExtension().lastPathComponent + ".png")
            } else {
                base = u.pathExtension.lowercased() == "png" ? u : u.appendingPathExtension("png")
            }
        } else {
            base = input.deletingPathExtension().appendingPathExtension("png")
        }

        let dir = base.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        guard fm.isWritableFile(atPath: dir.path) else {
            throw RuntimeError(message: "폴더에 쓸 권한이 없습니다: \(dir.path)")
        }
        if opts.force || !fm.fileExists(atPath: base.path) { return base }

        // 덮어쓰지 않고 name-1.png, name-2.png … 로 비켜 간다.
        let stem = base.deletingPathExtension().lastPathComponent
        for i in 1...999 {
            let candidate = dir.appendingPathComponent("\(stem)-\(i).png")
            if !fm.fileExists(atPath: candidate.path) { return candidate }
        }
        throw RuntimeError(message: "사용할 수 있는 파일 이름을 찾지 못했습니다")
    }

    // MARK: 마무리

    private func finishAll() {
        let ok = outcomes.filter { $0.error == nil }
        let failed = outcomes.filter { $0.error != nil }

        if gPorcelain {
            for r in outcomes {
                if let e = r.error {
                    emit("FAIL\t\(r.input.path)\t\(e)")
                } else {
                    emit("OK\t\(r.input.path)\t\(r.output!.path)\t\(r.pixels!.0)x\(r.pixels!.1)")
                }
            }
        } else {
            for r in ok {
                say("✓ \(r.input.lastPathComponent) → \(r.output!.lastPathComponent)  (\(r.pixels!.0)×\(r.pixels!.1))")
            }
            for r in failed {
                warn("✗ \(r.input.lastPathComponent): \(r.error!)")
            }
            if outcomes.count > 1 {
                say("\n완료: 성공 \(ok.count)개, 실패 \(failed.count)개")
            }
        }
        exit(failed.isEmpty ? 0 : 1)
    }
}

// MARK: - 진입점

let options = parseArgs()

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)        // Dock 아이콘·메뉴막대 없이 조용히 동작

let renderer = Renderer(options: options)
DispatchQueue.main.async { renderer.run() }
app.run()
