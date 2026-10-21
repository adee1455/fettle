# Dependencies and Licences

Fettle is designed to operate locally on macOS with minimal external dependencies. Third-party CLI tools are detected dynamically at runtime from Homebrew (`/opt/homebrew/bin` and `/usr/local/bin`). **No third-party binaries are bundled into the application bundle.**

## Dependency and Licence Matrix

| Component / Tool | Primary Engine | Optional / Fallback Engine | Licence & Redistribution Policy |
|---|---|---|---|
| **App Source** | Swift 6 / Apple SDK | — | MIT Licence. |
| **Raster Images** (PNG, JPEG, TIFF) | Core Graphics / Image I/O (`CGImageSource`, `CGImageDestination`) | ImageMagick 7 (`magick`) | System APIs are built-in. ImageMagick is licensed under Apache-2.0. |
| **WebP** | Image I/O (Native encode/decode supported on macOS 14+) | `cwebp` / `dwebp` via Homebrew `webp` | libwebp is BSD-licensed. Native Image I/O is preferred; CLI used only if extended options are required. |
| **HEIC / HEIF** | Image I/O | ImageMagick 7 (`magick`) | System codecs provided by Apple. |
| **Media** (Video / Audio) | FFmpeg (`ffmpeg`, `ffprobe`) executed via `Process` | AVFoundation (metadata & playback) | Homebrew builds of FFmpeg are typically **GPL-2.0 / GPL-3.0**. To preserve license compliance, Fettle **does not bundle** FFmpeg. It requires user installation (`brew install ffmpeg`). |
| **PDF** | PDFKit (`PDFDocument`, `PDFPage`) | `qpdf` CLI via Homebrew | PDFKit is built-in. `qpdf` is licensed under Apache-2.0. |
| **File Actions** | Foundation & AppKit (`NSWorkspace`, `FileManager`) | — | Native system APIs. |

## Host Environment Status (Inspected)

- **Architecture:** Apple Silicon (`arm64`)
- **OS Version:** macOS 14+ (tested on macOS 14.x / 27.x)
- **Homebrew Prefix:** `/opt/homebrew`
- **Installed Homebrew Formulae:**
  - `webp` (`cwebp`, `dwebp` installed at `/opt/homebrew/bin/cwebp`)
- **Not Installed:**
  - `imagemagick` (`magick` is absent)
  - `qpdf` (absent)
- **Incompatible Binary Detected:**
  - `/usr/local/bin/ffmpeg` and `/usr/local/bin/ffprobe` exist but are `x86_64` Mach-O binaries. On Apple Silicon systems without Rosetta (or in native execution), executing these results in `bad CPU type in executable`. Fettle's `ToolAvailability` scanner and `MachOReader` detect this mismatch and mark these tools as **incompatible architecture**, suppressing invalid execution attempts.

## Guidelines for External Tool Invocation

1. Always use `Foundation.Process` with explicit executable URL and arguments array `[String]`. **Never run shell strings** (`/bin/sh -c` or `bash -c`) with user input or file paths to prevent shell injection.
2. Check tool readiness using `ToolAvailability.status(for:)` before scheduling tasks.
3. Validate output files after generation via `OutputManager` before declaring task success.
