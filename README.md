# QuickKit

A local, native macOS file utility for conversions, light editing tools, and file actions. Files stay on the machine. Originals are never overwritten silently.

This repository currently contains **Milestone 1**: the app shell, file drop zone, tool detection, and a Finder-drag feasibility prototype.

## Requirements

- macOS 14 or later (developed on an Apple silicon Mac running macOS 27.0.1 with Xcode 27.1)
- Xcode 16 or later (this machine has Xcode 27.1)
- Optional Homebrew tools, detected at runtime:
  - `ffmpeg` / `ffprobe` — media (must be **arm64** on Apple silicon)
  - `imagemagick` (`magick`) — extra image formats
  - `qpdf` — optional PDF extras
  - `webp` (`cwebp` / `dwebp`) — optional WebP CLI

Do not copy binaries from other apps. QuickKit does not bundle FFmpeg, ImageMagick, or qpdf yet.

## Build

```bash
cd /Users/adee/Web-Development/quickcon
xcodegen generate   # only needed after editing project.yml
xcodebuild -scheme QuickKit -configuration Debug build
xcodebuild -scheme QuickKit -configuration Debug test
```

Open `QuickKit.xcodeproj` in Xcode to run the app.

## Current machine notes

On the development Mac:

- `/usr/local/bin/ffmpeg` is an **x86_64** Intel binary and cannot run (`bad CPU type`). QuickKit reports it as incompatible, not as a working encoder.
- ImageMagick and qpdf are not installed. Image I/O and PDFKit will cover the first conversion/PDF milestones.

Install an Apple silicon FFmpeg later with `brew install ffmpeg` (Homebrew prefix `/opt/homebrew`).

## Interaction

1. Drop files onto the main window (always supported).
2. Choose **Action Picker** or press Return while QuickKit is focused.
3. Optional spike: drag a file from Finder and press Shift, Command, or Control. The drag HUD reports whether public pasteboard tracking sees the drag. See [docs/drag-feasibility.md](docs/drag-feasibility.md).

## Licence

Application source is intended to be MIT; confirm before a public release. Third-party tool licences are listed in [docs/dependencies.md](docs/dependencies.md).
