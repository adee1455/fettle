# Conversion Presets Specification

Fettle defines conversion operations as declarative data structures rather than embedding logic inside UI controls. This architecture ensures presets can be ported to other platforms (such as Windows or Linux) or exposed through headless CLI runners without altering view models.

## 1. Image Presets

Image operations default to Apple's native **Image I/O** framework, falling back to `magick` or `cwebp` when advanced options or specialized encoders are needed.

### Format Conversion
- **PNG to JPEG**:
  - Parameters: Quality compression factor (0.0 to 1.0, default: 0.85).
  - Alpha handling: Flatten alpha onto custom matte background (default: `#FFFFFF` opaque white).
- **JPEG to PNG**:
  - Lossless conversion, preserves color space / ICC profiles.
- **Any to WebP**:
  - Target: WebP lossy or lossless.
  - Quality: Default 80.
  - Handled via Image I/O on macOS 14+ (`public.webp` destination).
- **HEIC to JPEG/PNG**:
  - Reads native HEIF/HEIC source containers and exports standard web-compatible bitmaps.

### Resize & Optimization
- **Scale by Percentage**: Scale dimensions proportionally (25%, 50%, 75%, 200%).
- **Fit within Bounding Box**: Resize to fit within `maxDimension` (e.g. 1920x1080) preserving aspect ratio.
- **Strip Metadata**: Remove EXIF / GPS / camera tags while preserving color space.

---

## 2. Media Presets (Audio & Video)

Media operations require **arm64 FFmpeg** (`ffmpeg` and `ffprobe`). Operations stream status updates using explicit `-progress pipe:1` arguments and process standard output.

### Video Transcoding & Compression
- **MP4 (H.264 / AAC)**:
  - Video Codec: `libx264`, preset `medium`, CRF 23.
  - Audio Codec: `aac`, 128 kbps.
  - Pixel Format: `yuv420p` for maximum player compatibility.
  - Faststart flag: `-movflags +faststart` for web streaming.
- **MP4 (H.265 / HEVC)**:
  - Video Codec: `libx265`, CRF 28.
  - Audio Codec: `aac`, 128 kbps.
- **Animated GIF**:
  - Palette generation filter: `split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse`.
  - Max FPS: 15 fps.

### Audio Extraction & Transcoding
- **Extract Audio to MP3**:
  - Codec: `libmp3lame`, quality VBR 2 (approx 190 kbps).
- **Extract Audio to AAC / M4A**:
  - Codec: `aac`, 192 kbps.
- **Extract Audio to WAV (Lossless)**:
  - Codec: `pcm_s16le`, 44.1 kHz, 16-bit stereo.

---

## 3. PDF Presets

PDF operations use Apple's **PDFKit** (`PDFDocument`) natively with no external dependency required.

- **Merge PDFs**:
  - Combines multiple selected PDF documents sequentially into a single multi-page PDF document.
- **Extract Pages**:
  - Extracts individual pages or page ranges into standalone PDF files.
- **Images to PDF**:
  - Takes a list of image files and creates a multi-page PDF document where each page embeds an image sized to standard page bounds.

---

## 4. File Actions

Quick, non-destructive file operations:
- **Reveal in Finder**: `NSWorkspace.shared.activateFileViewerSelecting(_:)`
- **Copy Path / POSIX Path**: Copies clean string to `NSPasteboard.general`.
- **Duplicate**: Clones file safely using `FileManager.default.copyItem`.
- **Open in Terminal**: Launches Terminal or iTerm cd-ed to containing folder.

---

## 5. Output Management Rules

All presets abide by the following output safety policies:
1. **Never Overwrite Silently**: If `target.ext` exists, generate collision-free unique names (e.g., `target (1).ext`).
2. **Never Delete Originals**: Conversions are strictly non-destructive.
3. **Atomic Writes**: Generate to a temporary location (`NSTemporaryDirectory()`) and atomically move to the destination upon complete verification.
