# Tiwut Launcher (MacOS Edition)

A premium, frosted **Liquid Glass** native macOS launcher designed exclusively for compiling, installing, running, and managing Tiwut applications. Built with a 100% native Apple Swift backend integrated with a responsive WebKit user interface.

<img width="1045" height="780" alt="Screenshot 2026-05-30 at 11 01 21" src="https://github.com/user-attachments/assets/425904c8-a6b1-415a-aef2-de559cd9ee94" />

---

## Key Features

### 1. Apple Liquid Glass Aesthetic
* **Native Vibrancy Blurs**: Features native macOS `NSVisualEffectView` HUD material backing directly behind transparent `WKWebView` window panels for stunning glassmorphism.
* **Tacit Micro-Animations**: Fluid spring tab transitions, elastic details modals, vertical grow navigation bars, and physical button-compress scaling triggers.
* **Cascading Grid Entries**: Staggered app card ripple entry delays (`index * 0.03s`) for smooth, high-end presentation grids.
* **Custom Drag Zone**: Viewport-anchored transparent titlebar overlay mapped perfectly to system level actions for fluid native movability.

### 2. Auto-Stretching Uniform Library
* Grid card layouts automatically stretch using CSS Grid `grid-auto-rows: 1fr` standard to match each other's height.
* Headers support safe multi-line wrapping and word breaks (`word-break: break-word;`), ensuring long repository names are always completely visible without clipping.

### 3. Military-Grade Downloader & DMG Fallbacks
* **Multi-Tiered Downloads**: Falls back gracefully: `URLSession` $\rightarrow$ Subprocess `curl` $\rightarrow$ Subprocess `wget` $\rightarrow$ AppleScript `do shell script` curl runner.
* **Mount & Extraction loops**: Swift-native plist mount checks (`hdiutil mount -nobrowse -plist`) $\rightarrow$ Direct `/Volumes` scans $\rightarrow$ Mount retries ignoring checksums.
* **Extraction Copying**: standard `cp -R` $\rightarrow$ `ditto` $\rightarrow$ `rsync` $\rightarrow$ User-context AppleScript Finder copy duplicate loops.
* **Quarantine Bypasses**: Automatically strips Gatekeeper quarantine flags (`xattr -cr`) on copy completions.

### 4. Source Compilers & Process Runner
* **Compiling Options**: Native git clones $\rightarrow$ Fallback ZIP download fallbacks $\rightarrow$ CMake checks $\rightarrow$ Raw `make` configurations $\rightarrow$ Custom setup scripts (`build.sh`, etc.) execute.
* **Process Launcher**: Sandboxed launches $\rightarrow$ Cocoa `NSWorkspace` opening $\rightarrow$ AppleScript terminal runners.
* **Uninstall Locks**: Clean exit processes (`pkill` $\rightarrow$ `killall` $\rightarrow$ dynamic PIDs kill) $\rightarrow$ Swift directory deletions $\rightarrow$ Rename concealment folders.

---

## Building & Installing

### System Requirements
* **Operating System**: macOS Sequoia (14.0+) or later optimized exclusively.
* **Compiler**: Swift Compiler (`swiftc`), Xcode Command Line Tools.
* **Build System**: CMake 3.15+ (optional).

### Option 1: Native Compilation (Standard)

Configure and compile the launcher binary from source:
```bash
mkdir build && cd build
cmake ..
make
```

To run the launcher:
```bash
./TiwutLauncher
```

---

## License
This project is licensed under the MIT License.
