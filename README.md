# Amkyaw Studio

A local-first **video editor and subtitle studio** for Android, built with
Flutter. Cut a timeline, mix audio lanes, author Myanmar subtitles, translate
SRT/TXT offline with a local GGUF model, and render with FFmpeg — without an
account, a cloud upload or a text-to-speech engine.

> **Status: source-complete, device runtime unverified.** The project compiles,
> passes static analysis and the unit/integration test suite in this workspace,
> and debug APK / release AAB builds succeed. No APK has been run on a physical
> device or emulator here (no `/dev/kvm`), so media preview, FFmpeg execution
> and local LLM inference are **not yet verified on-device**. See
> [Feature status](#feature-status) for the exact split.

---

## Feature status

| Area | Status | Evidence |
|---|---|---|
| Project browser, local project storage, autosave, undo/redo | Implemented | `lib/data/repositories/project_repository.dart`, `lib/state/editor_controller.dart` |
| Media import (video/audio/image), probe, thumbnail, waveform | Implemented | `lib/data/services/media_importer.dart`, `lib/data/services/ffmpeg/media_extraction_service.dart` |
| Multi-track timeline: primary video, overlay video, audio lanes, subtitle lane | Implemented | `lib/data/models/*`, `lib/features/editor/widgets/timeline_view.dart` |
| Trim, split, reorder, merge adjacent clips, speed, mute/volume | Implemented | `lib/state/timeline_ops.dart` + tests |
| Crop, rotate, fit/fill, zoom/pan, colour grade, B&W, mirror, vignette | Implemented (command builder) | `lib/data/services/ffmpeg/export_command_builder.dart` |
| Transitions (`xfade`) + audio crossfade | Implemented (command builder) | same |
| Video preview + subtitle overlay | Implemented, not device-verified | `preview_stage.dart` |
| Multi-track audio preview | Partial: plays the active audio clip under the playhead | `preview_stage.dart` |
| Overlay preview | Not composited in preview; rendered on export | UI shows a badge |
| Subtitle authoring: cues, timing, styling, position, Myanmar font | Implemented | `subtitle_panel.dart`, `subtitle_studio_screen.dart` |
| SRT/VTT import and export | Implemented + tested | `lib/data/services/subtitle/*`, `test/subtitle_codecs_test.dart` |
| Burn-in subtitles via libass (automated ASS generation) | Implemented (command builder), not device-verified | `lib/data/services/subtitle/ass_writer.dart` |
| Soft subtitle tracks (MP4 mov_text, MKV SRT/ASS, WebM WebVTT) | Implemented with compatibility matrix | `export_settings.dart`, `export_command_builder.dart` |
| FFmpeg render: progress, cancel, failure logs, temp cleanup, output verification | Implemented, not device-verified | `lib/data/services/ffmpeg/render_service.dart` |
| GGUF model library: 12 verified entries, resumable downloads, size + GGUF-header validation, delete/select | Implemented (downloads not executed here) | `lib/data/services/models/*`, `lib/features/models/model_library_screen.dart` |
| Offline SRT/TXT → Myanmar translation with review/edit, cancel, progress | Implemented (inference not device-verified) | `lib/data/services/ai/translation_service.dart`, `lib/features/subtitles/translate_screen.dart` |
| Local Movie Recap: FFmpeg evidence, optional local ASR/vision, editable script, TXT/SRT export | Implemented, not device-verified | `recap_service.dart`, `recap_screen.dart` |
| Accounts / Firebase | Not included — the app runs fully offline | no auth code, no cloud |

| TTS (Piper, VieNeu, any speech synthesis) | **Deliberately absent** | no dependency/service/UI |
| iOS | Not configured (Android-only project) | — |
| App icon: SVG source + adaptive/legacy PNGs | Implemented | `assets/branding/icon.svg`, `tool/generate_icons.py` |

## Tech stack

- **Flutter 3.50.1 / Dart 3.14** (Material UI from `package:material_ui`)
- **FFmpeg 8.1.3** via `ffmpeg_kit_flutter_new` (full GPL: libx264, libx265,
  libaom, libvpx, libopus, libmp3lame, libass, libfreetype, libharfbuzz)
- **llama.cpp** via `llamadart` 0.21 (GGUF text, vision projector, Qwen3-ASR)
- `video_player`, `file_picker` (SAF), `provider`, `path_provider`,
  `shared_preferences`, `wakelock_plus`, `flutter_animate`, `intl`, `uuid`
- Bundled fonts: Inter, JetBrains Mono, Noto Sans Myanmar (OFL)

## Architecture

```
lib/
  app.dart, main.dart        composition root, providers, theme
  core/                      design tokens, time math, cancellation, font materializer
  data/models/               project, clip, track, subtitle, recap, export, GGUF model metadata
  data/repositories/         JSON project store, settings
  data/services/
    ffmpeg/                  probe, extraction, capabilities, command builder, render
    subtitle/                SRT, VTT, ASS writer, format guards
    models/                  catalog, resumable downloader, GGUF header inspector
    ai/                      llama.cpp runner, translation, recap, ASR
  state/                     ChangeNotifier controllers + pure TimelineOps
  features/                  home, editor (+panels/widgets), subtitles, recap, models, settings
  widgets/                   shared premium UI components
```

- **Local-first**: projects, imported media copies, models and exports live in
  app-private storage. Nothing is uploaded.
- **Truthful rendering**: the timeline becomes one deterministic FFmpeg command
  (`ExportCommandBuilder`, unit-tested). Progress comes from FFmpeg statistics
  or real pipeline stages, never fabricated.
- **AI boundaries**: GGUF is used for SRT/TXT translation and optional recap
  analysis only. It is never used for speech synthesis.

## Prerequisites

- Flutter SDK **3.50.x** (Dart 3.14), Android SDK 36, build-tools 36.0.0,
  **JDK 21** (AGP 9 requires JDK 17+)
- Android device/emulator with **API 24+**
- Network is needed for dependency resolution and **model downloads**; editing
  and inference work offline once installed

## Setup

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

Android SDK path (local only, never commit):

```bash
echo "sdk.dir=/path/to/Android/Sdk" > android/local.properties
```

Regenerate launcher icons from the editable SVG source:

```bash
python3 -m pip install pillow
python3 tool/generate_icons.py
```

The script writes legacy `mipmap-*/ic_launcher.png`, round icons, adaptive
foreground PNGs, and `assets/branding/icon-512.png`. Adaptive icon XML lives in
`android/app/src/main/res/mipmap-anydpi-v26/`.

## Accounts & cloud

Amkyaw Studio is fully offline and account-free. There is no login, no cloud sync, no telemetry and no Firebase integration in this build. Your projects, imported media, GGUF models and exports never leave the device.

If Firebase authentication is added later, it will require an Android client config whose package name matches the app's `applicationId`, and that config file must stay out of version control.

## Offline GGUF translation (SRT/TXT only)

- Input is restricted to **`.srt` and `.txt`**; `.vtt`, video and audio are
  rejected before inference.
- Cue IDs, timestamps, order and formatting are preserved; only cue text goes to
  the model. Batches use delimiter/numbered prompts with retry and per-cue
  fallback. Every translated cue is editable before saving.
- Default Android model: **Hy-MT3 1.8B Q4_K_M** (1,348,432,160 bytes,
  Apache-2.0). Its model card lists Burmese (`my`) among 102 languages and
  recommends temperature 0.7 / top_p 0.6 / top_k 20 / repetition penalty 1.05.
- Downloads resume via HTTP Range, are storage-checked, size + GGUF-header
  validated, cancellable, and stored per model. The catalog has no published
  SHA-256, so integrity is size + header (stated in the app).

### Verified catalog (sizes from the Hugging Face API)

| Model | Repo / file | Quant | Size (bytes) | Licence | Ctx | Burmese evidence | Tier |
|---|---|---|---|---|---|---|---|
| Hy-MT3 1.8B Q4 | `tencent/Hy-MT3-1.8B-GGUF` / `Hy-MT3-1.8B-Q4_K_M.gguf` | Q4_K_M | 1,348,432,160 | Apache-2.0 | 8192 | Yes — card lists `my` | Recommended |
| Hy-MT3 1.8B Q8 | same repo / `Q8_0` | Q8_0 | 1,908,528,448 | Apache-2.0 | 8192 | Yes | Capable |
| Hy-MT3 7B Q4 | `tencent/Hy-MT3-7B-GGUF` / `Q4_K_M` | Q4_K_M | 5,145,531,232 | Apache-2.0 | 8192 | Yes | Capable (8 GB) |
| Hy-MT3 30B-A3B IQ2 | `tencent/Hy-MT3-30B-A3B-GGUF` / `IQ2` | IQ2 | 13,083,836,064 | Apache-2.0 | 8192 | Yes | Server only |
| Qwen 1.5B Burmese SFT v2 | `mradermacher/Qwen-1.5B-Burmese-SFT-v2-GGUF` / `Q4_K_M` | Q4_K_M | 986,046,848 | Apache-2.0 | 32768 | Purpose-built Burmese | Recommended |
| ShweYon 1.5B Burmese v1.2.4 | `mradermacher/ShweYon_Qwen2.5-Burmese-1.5B-v1.2.4-GGUF` / `Q4_K_M` | Q4_K_M | 1,000,359,360 | **Not declared** | 32768 | Burmese model | Recommended (licence risk) |
| Qwen2.5 0.5B Burmese v1.1 | `mradermacher/Qwen2.5-0.5B-burmese-v1.1-merged-GGUF` / `Q4_K_M` | Q4_K_M | 397,808,064 | **Not declared** | 32768 | Burmese merge | Recommended (low quality) |
| Burmese-GPT 7B 2025 | `mradermacher/Burmese-GPT-7b_2025-GGUF` / `Q4_K_M` | Q4_K_M | 4,174,931,712 | **Not declared** | 4096 | Burmese base, unbenchmarked | High-end |
| Qwen2.5 3B Instruct | `Qwen/Qwen2.5-3B-Instruct-GGUF` / `q4_k_m` | Q4_K_M | 2,104,932,768 | Qwen licence | 32768 | Not explicitly verified | Capable |
| Qwen2.5-VL 3B + mmproj | `ggml-org/Qwen2.5-VL-3B-Instruct-GGUF` / Q4_K_M + mmproj Q8_0 | Q4_K_M | 1,929,901,056 + 844,757,728 | Apache-2.0 | 32768 | Vision, not translation | High-end |
| Qwen3-ASR 0.6B + mmproj | `ggml-org/Qwen3-ASR-0.6B-GGUF` / Q8_0 + mmproj Q8_0 | Q8_0 | 804,749,536 + 214,392,544 | Apache-2.0 | 4096 | **Burmese not in 30-language list** | Capable |
| MiniMax-M2 UD-IQ1_S | `unsloth/MiniMax-M2-GGUF` / two shards | UD-IQ1_S | 63,976,293,760 | MIT (repo card) | 196608 | Not verified | **PC/server only** |

RAM figures are estimates (`weights × 1.15 + overhead`), not measured on a
phone. Burmese quality is **not benchmarked** by this project; the app labels
per-model evidence and asks you to review every cue.

## Subtitle editing and FFmpeg rendering

- SRT/WebVTT parsing handles BOM, CRLF, missing indexes, cue settings,
  multi-line text and Myanmar Unicode.
- Cue timing: add at playhead, edit start/end, nudge, shift all, fix overlaps,
  delete. Styling: font (Noto Sans Myanmar / Inter / JetBrains Mono), size,
  colour, outline, shadow, background, alignment, margins.
- Burn-in writes an ASS script and calls `subtitles=filename=...:fontsdir=...`
  (libass) with the bundled fonts; preview uses the same style values.
- Soft tracks: MP4 `mov_text` (plain text only — styling needs burn-in), MKV
  `srt`/`ass`, WebM `webvtt`. Invalid container/codec pairs are blocked by the UI.
- Video export: H.264 / H.265 / AV1 / VP9, AAC / Opus / MP3 or no audio,
  480p–1080p or source, 24/25/30/60 fps, bitrate control, MP4 faststart.
- FFmpeg capabilities (encoders, filters, muxers) are probed at runtime; the
  export sheet disables options the bundled build does not contain.

## Local AI Movie Recap — honest limits

Stages (each real, visible and cancellable):

1. FFprobe metadata.
2. FFmpeg extracts a mono 16 kHz WAV + mean/peak loudness.
3. FFmpeg samples scene frames (`select='gt(scene,0.3)'`, capped, with timed
   fallback).
4. Optional local ASR with Qwen3-ASR (30 languages; **Burmese is not one**), or
   attach an SRT/TXT transcript.
5. Optional frame captions with Qwen2.5-VL only if its mmproj is installed.
6. Optional local script model writes TITLE / LOGLINE / RECAP using only the
   evidence.

If no analysis model is installed, or there is no transcript/caption evidence,
the app returns a clearly labelled **evidence report** (runtime, scene
timestamps, loudness, transcript excerpt) and disables SRT export. It never
invents plot details, and a text-only model is never said to "see" the video.
There is no TTS stage.

## Build, test and CI

```bash
dart format lib test tool
flutter analyze
flutter test                       # unit/integration suites; see widget-test note
flutter build apk --debug          # verified here: app-debug.apk (~558 MB universal)
flutter build appbundle --release  # verified here: app-release.aab (~296 MB)
```

**Verification in this workspace:** `flutter analyze` reports no issues;
**63 unit/integration tests pass** (codecs, timeline ops, project model, FFmpeg
command builder, translation planner, recap planner, model catalog, GGUF header,
probe JSON). The app-level widget test currently hangs in this headless
container (a minimal `MaterialApp` smoke widget test passes, so the hang is
specific to the full app tree) and is tracked. No device/emulator run has been
done.

- `.github/workflows/android.yml` runs on push/PR: format check, analyze, tests,
  debug APK, release AAB, artifact upload. Release signing uses the
  `AMKYAW_KEYSTORE_*` secrets when present, else debug-signs; the keystore is
  deleted after the build.
- `.github/workflows/release.yml` runs on `v*` tags: builds split release APKs +
  AAB, writes `SHA256SUMS.txt`, and publishes a GitHub Release only after
  successful build. **No release exists yet**; a release will be created only
  from a real successful build.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Export disabled | FFmpeg probe failed, no clips, or invalid container/codec pair. Open Export for the exact message. |
| Burn-in missing | Bundled build must expose the `subtitles` filter and fonts must materialize; check Settings → FFmpeg. |
| Soft subtitles unstyled | MP4 `mov_text` is plain text. Use MKV+ASS or burn-in. |
| Model download fails | Storage, network, or HTTP 403 from Hugging Face. Partial files resume. |
| GGUF rejected | Header/size check failed; delete and re-download. |
| Recap returns "evidence report" | No analysis model installed, or no transcript/vision evidence. Intentional. |
| Burmese ASR silent | Qwen3-ASR does not list Burmese; attach a transcript. |
| SDK build error | Create `android/local.properties` with `sdk.dir`; install platform 36 / build-tools 36.0.0. |

## Privacy and licensing

- No account, telemetry, analytics, ads, cloud sync or remote inference. Only
  model downloads use the network (fixed Hugging Face URLs).
- Imported media is copied into the project folder in app-private storage;
  deleting a project deletes those copies. Models and exports are app-private.
- No account, no telemetry, no cloud sync and no remote inference. Only
  model downloads use the network (fixed Hugging Face URLs).
- Licensed under **Apache License 2.0** (`LICENSE`). Bundled FFmpeg is GPL;
  review FFmpeg/FFmpegKit and each model's licence before distribution. Model
  metadata links to the upstream cards.

Contact: [@amkyawdev](https://github.com/amkyawdev)
