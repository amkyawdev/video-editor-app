# Project documentation — Amkyaw Studio

This document explains how the app is put together, what is verified, and where
the sharp edges are. It is deliberately explicit about the difference between
"implemented" and "verified on a device".

## 1. Product scope

- **Video editor**: import video/audio/image, one primary video track with
  transitions, optional overlay video tracks, multiple audio tracks, subtitle
  lane. Trim, split, reorder, merge contiguous clips, speed, volume, mute, crop,
  rotate, fit/fill, zoom/pan, colour grade, B&W, mirror, vignette.
- **Subtitle editor**: cue authoring with timing, style, position, SRT/WebVTT
  import/export, ASS burn-in, soft subtitle muxing.
- **Offline translation**: SRT/TXT → Myanmar using a local GGUF model, with
  editable output. No TTS, no cloud.
- **Local Movie Recap**: FFmpeg evidence extraction + optional local ASR and
  vision captions + optional local script model, with honest fallbacks.
- **Model library**: 12 verified GGUF catalog entries, resumable downloads,
  validation, selection and deletion.

Out of scope: iOS, cloud accounts, Firestore, collaboration, TTS, speech
generation, automatic scene semantic understanding without a local vision model.

## 2. Layer map

| Layer | Files | Notes |
|---|---|---|
| Bootstrap | `lib/main.dart`, `lib/app.dart`, `lib/state/app_services.dart` | Composition root; FFmpeg capability probe; providers |
| Domain models | `lib/data/models/*` | Immutable-ish models with JSON; microseconds for all time |
| Persistence | `lib/data/repositories/*` | Project JSON with media/thumbs/exports beside it; SharedPreferences for selections |
| Media I/O | `lib/data/services/media_importer.dart`, `ffmpeg/media_probe_service.dart`, `ffmpeg/media_extraction_service.dart` | Copies imports, probes streams, thumbnails, waveform, scene frames, 16 kHz WAV, loudness |
| Render planning | `lib/data/services/ffmpeg/export_command_builder.dart` | Pure timeline → FFmpeg args, transitions, mixing, subtitle mapping, validation |
| Render execution | `lib/data/services/ffmpeg/render_service.dart` | Session lifecycle, stats, cancel, failure logs, output verification |
| Subtitle codecs | `lib/data/services/subtitle/*` | SRT, WebVTT, ASS, extension guards |
| Model catalog | `lib/data/services/models/model_catalog.dart` | Verified metadata; no fabricated URLs/sizes |
| Model install | `lib/data/services/models/model_library_service.dart`, `gguf_inspector.dart` | Range resume, storage check, size/header validation, delete |
| LLM runtime | `lib/data/services/ai/llama_runner.dart`, `asr_service.dart` | One llama.cpp engine at a time; serialized jobs; Qwen3-ASR adapter |
| Transliteration/translation | `lib/data/services/ai/translation_service.dart` | SRT/TXT only, batching, retries, per-cue fallback, progress events |
| Recap | `lib/data/services/ai/recap_service.dart`, `recap_planner.dart` | Staged pipeline, evidence report fallback, TXT/SRT export |
| UI state | `lib/state/*_controller.dart`, `timeline_ops.dart` | ChangeNotifier controllers; pure timeline mutations |
| UI | `lib/features/*`, `lib/widgets/*` | Premium dark mobile UI; responsive preview; animated panes |

## 3. Data model

- `Project`: id, name, canvas, fps, tracks, media, subtitle document, export
  settings, cover path. Timeline math uses integer microseconds to avoid drift.
- `Track`: video (primary sequential or overlay with explicit offsets) or audio.
  `Track.startsUs` computes primary layout with transition overlap; overlay and
  audio use `timelineStartUs`.
- `Clip`: asset id, source in, timeline duration, speed, volume, mute, rotation,
  fit, scale, pan, opacity, crop, grade, effects, transition.
- `SubtitleDocument`: cues + style + language; `fixOverlaps()` and `shiftAll()`.
- `SubtitleStyle`: font family, size (relative to 1080p), colours, outline,
  shadow, background, bold/italic, alignment, margins, spacing, line height.
- `ExportSettings`: container, video/audio codec, resolution, fps, bitrates,
  subtitle mode + soft codec, file name; validity matrices live on the enums.

## 4. Render pipeline

For each primary clip:
`setpts` → crop → rotate → scale/pad or cover → zoom/pan crop → `eq` →
effects → `fps` → `sar` → `yuv420p`.

- **Transitions** split the clip list into segments. Hard cuts inside a segment
  use `concat`; segment boundaries with a transition use `xfade` at
  `offset = accumulated duration − transition`, clamping to half of each side
  and falling back to concat when too short. Audio mirrors this with
  `acrossfade`.
- **Overlay tracks**: clips get a timestamp shift (`setpts=PTS-STARTPTS+start/TB`)
  and are composited with `overlay=...:enable='between(t,start,end)'`, RGBA with
  opacity.
- **Audio**: per-clip `atempo` (chained outside 0.5–2.0), volume, 48 kHz stereo
  `fltp`; silent video clips use `anullsrc`; extra lanes get `adelay`; everything
  mixes with `amix=normalize=0`, then `atrim`/`apad` to the project duration.
- **Padding**: audio/subtitles longer than video clone the last frame with
  `tpad`.
- **Subtitles**: burn-in adds `subtitles=filename=...:fontsdir=...`; soft mode
  maps a sidecar with the container's codec. Fonts are materialized from Flutter
  assets into a cache directory for libass.
