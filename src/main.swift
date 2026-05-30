import Cocoa
import WebKit

func escapeJS(_ val: String) -> String {
    return val
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\'", with: "\\'")
        .replacingOccurrences(of: "\n", with: "\\n")
        .replacingOccurrences(of: "\r", with: "\\r")
}

class TitlebarDragView: NSView {
    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        if loc.x < 80 {
            super.mouseDown(with: event)
            return
        }
        if event.clickCount == 2 {
            window?.zoom(nil)
        } else {
            window?.performDrag(with: event)
        }
    }
}

class LauncherController: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    var webView: WKWebView!
    var window: NSWindow!

    func getLauncherDir() -> URL {
        let fileManager = FileManager.default
        let homeDir = fileManager.homeDirectoryForCurrentUser
        let dir = homeDir.appendingPathComponent("Library/Application Support/TiwutLauncher")
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        return dir
    }

    func start() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        let windowStyle: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1024, height: 768),
                          styleMask: windowStyle,
                          backing: .buffered,
                          defer: false)
        window.title = "Tiwut Launcher"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.center()

        window.backgroundColor = .clear
        window.isOpaque = false
        window.isMovableByWindowBackground = true

        let configuration = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        contentController.add(self, name: "rpc")
        configuration.userContentController = contentController

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")

        guard let contentView = window.contentView else { return }

        let visualEffectView = NSVisualEffectView(frame: contentView.bounds)
        visualEffectView.autoresizingMask = [.width, .height]
        visualEffectView.state = .active
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow

        contentView.addSubview(visualEffectView)

        webView.frame = contentView.bounds
        webView.autoresizingMask = [.width, .height]
        contentView.addSubview(webView)

        let dragView = TitlebarDragView(frame: NSRect(x: 0, y: contentView.bounds.height - 48, width: contentView.bounds.width, height: 48))
        dragView.autoresizingMask = [.width, .minYMargin]
        contentView.addSubview(dragView, positioned: .above, relativeTo: webView)

        setAppMenu()

        let indexURL = resolveIndexURL()
        if let url = indexURL {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {

            let errorHTML = """
            <html>
                <body style="background:#0f172a; color:#f3f4f6; font-family:sans-serif; text-align:center; padding:100px;">
                    <h1>Tiwut Launcher Error</h1>
                    <p>Could not locate the frontend file: 'src/index.html'</p>
                </body>
            </html>
            """
            webView.loadHTMLString(errorHTML, baseURL: nil)
        }

        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        app.run()
    }

    func resolveIndexURL() -> URL? {
        let fileManager = FileManager.default
        let exeDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()

        let lookupPaths = [
            exeDir.appendingPathComponent("src/index.html"),
            exeDir.appendingPathComponent("index.html"),
            URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent("src/index.html"),
            URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent("index.html"),
            URL(fileURLWithPath: "/Users/tiwut/Documents/dev/Tiwut Launcher/src/index.html")
        ]

        for url in lookupPaths {
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    func evalJS(_ js: String) {
        DispatchQueue.main.async {
            self.webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "rpc",
              let body = message.body as? [String: Any],
              let seq = body["seq"] as? String,
              let functionName = body["functionName"] as? String else {
            return
        }

        let req = body["req"] as? String ?? "[]"

        DispatchQueue.global(qos: .userInitiated).async {
            self.handleRPC(seq: seq, name: functionName, reqJSON: req)
        }
    }

    func parseArgs(_ jsonString: String) -> [String] {
        guard let data = jsonString.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data, options: []) as? [String] else {
            return []
        }
        return array
    }

    func resolve(seq: String, status: Int, result: String) {
        let js = "window.rpc_resolve('\(seq)', \(status), '\(escapeJS(result))')"
        evalJS(js)
    }

    func handleRPC(seq: String, name: String, reqJSON: String) {
        let args = parseArgs(reqJSON)

        switch name {
        case "get_home_dir":
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            resolve(seq: seq, status: 0, result: home)

        case "save_config":
            guard args.count >= 2 else {
                resolve(seq: seq, status: 1, result: "Invalid parameters")
                return
            }
            let key = args[0]
            let val = args[1]
            let fileURL = getLauncherDir().appendingPathComponent("\(key).txt")
            do {
                try val.write(to: fileURL, atomically: true, encoding: .utf8)
                resolve(seq: seq, status: 0, result: "Success")
            } catch {
                resolve(seq: seq, status: 1, result: error.localizedDescription)
            }

        case "get_config":
            guard args.count >= 1 else {
                resolve(seq: seq, status: 0, result: "")
                return
            }
            let key = args[0]
            let fileURL = getLauncherDir().appendingPathComponent("\(key).txt")
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let content = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
                resolve(seq: seq, status: 0, result: content)
            } else {
                resolve(seq: seq, status: 0, result: "")
            }

        case "get_installed_apps":
            let fileURL = getLauncherDir().appendingPathComponent("installed.txt")
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let content = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
                resolve(seq: seq, status: 0, result: content)
            } else {
                resolve(seq: seq, status: 0, result: "")
            }

        case "detect_installed_app":
            guard args.count >= 1 else {
                resolve(seq: seq, status: 1, result: "Missing app name")
                return
            }
            let repoName = args[0]
            let path = detectAppPath(repoName: repoName)
            resolve(seq: seq, status: 0, result: path)

        case "download_file":
            guard args.count >= 3 else {
                resolve(seq: seq, status: 1, result: "Invalid download arguments")
                return
            }
            let urlStr = args[0]
            let filename = args[1]
            let repoName = args[2]

            executeDownload(urlStr: urlStr, filename: filename, repoName: repoName, seq: seq)

        case "build_repo":
            guard args.count >= 2 else {
                resolve(seq: seq, status: 1, result: "Invalid build arguments")
                return
            }
            let cloneUrl = args[0]
            let repoName = args[1]

            executeBuild(cloneUrl: cloneUrl, repoName: repoName, seq: seq)

        case "launch_app":
            guard args.count >= 1 else {
                resolve(seq: seq, status: 1, result: "Missing launch path")
                return
            }
            let path = args[0]
            launchAppPath(path: path, seq: seq)

        case "uninstall_app":
            guard args.count >= 2 else {
                resolve(seq: seq, status: 1, result: "Invalid uninstall arguments")
                return
            }
            let repoName = args[0]
            let binaryPath = args[1]

            executeUninstall(repoName: repoName, binaryPath: binaryPath, seq: seq)

        case "reset_launcher_cache":
            executeResetCache(seq: seq)

        default:
            resolve(seq: seq, status: 1, result: "Function not found")
        }
    }

    func detectAppPath(repoName: String) -> String {
        let fileManager = FileManager.default

        let localDir = getLauncherDir().appendingPathComponent("apps").appendingPathComponent(repoName)
        if fileManager.fileExists(atPath: localDir.path) {
            let keys = [URLResourceKey.isDirectoryKey]
            if let enumerator = fileManager.enumerator(at: localDir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                for case let url as URL in enumerator {
                    if url.pathExtension.lowercased() == "app" {
                        return url.path
                    }
                }
            }
        }

        var cleanName = repoName.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        cleanName = cleanName.capitalized

        let checkNames = [
            "\(repoName).app",
            "\(cleanName).app"
        ]

        let baseDirs = [
            URL(fileURLWithPath: "/Applications"),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
            localDir
        ]

        for base in baseDirs {
            for name in checkNames {
                let appURL = base.appendingPathComponent(name)
                if fileManager.fileExists(atPath: appURL.path) {
                    return appURL.path
                }
            }
        }

        return ""
    }

    func launchAppPath(path: String, seq: String) {

        let xattrProcess = Process()
        xattrProcess.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattrProcess.arguments = ["-cr", path]
        try? xattrProcess.run()
        xattrProcess.waitUntilExit()

        let launchProcess = Process()
        let pathLower = path.lowercased()

        if pathLower.hasSuffix(".app") || pathLower.hasSuffix(".app/") {
            launchProcess.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            launchProcess.arguments = [path]
        } else {

            let chmodProcess = Process()
            chmodProcess.executableURL = URL(fileURLWithPath: "/bin/chmod")
            chmodProcess.arguments = ["+x", path]
            try? chmodProcess.run()
            chmodProcess.waitUntilExit()

            launchProcess.executableURL = URL(fileURLWithPath: path)
        }

        do {
            try launchProcess.run()
            resolve(seq: seq, status: 0, result: "Launched successfully")
        } catch {

            self.evalJS("window.onBuildLog('[Warning] Standard process run failed. Trying Way 2: NSWorkspace open...')")
            if NSWorkspace.shared.open(URL(fileURLWithPath: path)) {
                resolve(seq: seq, status: 0, result: "Launched successfully via Workspace")
                return
            }

            self.evalJS("window.onBuildLog('[Warning] Way 2 failed. Trying Way 3: AppleScript Terminal Execution...')")
            let scpt = "tell application \"Terminal\" to do script \"chmod +x \(escapeJS(path)) && \(escapeJS(path))\""
            let terminalProcess = Process()
            terminalProcess.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            terminalProcess.arguments = ["-e", scpt]

            do {
                try terminalProcess.run()
                resolve(seq: seq, status: 0, result: "Launched successfully via Terminal")
            } catch {

                if pathLower.hasSuffix(".app") || pathLower.hasSuffix(".app/") {
                    self.evalJS("window.onBuildLog('[Warning] Way 3 failed. Trying Way 4: Direct nested binary execution...')")
                    let contentsMacOS = URL(fileURLWithPath: path).appendingPathComponent("Contents/MacOS")
                    if let files = try? FileManager.default.contentsOfDirectory(at: contentsMacOS, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
                        for file in files {
                            if FileManager.default.isExecutableFile(atPath: file.path) {
                                let chmodProcess = Process()
                                chmodProcess.executableURL = URL(fileURLWithPath: "/bin/chmod")
                                chmodProcess.arguments = ["+x", file.path]
                                try? chmodProcess.run()
                                chmodProcess.waitUntilExit()

                                let subProcess = Process()
                                subProcess.executableURL = file
                                do {
                                    try subProcess.run()
                                    resolve(seq: seq, status: 0, result: "Launched nested binary successfully")
                                    return
                                } catch {}
                            }
                        }
                    }
                }
                resolve(seq: seq, status: 1, result: "All launch methods failed: \(error.localizedDescription)")
            }
        }
    }

    func executeDownload(urlStr: String, filename: String, repoName: String, seq: String) {
        guard let url = URL(string: urlStr) else {
            resolve(seq: seq, status: 1, result: "Invalid URL")
            return
        }

        let targetDir = getLauncherDir().appendingPathComponent("apps").appendingPathComponent(repoName)
        try? FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true, attributes: nil)
        let targetFile = targetDir.appendingPathComponent(filename)

        evalJS("window.onBuildLog('[System] Starting download from \(urlStr)...')")

        let sessionConfig = URLSessionConfiguration.default
        let session = URLSession(configuration: sessionConfig, delegate: nil, delegateQueue: nil)

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")

        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                self.evalJS("window.onBuildLog('[Warning] Native URLSession download failed: \(error.localizedDescription). Trying Way 2: Curl fallback...')")
                self.downloadViaCurl(urlStr: urlStr, targetFile: targetFile, repoName: repoName, filename: filename, seq: seq)
                return
            }

            guard let data = data, !data.isEmpty else {
                self.evalJS("window.onBuildLog('[Warning] Native URLSession returned empty data. Trying Way 2: Curl fallback...')")
                self.downloadViaCurl(urlStr: urlStr, targetFile: targetFile, repoName: repoName, filename: filename, seq: seq)
                return
            }

            do {
                try data.write(to: targetFile)
                self.finalizeDownload(targetFile: targetFile, repoName: repoName, filename: filename, seq: seq)
            } catch {
                self.evalJS("window.onBuildLog('[Warning] Failed to write downloaded data to disk: \(error.localizedDescription). Trying Way 2: Curl fallback...')")
                self.downloadViaCurl(urlStr: urlStr, targetFile: targetFile, repoName: repoName, filename: filename, seq: seq)
            }
        }
        task.resume()

        var currentPercent = 0
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if task.state == .completed {
                self.evalJS("window.onDownloadProgress(100, 100, 100)")
                timer.invalidate()
            } else {
                currentPercent += 5
                if currentPercent >= 95 { currentPercent = 95 }
                self.evalJS("window.onDownloadProgress(\(currentPercent), \(currentPercent), 100)")
            }
        }
    }

    func downloadViaCurl(urlStr: String, targetFile: URL, repoName: String, filename: String, seq: String) {
        evalJS("window.onBuildLog('[System] Initiating Way 2: curl subprocess download...')")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = ["-L", "-o", targetFile.path, "-A", "Mozilla/5.0", urlStr]

        try? process.run()
        process.waitUntilExit()

        let fileManager = FileManager.default
        let size = (try? fileManager.attributesOfItem(atPath: targetFile.path)[.size] as? Int64) ?? 0

        if process.terminationStatus == 0 && fileManager.fileExists(atPath: targetFile.path) && size > 1000 {
            evalJS("window.onBuildLog('[System] Way 2: curl download succeeded!')")
            finalizeDownload(targetFile: targetFile, repoName: repoName, filename: filename, seq: seq)
        } else {
            evalJS("window.onBuildLog('[Warning] Way 2: curl download failed. Trying Way 3: wget fallback...')")
            downloadViaWget(urlStr: urlStr, targetFile: targetFile, repoName: repoName, filename: filename, seq: seq)
        }
    }

    func downloadViaWget(urlStr: String, targetFile: URL, repoName: String, filename: String, seq: String) {
        evalJS("window.onBuildLog('[System] Initiating Way 3: wget subprocess download...')")

        let fileManager = FileManager.default
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/wget")
        if !fileManager.fileExists(atPath: process.executableURL!.path) {
            process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/wget")
        }

        if fileManager.fileExists(atPath: process.executableURL!.path) {
            process.arguments = ["-O", targetFile.path, "-U", "Mozilla/5.0", urlStr]
            try? process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 && fileManager.fileExists(atPath: targetFile.path) {
                evalJS("window.onBuildLog('[System] Way 3: wget download succeeded!')")
                finalizeDownload(targetFile: targetFile, repoName: repoName, filename: filename, seq: seq)
                return
            }
        }

        evalJS("window.onBuildLog('[Warning] Way 3: wget download failed. Trying Way 4: AppleScript do shell script curl fallback...')")
        downloadViaAppleScriptCurl(urlStr: urlStr, targetFile: targetFile, repoName: repoName, filename: filename, seq: seq)
    }

    func downloadViaAppleScriptCurl(urlStr: String, targetFile: URL, repoName: String, filename: String, seq: String) {
        evalJS("window.onBuildLog('[System] Initiating Way 4: AppleScript do shell script curl download...')")

        let fileManager = FileManager.default
        let scpt = "do shell script \"curl -L -o \\\"\(escapeJS(targetFile.path))\\\" -A \\\"Mozilla/5.0\\\" \\\"\(escapeJS(urlStr))\\\"\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", scpt]

        try? process.run()
        process.waitUntilExit()

        let size = (try? fileManager.attributesOfItem(atPath: targetFile.path)[.size] as? Int64) ?? 0
        if process.terminationStatus == 0 && fileManager.fileExists(atPath: targetFile.path) && size > 1000 {
            evalJS("window.onBuildLog('[System] Way 4: AppleScript curl download succeeded!')")
            finalizeDownload(targetFile: targetFile, repoName: repoName, filename: filename, seq: seq)
        } else {
            evalJS("window.onBuildLog('[Error] All download methods (URLSession, curl, wget, AppleScript) failed!')")
            evalJS("window.onDownloadFailed('\(repoName)', 'Download failed on all fallback ways.')")
            resolve(seq: seq, status: 1, result: "Download failed on all fallbacks")
        }
    }

    func finalizeDownload(targetFile: URL, repoName: String, filename: String, seq: String) {
        var finalFilePath = targetFile.path

        if filename.lowercased().hasSuffix(".dmg") {
            self.evalJS("window.onBuildLog('[System] DMG downloaded! Commencing auto-mount extraction...')")
            if let appPath = self.extractDMG(dmgURL: targetFile, repoName: repoName) {
                finalFilePath = appPath
            }
        }

        self.evalJS("window.onDownloadComplete('\(repoName)', '\(escapeJS(finalFilePath))', '\(escapeJS(filename))')")
        self.resolve(seq: seq, status: 0, result: "Download completed")
    }

    func extractDMG(dmgURL: URL, repoName: String) -> String? {
        let fileManager = FileManager.default

        var mountProcess = Process()
        mountProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        mountProcess.arguments = ["mount", "-nobrowse", "-plist", dmgURL.path]

        var pipe = Pipe()
        mountProcess.standardOutput = pipe
        try? mountProcess.run()
        mountProcess.waitUntilExit()

        var data = pipe.fileHandleForReading.readDataToEndOfFile()
        var output = String(data: data, encoding: .utf8) ?? ""

        if mountProcess.terminationStatus != 0 || output.isEmpty {
            evalJS("window.onBuildLog('[Warning] Standard DMG mount failed. Retrying Way 2: Mount with -noverify -noautoopen...')")
            mountProcess = Process()
            mountProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            mountProcess.arguments = ["mount", "-nobrowse", "-noverify", "-noautoopen", "-plist", dmgURL.path]

            pipe = Pipe()
            mountProcess.standardOutput = pipe
            try? mountProcess.run()
            mountProcess.waitUntilExit()

            data = pipe.fileHandleForReading.readDataToEndOfFile()
            output = String(data: data, encoding: .utf8) ?? ""
        }

        var mountPoint: String? = nil
        let lines = output.components(separatedBy: .newlines)
        for i in 0..<lines.count {
            if lines[i].contains("mount-point") && i + 1 < lines.count {
                let nextLine = lines[i+1]
                if let startRange = nextLine.range(of: "<string>"),
                   let endRange = nextLine.range(of: "</string>") {
                    mountPoint = String(nextLine[startRange.upperBound..<endRange.lowerBound])
                    break
                }
            }
        }

        if mountPoint == nil {
            evalJS("window.onBuildLog('[Warning] Mount plist parsing failed. Scanning /Volumes directly...')")
            let volumesURL = URL(fileURLWithPath: "/Volumes")
            if let volumes = try? fileManager.contentsOfDirectory(at: volumesURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
                for vol in volumes {
                    let firstWord = repoName.split(separator: "-").first ?? ""
                    if vol.lastPathComponent.lowercased().contains(firstWord.lowercased()) ||
                       (try? fileManager.contentsOfDirectory(at: vol, includingPropertiesForKeys: nil, options: .skipsHiddenFiles).contains { $0.pathExtension.lowercased() == "app" }) ?? false {
                        mountPoint = vol.path
                        break
                    }
                }
            }
        }

        guard let mp = mountPoint else {
            evalJS("window.onBuildLog('[Error] Mount point lookup failed on all fail-safes.')")
            return nil
        }

        evalJS("window.onBuildLog('[System] DMG mounted successfully at: \(mp)')")

        let mpURL = URL(fileURLWithPath: mp)
        var appURL: URL? = nil

        if let contents = try? fileManager.contentsOfDirectory(at: mpURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
            for url in contents {
                if url.pathExtension.lowercased() == "app" {
                    appURL = url
                    break
                }
            }
        }

        guard let app = appURL else {
            evalJS("window.onBuildLog('[Error] Could not find any .app bundle inside mounted volume.')")
            let detachProcess = Process()
            detachProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            detachProcess.arguments = ["detach", "-force", mp]
            try? detachProcess.run()
            return nil
        }

        let destAppURL = getLauncherDir().appendingPathComponent("apps").appendingPathComponent(repoName).appendingPathComponent(app.lastPathComponent)

        try? fileManager.removeItem(at: destAppURL)

        evalJS("window.onBuildLog('[System] Copying \(app.lastPathComponent) to apps folder...')")

        let cpProcess = Process()
        cpProcess.executableURL = URL(fileURLWithPath: "/bin/cp")
        cpProcess.arguments = ["-R", app.path, destAppURL.deletingLastPathComponent().path]
        try? cpProcess.run()
        cpProcess.waitUntilExit()

        if cpProcess.terminationStatus != 0 || !fileManager.fileExists(atPath: destAppURL.path) {
            evalJS("window.onBuildLog('[Warning] Standard cp failed. Trying Way 2: ditto...')")

            let dittoProcess = Process()
            dittoProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            dittoProcess.arguments = [app.path, destAppURL.path]
            try? dittoProcess.run()
            dittoProcess.waitUntilExit()

            if dittoProcess.terminationStatus != 0 || !fileManager.fileExists(atPath: destAppURL.path) {
                evalJS("window.onBuildLog('[Warning] ditto failed. Trying Way 3: rsync...')")

                let rsyncProcess = Process()
                rsyncProcess.executableURL = URL(fileURLWithPath: "/usr/bin/rsync")
                rsyncProcess.arguments = ["-a", app.path + "/", destAppURL.path]
                try? rsyncProcess.run()
                rsyncProcess.waitUntilExit()

                if !fileManager.fileExists(atPath: destAppURL.path) {
                    evalJS("window.onBuildLog('[Warning] rsync failed. Trying Way 4: AppleScript Finder duplicate copy fallback...')")

                    let parentPath = destAppURL.deletingLastPathComponent().path
                    let scpt = "tell application \"Finder\" to duplicate POSIX file \"\(escapeJS(app.path))\" to POSIX file \"\(escapeJS(parentPath))\" with replacing"
                    let osascript = Process()
                    osascript.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                    osascript.arguments = ["-e", scpt]
                    try? osascript.run()
                    osascript.waitUntilExit()
                }
            }
        }

        evalJS("window.onBuildLog('[System] Unmounting DMG volume...')")
        let detachProcess = Process()
        detachProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        detachProcess.arguments = ["detach", "-force", mp]
        try? detachProcess.run()
        detachProcess.waitUntilExit()

        let xattrProcess = Process()
        xattrProcess.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattrProcess.arguments = ["-cr", destAppURL.path]
        try? xattrProcess.run()
        xattrProcess.waitUntilExit()

        return destAppURL.path
    }

    func executeBuild(cloneUrl: String, repoName: String, seq: String) {
        let fileManager = FileManager.default
        let launcherDir = getLauncherDir()
        let sourcesDir = launcherDir.appendingPathComponent("sources").appendingPathComponent(repoName)
        let appsDir = launcherDir.appendingPathComponent("apps").appendingPathComponent(repoName)

        try? fileManager.removeItem(at: sourcesDir)
        try? fileManager.createDirectory(at: sourcesDir, withIntermediateDirectories: true, attributes: nil)
        try? fileManager.createDirectory(at: appsDir, withIntermediateDirectories: true, attributes: nil)

        self.evalJS("window.onBuildLog('[System] Cloning repository: \(cloneUrl)...')")

        let gitProcess = Process()
        gitProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        gitProcess.arguments = ["clone", cloneUrl, sourcesDir.path]

        let gitPipe = Pipe()
        gitProcess.standardError = gitPipe
        gitProcess.standardOutput = gitPipe

        try? gitProcess.run()

        let gitFileHandle = gitPipe.fileHandleForReading
        gitFileHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if let line = String(data: data, encoding: .utf8), !line.isEmpty {
                self.evalJS("window.onBuildLog('\(escapeJS(line))')")
            }
        }

        gitProcess.waitUntilExit()
        gitFileHandle.readabilityHandler = nil

        if gitProcess.terminationStatus != 0 || !fileManager.fileExists(atPath: sourcesDir.path) || (try? fileManager.contentsOfDirectory(atPath: sourcesDir.path))?.isEmpty ?? true {
            self.evalJS("window.onBuildLog('[Warning] Git clone failed or is unavailable. Trying Way 2: Downloading ZIP source archive...')")
            let zipURL = "https://github.com/\(repoName)/archive/refs/heads/main.zip"
            let fallbackZipURL = "https://github.com/\(repoName)/archive/refs/heads/master.zip"

            let tempZip = sourcesDir.deletingLastPathComponent().appendingPathComponent("\(repoName)_source.zip")
            try? fileManager.removeItem(at: tempZip)

            let curlZip = Process()
            curlZip.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            curlZip.arguments = ["-L", "-o", tempZip.path, zipURL]
            try? curlZip.run()
            curlZip.waitUntilExit()

            let size = (try? fileManager.attributesOfItem(atPath: tempZip.path)[.size] as? Int64) ?? 0

            if !fileManager.fileExists(atPath: tempZip.path) || size < 2000 {

                let curlZipMaster = Process()
                curlZipMaster.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
                curlZipMaster.arguments = ["-L", "-o", tempZip.path, fallbackZipURL]
                try? curlZipMaster.run()
                curlZipMaster.waitUntilExit()
            }

            let finalSize = (try? fileManager.attributesOfItem(atPath: tempZip.path)[.size] as? Int64) ?? 0

            if fileManager.fileExists(atPath: tempZip.path) && finalSize > 2000 {
                self.evalJS("window.onBuildLog('[System] Archive downloaded successfully. Extracting ZIP...')")
                let unzipProcess = Process()
                unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                unzipProcess.arguments = ["-o", tempZip.path, "-d", sourcesDir.deletingLastPathComponent().path]
                try? unzipProcess.run()
                unzipProcess.waitUntilExit()

                if unzipProcess.terminationStatus != 0 {
                    self.evalJS("window.onBuildLog('[Warning] standard unzip failed. Trying Way 2: ditto extractor...')")
                    let dittoExtract = Process()
                    dittoExtract.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                    dittoExtract.arguments = ["-x", "-k", tempZip.path, sourcesDir.deletingLastPathComponent().path]
                    try? dittoExtract.run()
                    dittoExtract.waitUntilExit()
                }

                if let subfolders = try? fileManager.contentsOfDirectory(at: sourcesDir.deletingLastPathComponent(), includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
                    for folder in subfolders {
                        if folder.lastPathComponent.hasPrefix(repoName.split(separator: "/").last ?? "") && folder != sourcesDir {
                            try? fileManager.removeItem(at: sourcesDir)
                            try? fileManager.moveItem(at: folder, to: sourcesDir)
                            break
                        }
                    }
                }
                try? fileManager.removeItem(at: tempZip)
            } else {
                self.evalJS("window.onBuildFailed('\(repoName)', 'Source cloning and ZIP archive fallback failed.')")
                self.resolve(seq: seq, status: 1, result: "Source acquisition failed")
                return
            }
        }

        let hasCMake = fileManager.fileExists(atPath: sourcesDir.appendingPathComponent("CMakeLists.txt").path)
        let hasMakefile = fileManager.fileExists(atPath: sourcesDir.appendingPathComponent("Makefile").path)

        let buildScripts = ["build.sh", "install.sh", "compile.sh", "make.sh", "setup.sh"]
        var activeScript: String? = nil
        for script in buildScripts {
            if fileManager.fileExists(atPath: sourcesDir.appendingPathComponent(script).path) {
                activeScript = script
                break
            }
        }

        var buildSuccess = false
        var compiledBinaryURL: URL? = nil

        if hasCMake {
            self.evalJS("window.onBuildLog('[System] CMakeLists.txt detected. Running CMake configuration...')")
            let buildDir = sourcesDir.appendingPathComponent("build")
            try? fileManager.createDirectory(at: buildDir, withIntermediateDirectories: true, attributes: nil)

            let cmakeConf = Process()
            cmakeConf.executableURL = URL(fileURLWithPath: "/usr/local/bin/cmake")
            if !fileManager.fileExists(atPath: cmakeConf.executableURL!.path) {
                cmakeConf.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/cmake")
            }
            if !fileManager.fileExists(atPath: cmakeConf.executableURL!.path) {
                cmakeConf.executableURL = URL(fileURLWithPath: "/Applications/CMake.app/Contents/bin/cmake")
            }
            if !fileManager.fileExists(atPath: cmakeConf.executableURL!.path) {
                cmakeConf.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                cmakeConf.arguments = ["cmake"]
            }

            let cPipe = Pipe()
            if cmakeConf.executableURL!.path == "/usr/bin/env" {
                cmakeConf.arguments = ["cmake", "-B", buildDir.path, "-S", sourcesDir.path, "-DCMAKE_BUILD_TYPE=Release"]
            } else {
                cmakeConf.arguments = ["-B", buildDir.path, "-S", sourcesDir.path, "-DCMAKE_BUILD_TYPE=Release"]
            }

            cmakeConf.standardOutput = cPipe
            cmakeConf.standardError = cPipe
            try? cmakeConf.run()

            cPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if let line = String(data: data, encoding: .utf8), !line.isEmpty {
                    self.evalJS("window.onBuildLog('\(escapeJS(line))')")
                }
            }
            cmakeConf.waitUntilExit()
            cPipe.fileHandleForReading.readabilityHandler = nil

            if cmakeConf.terminationStatus == 0 {

                self.evalJS("window.onBuildLog('[System] Running CMake build compilation...')")
                let cmakeBuild = Process()
                if cmakeConf.executableURL!.path == "/usr/bin/env" {
                    cmakeBuild.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                    cmakeBuild.arguments = ["cmake", "--build", buildDir.path, "--config", "Release"]
                } else {
                    cmakeBuild.executableURL = cmakeConf.executableURL
                    cmakeBuild.arguments = ["--build", buildDir.path, "--config", "Release"]
                }

                let bPipe = Pipe()
                cmakeBuild.standardOutput = bPipe
                cmakeBuild.standardError = bPipe
                try? cmakeBuild.run()

                bPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if let line = String(data: data, encoding: .utf8), !line.isEmpty {
                        self.evalJS("window.onBuildLog('\(escapeJS(line))')")
                    }
                }
                cmakeBuild.waitUntilExit()
                bPipe.fileHandleForReading.readabilityHandler = nil

                if cmakeBuild.terminationStatus == 0 {
                    buildSuccess = true
                    compiledBinaryURL = scanForExecutables(in: buildDir)
                }
            }

            if !buildSuccess {
                if hasMakefile {
                    self.evalJS("window.onBuildLog('[Warning] CMake build failed. Trying Makefile fallback compilation...')")
                    self.runMakefileBuild(sourcesDir: sourcesDir, appsDir: appsDir, repoName: repoName, seq: seq)
                    return
                } else if let script = activeScript {
                    self.evalJS("window.onBuildLog('[Warning] CMake failed. Trying build script fallback compilation...')")
                    self.runScriptBuild(scriptName: script, sourcesDir: sourcesDir, appsDir: appsDir, repoName: repoName, seq: seq)
                    return
                }
            }
        } else if let script = activeScript {
            self.runScriptBuild(scriptName: script, sourcesDir: sourcesDir, appsDir: appsDir, repoName: repoName, seq: seq)
            return
        } else if hasMakefile {
            self.runMakefileBuild(sourcesDir: sourcesDir, appsDir: appsDir, repoName: repoName, seq: seq)
            return
        } else {

            self.evalJS("window.onBuildLog('[Warning] No CMakeLists.txt or Makefile found. Scanning directory for pre-built binaries or runnable scripts...')")
            if let binURL = scanForExecutables(in: sourcesDir) {
                compiledBinaryURL = binURL
                buildSuccess = true
            } else {
                self.evalJS("window.onBuildLog('[Error] No build system or executable binaries detected!')")
            }
        }

        if buildSuccess, let binURL = compiledBinaryURL {
            let destURL = appsDir.appendingPathComponent(binURL.lastPathComponent)
            try? fileManager.removeItem(at: destURL)

            let cpProcess = Process()
            cpProcess.executableURL = URL(fileURLWithPath: "/bin/cp")
            cpProcess.arguments = ["-R", binURL.path, appsDir.path]
            try? cpProcess.run()
            cpProcess.waitUntilExit()

            let finalBinPath = destURL.path

            let xattrProcess = Process()
            xattrProcess.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            xattrProcess.arguments = ["-cr", finalBinPath]
            try? xattrProcess.run()
            xattrProcess.waitUntilExit()

            self.evalJS("window.onBuildComplete('\(repoName)', '\(escapeJS(finalBinPath))')")
            self.resolve(seq: seq, status: 0, result: "Build completed")
        } else {
            self.evalJS("window.onBuildFailed('\(repoName)', 'Compilation failed or no executable found.')")
            self.resolve(seq: seq, status: 1, result: "Build failed")
        }
    }

    func runScriptBuild(scriptName: String, sourcesDir: URL, appsDir: URL, repoName: String, seq: String) {
        let fileManager = FileManager.default
        self.evalJS("window.onBuildLog('[System] Build script detected: \(scriptName). Running script compilation...')")

        let chmodProcess = Process()
        chmodProcess.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmodProcess.arguments = ["+x", sourcesDir.appendingPathComponent(scriptName).path]
        try? chmodProcess.run()
        chmodProcess.waitUntilExit()

        let scriptProcess = Process()
        scriptProcess.executableURL = URL(fileURLWithPath: "/bin/sh")
        scriptProcess.arguments = [sourcesDir.appendingPathComponent(scriptName).path]
        scriptProcess.currentDirectoryURL = sourcesDir

        let sPipe = Pipe()
        scriptProcess.standardOutput = sPipe
        scriptProcess.standardError = sPipe
        try? scriptProcess.run()

        sPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let line = String(data: data, encoding: .utf8), !line.isEmpty {
                self.evalJS("window.onBuildLog('\(escapeJS(line))')")
            }
        }
        scriptProcess.waitUntilExit()
        sPipe.fileHandleForReading.readabilityHandler = nil

        let hasMakefile = fileManager.fileExists(atPath: sourcesDir.appendingPathComponent("Makefile").path)

        if scriptProcess.terminationStatus == 0, let binURL = scanForExecutables(in: sourcesDir) {
            let destURL = appsDir.appendingPathComponent(binURL.lastPathComponent)
            try? fileManager.removeItem(at: destURL)

            let cpProcess = Process()
            cpProcess.executableURL = URL(fileURLWithPath: "/bin/cp")
            cpProcess.arguments = ["-R", binURL.path, appsDir.path]
            try? cpProcess.run()
            cpProcess.waitUntilExit()

            let finalBinPath = destURL.path

            let xattrProcess = Process()
            xattrProcess.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            xattrProcess.arguments = ["-cr", finalBinPath]
            try? xattrProcess.run()
            xattrProcess.waitUntilExit()

            self.evalJS("window.onBuildComplete('\(repoName)', '\(escapeJS(finalBinPath))')")
            self.resolve(seq: seq, status: 0, result: "Build completed")
        } else {
            self.evalJS("window.onBuildLog('[Warning] Build script returned error or no executable found. Falling back...')")
            if hasMakefile {
                self.runMakefileBuild(sourcesDir: sourcesDir, appsDir: appsDir, repoName: repoName, seq: seq)
            } else if let binURL = scanForExecutables(in: sourcesDir) {
                let destURL = appsDir.appendingPathComponent(binURL.lastPathComponent)
                try? fileManager.removeItem(at: destURL)
                try? fileManager.copyItem(at: binURL, to: destURL)
                self.evalJS("window.onBuildComplete('\(repoName)', '\(escapeJS(destURL.path))')")
                self.resolve(seq: seq, status: 0, result: "Build completed")
            } else {
                self.evalJS("window.onBuildFailed('\(repoName)', 'Script compilation failed.')")
                self.resolve(seq: seq, status: 1, result: "Build failed")
            }
        }
    }

    func runMakefileBuild(sourcesDir: URL, appsDir: URL, repoName: String, seq: String) {
        let fileManager = FileManager.default
        self.evalJS("window.onBuildLog('[System] Makefile detected. Running make compilation...')")
        let makeProcess = Process()
        makeProcess.executableURL = URL(fileURLWithPath: "/usr/bin/make")
        makeProcess.arguments = ["-C", sourcesDir.path]
        let mPipe = Pipe()
        makeProcess.standardOutput = mPipe
        makeProcess.standardError = mPipe
        try? makeProcess.run()

        mPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let line = String(data: data, encoding: .utf8), !line.isEmpty {
                self.evalJS("window.onBuildLog('\(escapeJS(line))')")
            }
        }
        makeProcess.waitUntilExit()
        mPipe.fileHandleForReading.readabilityHandler = nil

        if makeProcess.terminationStatus == 0, let binURL = scanForExecutables(in: sourcesDir) {
            let destURL = appsDir.appendingPathComponent(binURL.lastPathComponent)
            try? fileManager.removeItem(at: destURL)

            let cpProcess = Process()
            cpProcess.executableURL = URL(fileURLWithPath: "/bin/cp")
            cpProcess.arguments = ["-R", binURL.path, appsDir.path]
            try? cpProcess.run()
            cpProcess.waitUntilExit()

            let finalBinPath = destURL.path

            let xattrProcess = Process()
            xattrProcess.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            xattrProcess.arguments = ["-cr", finalBinPath]
            try? xattrProcess.run()
            xattrProcess.waitUntilExit()

            self.evalJS("window.onBuildComplete('\(repoName)', '\(escapeJS(finalBinPath))')")
            self.resolve(seq: seq, status: 0, result: "Build completed")
        } else {
            self.evalJS("window.onBuildFailed('\(repoName)', 'Make compilation failed.')")
            self.resolve(seq: seq, status: 1, result: "Build failed")
        }
    }

    func scanForExecutables(in directory: URL) -> URL? {
        let fileManager = FileManager.default
        let keys = [URLResourceKey.isDirectoryKey]

        if let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for case let url as URL in enumerator {
                if url.pathExtension.lowercased() == "app" {
                    return url
                }
            }
        }

        if let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for case let url as URL in enumerator {
                let path = url.path
                if fileManager.isExecutableFile(atPath: path) && url.pathExtension.isEmpty && !path.contains("CMakeFiles") {
                    return url
                }
            }
        }

        return nil
    }

    func executeUninstall(repoName: String, binaryPath: String, seq: String) {
        evalJS("window.onBuildLog('[System] Starting uninstallation for \(repoName)...')")

        let appsDir = getLauncherDir().appendingPathComponent("apps").appendingPathComponent(repoName)
        let sourcesDir = getLauncherDir().appendingPathComponent("sources").appendingPathComponent(repoName)

        let pkill1 = Process()
        pkill1.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkill1.arguments = ["-9", "-f", repoName]
        try? pkill1.run()
        pkill1.waitUntilExit()

        var exeName = ""
        if !binaryPath.isEmpty {
            let binURL = URL(fileURLWithPath: binaryPath)
            exeName = binURL.lastPathComponent
            if exeName.hasSuffix(".app") && exeName.count > 4 {
                exeName = String(exeName.dropLast(4))
            }

            let pkill2 = Process()
            pkill2.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            pkill2.arguments = ["-9", "-f", exeName]
            try? pkill2.run()
            pkill2.waitUntilExit()
        }

        if !exeName.isEmpty {
            let killall = Process()
            killall.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            killall.arguments = ["-9", exeName]
            try? killall.run()
            killall.waitUntilExit()
        }

        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-f", repoName]
        let pgPipe = Pipe()
        pgrep.standardOutput = pgPipe
        try? pgrep.run()
        pgrep.waitUntilExit()
        let pgData = pgPipe.fileHandleForReading.readDataToEndOfFile()
        if let pgStr = String(data: pgData, encoding: .utf8), !pgStr.isEmpty {
            let pids = pgStr.components(separatedBy: .newlines).filter { !$0.isEmpty }
            for pid in pids {
                let killProc = Process()
                killProc.executableURL = URL(fileURLWithPath: "/bin/kill")
                killProc.arguments = ["-9", pid]
                try? killProc.run()
                killProc.waitUntilExit()
            }
        }

        if !exeName.isEmpty {
            let quitScpt = "tell application \"\(escapeJS(exeName))\" to quit"
            let osascriptQuit = Process()
            osascriptQuit.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            osascriptQuit.arguments = ["-e", quitScpt]
            try? osascriptQuit.run()
            osascriptQuit.waitUntilExit()
        }

        Thread.sleep(forTimeInterval: 0.2)

        let fileManager = FileManager.default
        var success = true

        if fileManager.fileExists(atPath: appsDir.path) {
            evalJS("window.onBuildLog('[System] Removing local app binaries...')")
            do {
                try fileManager.removeItem(at: appsDir)
            } catch {
                evalJS("window.onBuildLog('[Warning] Native rmdir failed: \(error.localizedDescription). Trying Way 2: shell rm -rf...')")

                let rmProcess = Process()
                rmProcess.executableURL = URL(fileURLWithPath: "/bin/rm")
                rmProcess.arguments = ["-rf", appsDir.path]
                try? rmProcess.run()
                rmProcess.waitUntilExit()

                if fileManager.fileExists(atPath: appsDir.path) {
                    evalJS("window.onBuildLog('[Warning] Shell rm -rf failed. Trying Way 3: AppleScript Finder Move to Trash...')")

                    let trashProcess = Process()
                    trashProcess.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                    trashProcess.arguments = ["-e", "with timeout of 2 seconds", "-e", "tell application \"Finder\" to delete POSIX file \"\(appsDir.path)\"", "-e", "end timeout"]
                    try? trashProcess.run()
                    trashProcess.waitUntilExit()

                    if fileManager.fileExists(atPath: appsDir.path) {
                        evalJS("window.onBuildLog('[Warning] Way 3 failed. Trying Way 4: Rename to junk fallback...')")

                        let junkDir = getLauncherDir().appendingPathComponent("junk")
                        try? fileManager.createDirectory(at: junkDir, withIntermediateDirectories: true, attributes: nil)
                        let junkPath = junkDir.appendingPathComponent("\(repoName)_\(Date().timeIntervalSince1970)")
                        do {
                            try fileManager.moveItem(at: appsDir, to: junkPath)
                        } catch {

                            evalJS("window.onBuildLog('[Warning] Way 4 failed. Trying Way 5: Hidden dot-prefix concealment...')")
                            let hiddenPath = getLauncherDir().appendingPathComponent("apps").appendingPathComponent(".junk_\(repoName)_\(Date().timeIntervalSince1970)")
                            do {
                                try fileManager.moveItem(at: appsDir, to: hiddenPath)
                            } catch {
                                success = false
                                evalJS("window.onBuildLog('[Error] All uninstallation failsafes failed for apps folder: \(error.localizedDescription)')")
                            }
                        }
                    }
                }
            }
        }

        if fileManager.fileExists(atPath: sourcesDir.path) {
            evalJS("window.onBuildLog('[System] Removing source caches...')")
            do {
                try fileManager.removeItem(at: sourcesDir)
            } catch {

                let rmProcess = Process()
                rmProcess.executableURL = URL(fileURLWithPath: "/bin/rm")
                rmProcess.arguments = ["-rf", sourcesDir.path]
                try? rmProcess.run()
                rmProcess.waitUntilExit()

                if fileManager.fileExists(atPath: sourcesDir.path) {

                    let junkDir = getLauncherDir().appendingPathComponent("junk")
                    try? fileManager.createDirectory(at: junkDir, withIntermediateDirectories: true, attributes: nil)
                    let junkPath = junkDir.appendingPathComponent("\(repoName)_sources_\(Date().timeIntervalSince1970)")
                    try? fileManager.moveItem(at: sourcesDir, to: junkPath)
                }
            }
        }

        if success {
            resolve(seq: seq, status: 0, result: "Successfully uninstalled completely.")
        } else {
            resolve(seq: seq, status: 0, result: "Uninstalled with warnings.")
        }
    }

    func executeResetCache(seq: String) {
        let fileManager = FileManager.default
        let launcherDir = getLauncherDir()
        let appsDir = launcherDir.appendingPathComponent("apps")
        let sourcesDir = launcherDir.appendingPathComponent("sources")
        let installedFile = launcherDir.appendingPathComponent("installed.txt")

        try? fileManager.removeItem(at: appsDir)
        try? fileManager.removeItem(at: sourcesDir)
        try? fileManager.removeItem(at: installedFile)

        resolve(seq: seq, status: 0, result: "Launcher cache and applications database reset successfully.")
    }

    func setAppMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appSubMenu = NSMenu()
        appMenuItem.submenu = appSubMenu

        let appName = ProcessInfo.processInfo.processName
        appSubMenu.addItem(withTitle: "About \(appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appSubMenu.addItem(NSMenuItem.separator())
        appSubMenu.addItem(withTitle: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editSubMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editSubMenu

        editSubMenu.addItem(withTitle: "Undo", action: #selector(UndoManager.undo), keyEquivalent: "z")
        editSubMenu.addItem(withTitle: "Redo", action: #selector(UndoManager.redo), keyEquivalent: "Z")
        editSubMenu.addItem(NSMenuItem.separator())
        editSubMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editSubMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editSubMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editSubMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        NSApplication.shared.mainMenu = mainMenu
    }
}

let controller = LauncherController()
controller.start()
