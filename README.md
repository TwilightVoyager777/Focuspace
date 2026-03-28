# Focuspace

![Swift](https://img.shields.io/badge/Swift-6.0-FA7343?logo=swift&logoColor=white)
![iOS](https://img.shields.io/badge/iOS-17.0+-000000?logo=apple&logoColor=white)
![SwiftUI](https://img.shields.io/badge/SwiftUI-5-0D96F6?logo=swift&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-iPhone%20%7C%20iPad-lightgrey?logo=apple)
![Apple Intelligence](https://img.shields.io/badge/Apple%20Intelligence-iOS%2026+-black?logo=apple)
![License](https://img.shields.io/badge/License-MIT-green)

> A real-time AI composition coach for iPhone and iPad — guides your framing live through a HUD, powered by on-device Vision tracking and Apple Intelligence.

---

## What It Does

Focuspace overlays a live guidance HUD on your camera viewfinder. Tap a subject, choose a composition template, and the app calculates how far your frame is from the ideal composition in real time. An animated reticle and directional arrows tell you exactly how to move the camera. When the frame locks in, **Smart Compose** smoothly tightens the zoom.

The AI Coach has two tiers:

| Tier          | Engine                                | Availability                            |
| ------------- | ------------------------------------- | --------------------------------------- |
| Deterministic | Rule-based geometry engine            | Always on                               |
| Semantic      | Apple Intelligence (FoundationModels) | iOS 26+, device with Apple Intelligence |

On supported devices the on-device language model reads the scene — subject position, drift, structural tags — and picks the most appropriate composition template automatically.

---

## Composition Templates

| ID                  | Name                 | Philosophy                                        |
| ------------------- | -------------------- | ------------------------------------------------- |
| `rule_of_thirds`    | Rule of Thirds       | Let the subject breathe within the frame          |
| `golden_spiral`     | Golden Spiral        | Guide attention along a quiet curve               |
| `center`            | Center Composition   | Centering creates calm, confident focus           |
| `symmetry`          | Symmetry             | Mirror the scene for a refined order              |
| `leading_lines`     | Leading Lines        | Use lines to draw focus with intent               |
| `framing`           | Framing              | Build a visual window for the subject             |
| `negative_space`    | Negative Space       | Let emptiness amplify the subject                 |
| `portrait_headroom` | Portrait Headroom    | Place eyes with intent and keep headroom clean    |
| `triangle`          | Triangle Composition | Triangles add balance and strong visual structure |

---

## Architecture

```
┌──────────────────────────────────────────────────┐
│                  CameraScreenView                 │
│   (adaptive layout: iPhone / iPad portrait /     │
│    iPad landscape sidebar rails)                  │
│                                                  │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐  │
│  │  TopBarView│  │ViewfinderView  │BottomBarView│  │
│  │ (template  │  │            │  │ (shutter / │  │
│  │  picker)   │  │  live HUD  │  │  gallery / │  │
│  └────────────┘  │  overlays  │  │  template) │  │
│                  └─────┬──────┘  └────────────┘  │
└────────────────────────┼─────────────────────────┘
                         │
          ┌──────────────┼──────────────┐
          ▼              ▼              ▼
  ┌──────────────┐ ┌───────────┐ ┌───────────────┐
  │CameraSession │ │  Frame    │ │  AI Coach     │
  │Controller    │ │  Guidance │ │  Coordinator  │
  │              │ │  Coord.   │ │               │
  │ AVFoundation │ │ Template  │ │ Deterministic │
  │ CameraFilter │ │ RuleEngine│ │ Engine        │
  │ SmartCompose │ │ Guidance  │ │ +             │
  │ StateCtrl    │ │ Stabilizer│ │ FoundationModel│
  └──────┬───────┘ └─────┬─────┘ │ (iOS 26+)    │
         │               │       └───────────────┘
         ▼               ▼
  ┌──────────────┐ ┌───────────────────────────┐
  │ Vision Stack │ │   Guidance HUD Views      │
  │              │ │                           │
  │ VisionObject │ │ Arrow / Reticle / Dot /   │
  │ Tracker      │ │ Crosshair / Scope HUDs    │
  │ FaceSubject  │ │ TemplateOverlayEngine     │
  │ Analyzer     │ │ GridOverlay / LevelOverlay│
  └──────────────┘ └───────────────────────────┘
```

---

## Directory Structure

```
Focuspace.swiftpm/
├── Package.swift                   # Swift Package / iOS app manifest
├── Views/
│   ├── System/
│   │   ├── MyApp.swift             # @main entry point
│   │   ├── ContentView.swift       # Root view → CameraScreenView
│   │   └── SettingsView.swift
│   ├── Camera/
│   │   ├── CameraScreenView.swift  # Adaptive layout (iPhone / iPad)
│   │   ├── ViewfinderView.swift    # Live preview + HUD mount point
│   │   ├── TopBarView.swift        # Template picker rail
│   │   └── BottomBarView.swift     # Shutter, zoom, gallery, SmartCompose
│   ├── Guidance/                   # All HUD overlay views
│   │   ├── ArrowGuidanceHUDView.swift
│   │   ├── GuidanceReticleHUDView.swift
│   │   ├── GuidanceCrosshairView.swift
│   │   ├── GuidanceLayeredDotHUDView.swift
│   │   ├── CenterGuidanceHUDView.swift
│   │   ├── BreathingDotView.swift
│   │   ├── AICoachDebugHUDView.swift
│   │   └── GuidanceDebugHUDView.swift
│   ├── Overlays/
│   │   ├── TemplateOverlayEngine.swift   # Renders composition grid lines
│   │   ├── TemplateOverlayView.swift
│   │   ├── GridOverlayView.swift
│   │   ├── LevelOverlay.swift
│   │   └── FilteredPreviewOverlayView.swift
│   ├── Templates/
│   │   ├── CompositionLabView.swift      # Browse templates with examples
│   │   ├── TemplateRowCardView.swift
│   │   └── TemplateRowView.swift
│   └── Library/
│       ├── MediaLibraryView.swift
│       └── GalleryView.swift
├── Data/
│   ├── CameraService.swift               # AVCaptureSession setup
│   ├── CameraSessionController.swift     # Main camera state controller
│   ├── CameraFilterController.swift      # Live filter pipeline
│   ├── LiveFilterPreviewRenderer.swift
│   ├── FrameGuidanceCoordinator.swift    # Per-frame composition eval
│   ├── AICoachCoordinator.swift          # AI Coach (deterministic + FM)
│   ├── AICoachDeterministicEngine.swift
│   ├── AICoachModels.swift
│   ├── AICoachStructuralTagBuilder.swift
│   ├── SmartComposeStateController.swift # Auto-zoom when locked
│   ├── SmartComposeRecommendationResolver.swift
│   ├── CompositionOverlayController.swift
│   ├── CapturedPhotoProcessor.swift
│   ├── RecordingStateController.swift
│   ├── LocalMediaLibrary.swift
│   ├── DeviceControls.swift
│   └── templates.json                    # Composition template definitions
├── Models/
│   ├── CompositionTemplateCatalog.swift  # Loads templates.json
│   ├── TemplateItem.swift
│   ├── TemplateRegistry.swift
│   ├── MediaItem.swift
│   └── ToolItem.swift
├── Component/
│   ├── Guidance/                         # GuidanceStabilizer, contracts
│   ├── Tracking/
│   │   ├── VisionObjectTracker.swift     # Vision NCC object tracking
│   │   └── SubjectTrackerNCC.swift
│   ├── Vision/
│   │   └── FaceSubjectAnalyzer.swift     # Face observation for headroom
│   ├── CameraPreviewView.swift
│   ├── ShutterButtonView.swift
│   ├── RulerControl.swift
│   ├── BottomControlsView.swift
│   └── Settings/DebugSettings.swift
├── Modifiers/
│   ├── LivePreviewCropModifier.swift
│   └── Rules/
│       ├── TemplateRuleEngine.swift      # Per-template geometry rules
│       ├── CenterRuleEngine.swift
│       ├── SymmetryRuleEngine.swift
│       └── TemplateRuleTypes.swift
└── Assets.xcassets/
```

---

## Requirements

| Item               | Requirement                                                  |
| ------------------ | ------------------------------------------------------------ |
| Xcode              | 16+ or Swift Playgrounds 4.5+                                |
| iOS                | 17.0+                                                        |
| Device             | iPhone or iPad with a rear camera                            |
| Apple Intelligence | iOS 26+ device (optional — falls back to deterministic engine) |

> The app runs fully offline. Apple Intelligence enhances template selection but is never required.

---

## Quick Start

### Swift Playgrounds

1. Open `Focuspace.swiftpm` in **Swift Playgrounds 4.5+** on iPad or Mac.
2. Tap **Run**.

### Xcode

```bash
open /path/to/Focuspace.swiftpm
```

Select a physical device (camera access is required), then press **⌘R**.

> Simulator does not provide a real camera feed — run on device for full functionality.

---

## How the AI Coach Works

```
Each camera frame
       │
       ▼
VisionObjectTracker (Vision NCC)
  └─ subject position + confidence
       │
       ▼
FaceSubjectAnalyzer
  └─ face bounding box for portrait headroom
       │
       ▼
FrameGuidanceCoordinator
  └─ TemplateRuleEngine → raw dx/dy guidance vector
  └─ GuidanceStabilizer2D → smoothed, noise-filtered vector
  └─ isHolding flag (true when frame is well-aligned)
       │
       ├──► HUD Views (arrow, reticle, dot, crosshair)
       │
       └──► AICoachCoordinator
              ├─ AICoachDeterministicEngine
              │   always available — geometry-based scoring
              └─ FoundationModelCoachRuntime (iOS 26+)
                  on-device LLM reads scene summary,
                  structural tags, drift → picks best template
```

**Smart Compose** watches the `isHolding` flag. After several consecutive aligned frames, it gradually tightens the zoom to finalize the composition automatically.

---

## Tech Stack

| Layer               | Technology                                      |
| ------------------- | ----------------------------------------------- |
| UI Framework        | SwiftUI 5                                       |
| Camera              | AVFoundation                                    |
| Subject Tracking    | Vision (VNSequenceRequestHandler, NCC)          |
| Face Detection      | Vision (VNDetectFaceRectanglesRequest)          |
| AI Coach (base)     | Deterministic geometry engine                   |
| AI Coach (enhanced) | FoundationModels / Apple Intelligence (iOS 26+) |
| Overlays            | SwiftUI Canvas + GeometryReader                 |
| Media               | Photos / PhotosUI                               |
| Orientation Lock    | UIWindowScene                                   |

---

## License

[MIT](./LICENSE) © 2025 Focuspace