- **Output**: encoder-specific flags, even dimensions, `+faststart` for MP4,
  `hvc1` tag for H.265, metadata stripped, `-t` for exact runtime, `-y`.
- **Cancellation**: RenderService calls `FFmpegKit.cancel(sessionId)` and maps it
  to a cancelled state. Failure includes the final log tail. Success is only
  reported when the output file exists and is non-empty.

## 5. Model matrix and runtime constraints

llama.cpp runs in-process through `llamadart`, which resolves native archives at
build time. There is no cloud fallback. Model files are loaded from app storage
and kept resident until another model is requested; jobs are serialized so two
pipelines never share a KV cache.

| Capability | Model | Notes |
|---|---|---|
| Translation (Burmese evidence) | Hy-MT3 1.8B/7B/30B-A3B | Card lists `my`; 8192 context |
| Translation (Burmese-specific) | Qwen 1.5B Burmese SFT, ShweYon 1.5B, Qwen2.5 0.5B Burmese, Burmese-GPT 7B | No published subtitle benchmark; two entries have no declared licence |
| Vision captions | Qwen2.5-VL 3B + mmproj | Needed for recap frame understanding |
| ASR | Qwen3-ASR 0.6B + mmproj | 30 languages; **no Burmese** |
| Server-only reference | MiniMax-M2 UD-IQ1_S | ≈64 GB, multi-shard, not downloadable in-app |

Integrity: expected byte size + GGUF header parse. No SHA-256 is published in the
catalog, so a hash cannot be verified; the app says so rather than pretending.

Storage: downloads require the model size plus 15% headroom; free space is read
with `df` when available. Downloads resume from `.part` files with HTTP Range.

## 6. Movie Recap stages and honesty rules

`preparing → probing → extractingAudio → samplingFrames → transcribing →
captioning → scripting`. Every stage reports real progress from FFmpeg or
llama.cpp.

Rules enforced in code and UI:

1. A text-only model never receives images.
2. Without transcript or captions, the service returns an evidence report and
   the UI disables SRT export.
3. ASR is only attempted when an ASR model is installed; failures are surfaced
   as warnings and do not fabricate a transcript.
4. No TTS or speech generation exists anywhere.
5. Warnings list missing capabilities (no ASR, no vision, no script model,
   unsupported languages).

## 7. Testing

Current automated coverage:

- SRT/VTT parsing (BOM, CRLF, multi-line, Myanmar), ASS style/timing/escaping,
  cue operations (`test/subtitle_codecs_test.dart`).
- Timeline split/trim/speed/merge/reorder/audio placement
  (`test/timeline_ops_test.dart`).
- Project JSON round-trip, duration math, export settings
  (`test/project_model_test.dart`).
- FFmpeg command builder: burn-in, soft mapping, transitions, speed, mixing,
  silent output, crop/rotate/grade/effects, WebM matrix, invalid combos, overlay,
  tpad (`test/export_command_builder_test.dart`).
- Translation batching/prompts/parsers/guards
  (`test/translation_planner_test.dart`).
- Recap sentence split, SRT distribution, script parsing, evidence-report
  honesty (`test/recap_planner_test.dart`).
- Model catalog integrity/URLs/sizes/licences/Burmese evidence
  (`test/model_catalog_test.dart`).
- GGUF header inspector and probe JSON parsing.
- Widget tests: home render, new-project sheet, entering the editor, existing
  project list.

Manual device checklist (not executed here):

1. Import a 1080p MP4 and a portrait clip; confirm thumbnails and probe data.
2. Split/trim/speed and verify preview transitions.
3. Add a music lane and confirm export mixing with headphones.
4. Author Myanmar cues, verify shaping, outline and background; export burn-in
   and soft MKV.
5. Import SRT, translate with Hy-MT3 Q4, edit cues, save.
6. Install Qwen3-ASR and Qwen2.5-VL; run recap on an English clip; confirm frame
   captions and script; try a Burmese clip and confirm the ASR warning.
7. Cancel a render and confirm no partial file is reported as success.
8. Rotate the device during editor use; confirm no overflow.

## 8. Known limitations

- No device/emulator run in this environment (`/dev/kvm` absent). Runtime media
  preview, FFmpeg execution and model inference are unverified.
- Overlay video is not composited in the in-app preview.
- Multi-track audio preview mixes only the active audio clip under the playhead.
- Soft subtitle styling is limited by container/codec (MP4 plain text).
- Burmese translation quality and ASR coverage are not benchmarked; only
  model-card evidence is reported.
- AV1/VP9 encoding is slow on phones and not hardware-accelerated.
- No background render service/notification; long renders need the app open
  (screen kept awake during export).
- Firebase Auth is blocked by the Android package mismatch; no auth code exists.
- No iOS target, no release assets yet.

## 9. Security and privacy

- All user content and models remain in app-private storage.
- Only model downloads use the network; URLs are fixed Hugging Face paths.
- No secrets are stored in the repository. `google-services.json` and signing
  material are ignored; CI reads signing values from secrets and deletes the
  temporary keystore after the build.
- Logs may include FFmpeg error text and file paths, but never paste model or
  auth secrets.

## 10. Roadmap

1. Verify on a physical device and record the checklist results.
2. Multi-track audio preview with drift correction; overlay preview.
3. Split-screen player for A/B trims.
4. Optional hardware encoder (`mediacodec`) with capability fallback.
5. Firebase Auth once a matching Android app config exists.
6. Benchmarked Burmese translation defaults.
