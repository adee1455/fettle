# Fettle for Mac
> **Your files, in good shape.**  
> Official Website: [fettle.itsadee.com](https://fettle.itsadee.com)

**Fettle** is a minimal, premium, native macOS file conversion and action utility designed for seamless workflow integration. Files stay 100% private on your machine—never uploaded to the cloud, and original files are never overwritten.

Built specifically for Apple Silicon and macOS 14+, Fettle features an instant **Shift-drag Radial Menu** in Finder, an interactive **Action Picker**, native background job processing, and automatic in-place output saving with collision-safe naming.

---

## ✨ Key Features

- **🎯 Shift-Drag Radial Menu in Finder & Desktop**:
  - Select files in Finder or on your Desktop, start dragging, and tap/hold **Shift** (or **Command** / **Control**).
  - An intelligent radial menu appears around your cursor presenting smart context-aware conversion actions (e.g. PNG → WebP, JPEG, PDF; PPTX/DOCX → PDF; MP4 → MP3).
  - Tap number keys **`1`–`9`**, use arrow keys, or release directly over a slice to trigger instant conversion.
  - Press **`Esc`** at any time to immediately dismiss without performing actions.

- **⚡ Smart Action Picker (`Return` or `⌘R`)**:
  - Automatically identifies loaded file types and suggests the most relevant conversions first (marked with **SUGGESTED** badges).
  - Searchable by action title, target extension, or category.
  - Full keyboard navigation: **`↑` / `↓`** arrows to browse, **`Return`** to execute.

- **📁 In-Place Output & Original Preservation**:
  - Converted files save directly alongside your original files in their parent directory.
  - Automatic collision protection ensures original files are never overwritten (e.g., `photo (1).webp`).

- **🔔 Instant Completion Toast & Finder Reveal**:
  - Non-intrusive floating completion toast slides in when tasks finish.
  - One-click **"Show in Finder"** button highlights the newly generated output file in Finder.
  - Converted items in the file list display a green status pill with a Finder shortcut.

- **🔒 100% Private & Native**:
  - Powered by macOS built-in native engines: **Image I/O**, **PDFKit**, **CoreText**, and **AVFoundation**.
  - Silent background detection for optional external CLI tools (**FFmpeg**, **ImageMagick**, **qpdf**).

---

## 🚀 Supported Conversions & Actions

| Category | Native Actions | Optional CLI Enhancements |
| :--- | :--- | :--- |
| **Images** | PNG ↔ JPEG, Image → WebP, HEIC → JPEG, 50% Resize, Strip EXIF Metadata | Advanced format filters via ImageMagick |
| **PDF & Docs** | Merge Multiple PDFs, Images → PDF, Split PDF Pages, Text / RTF → PDF | PDF linearization & decryption via `qpdf` |
| **Media** | Video → MP4 (H.264 / HEVC), Audio Extraction (MP3, AAC, WAV), Video Thumbnail | GIF encoding & deep transcoding via `ffmpeg` |
| **File Actions**| Reveal in Finder, Copy Absolute Path, Duplicate File | — |

---

## ⌨️ Keyboard Shortcuts

| Shortcut | Description |
| :--- | :--- |
| **Hold `Shift` (during Finder drag)** | Open context-aware Radial Menu at cursor position |
| **`1` – `9`** | Trigger radial slice action directly |
| **`←` / `→` / `↑` / `↓`** | Cycle through radial actions or Action Picker items |
| **`Return`** | Execute selected action / Open Action Picker |
| **`Esc`** | Dismiss Radial Menu / Action Picker |
| **`⌘R`** | Open Radial Menu for current selection |
| **`⌘,`** | Open Settings (output folders, concurrent worker limits) |

---

## 🛠️ Building & Testing

### Requirements
- macOS 14.0 or later (Optimized for Apple Silicon `arm64`)
- Xcode 15 or later

### Build & Run Tests
```bash
# Run unit and integration tests (67 automated tests)
xcodebuild test -scheme Fettle -destination 'platform=macOS'

# Build Debug binary
xcodebuild -scheme Fettle -configuration Debug build
```

### Packaging Distribution Artifacts (.dmg & .zip)
Run the automated release packaging script:
```bash
./scripts/package.sh
```
This builds the `Release` configuration, ad-hoc codesigns the `.app` bundle, generates `dist/Fettle-macOS.dmg`, and creates `dist/Fettle-macOS.zip`.

---

## 📄 License
Fettle is open source under the MIT License.
