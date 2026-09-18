**FluisterDemo** is a small but unusually serious iOS demo: on-device Afrikaans / SA English live captioning with WhisperKit, a custom silence-commit loop, a Hub-backed ~1.6 GB Core ML downloader, and a 500-clip WER harness. Two commits on `main` (`2026-09-13` then `2026-09-18`), MIT app source, Whisper Apache 2.0 notice, 0 stars / 0 issues / no CI. The latest commit is explicitly co-authored with Claude. That is not a problem by itself; it does show in leftover Mac paths, dead enrolment code, and a few Sharp Edges that a human pass should still own.

What follows is a review of the tree as of `5759a64`, not a rebuild.

---

## What it is trying to be

The README is the strongest part of the repo. It states a real product, not a model card:

- table captioner for a person who can read but not hear
- audio never leaves the process
- user tap before the mic (Apple policy)
- Afrikaans forced so stock Whisper does not slide into Dutch
- spoken enrolment killed after field tests because it interrupted the table and missed the answer

That last point is rare and good. Most demos would have shipped the talking agent.

The code mostly matches that story. `LiveListen` exists because WhisperKit’s `AudioStreamTranscriber` was a poor fit (session-long re-encode, 1 s window clip, “Waiting for speech…” junk). The live policy is extracted as a pure `LiveListenSegmenter` so the eval harness segments the same way as the app. That is the right split.

---

## What is genuinely good

**1. The live decode policy is evidence-driven.**  
The Fluister fine-tune was not trained with `<|startofprev|>`. Prompted live WER ~0.41 vs unprompted ~0.06 is written into `LiveListen`, `LiveListenTests`, and `livePipelineWERTracksWholeClipDecode`. Streaming never sets `promptTokens`. Final commits use temperature fallback; partials do not. Utterances need 1.2 s trailing silence and ≥0.7 s voiced audio. Those numbers are not cargo-culted.

**2. `PartialStabiliser` solves a real UI bug.**  
Streaming Whisper rewrites the whole line every 300 ms (“power” → “public”). The two-pass lock + append-only live updates + grow-only caption height is the kind of product detail that makes a table usable.

**3. Model delivery is production-shaped, not demo-shaped.**  
Staging folder, SHA-256 via `manifest.json`, Range resume, atomic promote with `.outgoing` rollback, “keep listening on the old weights until Stop”, env override for tests only. `ModelStore` / `ModelDownload` / `RemoteModel` are the largest files and they earn it.

**4. The test suite is the real artefact.**  
Swift Testing, shared test plan, serialized suite, single `AfrikaansEvalKit` because two WhisperKit instances jetsam the device, host process stays dormant (`XCTestCase` / `XCTestConfigurationFilePath` guard in `FluisterDemoApp`). Per-clip 10-minute budget so a cold WAV cache does not blow the 1-hour runner. Live-pipeline eval on 40 clips with an explicit gap budget (live mean < 0.25 and within 0.10 of whole-clip). That is how you protect a streaming policy from “the model is fine, the app is not.”

**5. Swift 6 / concurrency is taken seriously.**  
Default MainActor isolation, `Task.detached` around `AVAudioSession.setActive`, comments that name the `_swift_task_checkIsolatedSwift` trap. Generation counters on prepare and listen. That is not beginner SwiftUI.

**6. Licensing and localization are not afterthoughts.**  
`NOTICE` names DigiPhyte, OpenAI, Argmax, CC-BY training sets. String catalog with Afrikaans. Microphone usage string is honest. Dynamic Type on captions. 44 pt targets on the listen button and overflow menu.

Treat this as a strong workshop demo that already has field scars, not as a student Whisper wrapper.

---

## Architecture and product gaps

### Speaker ID is the claimed product and the weakest subsystem

The README leads with “voices you can tell apart.” Implementation is 20-band mean log-mel of voiced frames, cosine ≥ 0.80, running average blend. The file itself says this is not SpeakerKit / pyannote and cannot re-identify Fred across sessions.

Problems:

- **Tests only prove sine-wave self-similarity.** `VoicePrintTests` compares 180 Hz vs 180 Hz and 140 Hz vs 900 Hz. That does not exercise two humans at a table, overlapping speech, a kettle, or the same person after a sip of water.
- **Threshold 0.80 on 20 dimensions will collide.** A handful of relatives in one room is the actual use case. Expect Speaker 3 to steal Speaker 1 after a laugh.
- **Embeddings live only in RAM.** Clear transcript wipes speakers. Relaunch wipes speakers. The deaf user has to rename people every sitting.
- **Partials have no speaker.** The live line is anonymous until the 1.2 s commit. At a table that is when you most need the colour.
- **“This is me…” is first-person copy for a last-speaker action.** If two people spoke, the wrong row gets the name. There is no tap-a-row-to-name path.
- **`NameParser` + Foundation Models is dead weight.** Spoken enrolment was removed; `resolvedName` / `askFoundationModel` (`iOS 26`) is unused on the sheet path, which just trims a text field. Keep the heuristics if you ever restore voice enrolment; do not pretend Apple Intelligence is in the product.

If the claim is “who said what,” ship a real embedder (even a tiny WeSpeaker / ECAPA Core ML) or demote the claim to “colour tags for this sitting, best-effort.”

### The listen loop will get worse as the sitting gets longer

Every 50 ms, `listenLoop` does `Array(kit.audioProcessor.audioSamples)` — a full copy of the session buffer — then later copies the growing slice for a decode. WhisperKit already holds the samples. You then keep `lastCommittedAudio` for enrolment.

Implications at a Sunday lunch:

- memory grows with the session even though captions cap at 400
- decode start index is `committedSamples - overlap`, but the processor is never trimmed
- a two-hour sitting plus a 1.6 GB model is a jetsam candidate on older iPhones

Trim or ring-buffer the processor after each commit. Do not copy the world to take a level reading.

### `ModelDownloadRuntime` is a one-slot singleton

One `CheckedContinuation`, one `destination`. Files download sequentially, so the happy path works. Background launch via `handleEventsForBackgroundURLSession` plus `settleOrphan` is thoughtful.

Still fragile:

- empty entitlements; no `UIBackgroundModes`
- `allowsCellularAccess = true` on a **1.6 GB** package aimed at South Africa
- no Low Data Mode / Wi-Fi-only gate, no “this will use 1.6 GB cellular” confirmation
- 416 / 206 / `.part` / `.transfer` state machine is easy to desync if two tasks ever overlap
- Hub `usedStorage` can include README/LICENSE you do not download, so the progress bar can lie

A Wi-Fi default and an explicit cellular confirm would match the privacy/respect tone of the rest of the app.

### Product surface is still a workshop

- no saved transcript, no share sheet besides pasteboard, no export
- language toggle restarts recognition **and** the whole UI locale; a hearing user who wants English UI + Afrikaans ASR cannot have both
- captions drop from the front after 400 with no “earlier lines were removed” hint
- idle timer is disabled only while `.listening`; good — but there is no “keep awake while reading” option for the person who stopped the mic
- `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace` look like leftovers from dropping the model into Documents. Live weights now live in Application Support. iTunes file sharing on a mic app is a surprising surface
- `Colour.agent` and the AppKit branch that constructs a `UIColor` inside `NSColor` are Mac-workshop fossils. The AppKit path would not compile as written

---

## Code-level notes

**Concurrency.** `nonisolated(unsafe)` on `WhisperKit` / `audioProcessor` is documented and probably unavoidable. Still: `listenLoop` hops to MainActor many times per second (`shouldContinueListening`, `publishLevel`, `setPartial`, `partial.isEmpty`). That is correct isolation and also a UI jank source. Batch the publishes.

**`Transcriber` is a god object.** Phase machine, download, prepare, listen, captions, clipboard, enrolment, idle timer. `EnrolmentHost` and `ModelStore` are already extracted; the listen loop and caption store could follow. Tests cannot drive `Transcriber` without a real kit.

**Error handling is uneven.** Download failures while a local model exists are swallowed (`if models.hasLocal { return }`). Prepare failures surface. Checksum mismatch deletes one file and leaves the rest of staging — resume can then skip a now-wrong sibling if `plan` sees a full dest size.

**`bootstrap.sh` is stale.** It writes `FluisterDemo/Assets.xcassets/AppIcon.appiconset/AppIcon.png` and chmod’s `generate_xcodeproj.rb`. The app now uses `FluisterDemo/Assets/AppIcon.icon`. Running bootstrap will confuse the next person.

**README vs project.** README says Xcode 16+ / Apple Silicon device. Project is iOS 17, Swift 6, default MainActor. Comments mention iOS 27 `AVAudioSession` warnings and iOS 26 Foundation Models. Pick a floor and write it once. Simulator is mentioned in `xcodebuild` but the model will not run usefully there; say that.

**WER ceilings are honest and also loose.** Native clip WER `< 0.70`, 1.5× `< 0.85`, 2.0× `< 1.00` (hallucination-loop detector only). For a table captioner, 0.70 WER is every third word wrong. The live-pipeline numbers you measured (0.067 vs 0.057) are the ones that belong in the README hero section; the 0.70 ceiling belongs in a footnote as “don’t fail the suite on a hymn the filter missed.”

**Eval corpus bias.** 500 clips from `andreoosthuizen/afrikaans-30s`, sermons, 30 s, round-robin speakers, hymns dropped in Python. That is better than nothing and not a dinner table: no crockery, no two-talker overlap, no township English, no codeswitch mid-clause, no 80-year-old voice. The 1.5× / 2.0× resample approximates pace, not that acoustics.

---

## Security, privacy, compliance

Strengths: no audio upload, on-device decode, checksums before promote, tokenizer required before listen, mic permission requested at prepare.

Gaps:

- cellular 1.6 GB as above
- file sharing leftover
- logs include committed caption text (`privacy: .public`) — fine for a personal device, not fine if a sysdiagnose leaves the table
- Hugging Face is contacted on every launch (`refreshFromHub`) even when a model exists; that is metadata, not audio, but it is still a network call the README’s “on-device only” line should mention
- no App Privacy nutrition / no “what we send to Hugging Face” copy beyond the download button

The privacy story is still better than almost every cloud captioner. Tighten the wording so “audio never leaves” is not read as “the app never networks.”

---

## Repo hygiene

| Item | State |
|---|---|
| License / NOTICE | Good |
| `.gitignore` | Weights and WAVs ignored; correct |
| CI | None. The 500-clip suite cannot run in Actions without a device and 1.6 GB weights; a *unit-only* job (segmenter, stabiliser, checksum, name parser, download planner) would still catch a lot |
| Issues / PR template / CODEOWNERS | None |
| Topics / description | Description is accurate; add `whisper`, `coreml`, `afrikaans`, `accessibility` |
| `DEVELOPMENT_TEAM` empty | Documented; correct for a public repo |
| Icon | New `.icon` format plus marketing PNG; `bootstrap.sh` still points at the old appiconset |
| Tests in the host app | Correctly gated; do not regress that |

Two-commit history is fine for a first public drop. The Claude co-author line should not be treated as a quality stain; treat the leftover Mac / enrolment / file-sharing bits as the actual stain.

---

## Priority order if this is meant to leave the workshop

1. **Do not let the speaker story over-promise.** Either integrate a real embedding model or rewrite the README around “session-local colour tags.”
2. **Stop copying the entire sample buffer every poll.** Trim after commit.
3. **Wi-Fi default + size confirmation** on the 1.6 GB download.
4. **Persist names for the sitting** (Keychain or Application Support), and let the user tap a row to name it.
5. **CI for the pure tests** (`LiveListenTests`, `PartialStabiliserTests`, `ModelChecksumTests`, `RemoteModelTests`, `NameParserTests`). Keep the 500-clip sweep as a device-only job.
6. **Delete or quarantine dead code:** `NameParser.resolvedName`, `Colour.agent`, AppKit `UIColor` branch, `UIFileSharingEnabled` unless you still drop models in Documents.
7. **Fix `bootstrap.sh`** or delete it in favour of the checked-in `xcodeproj`.
8. **Put the live-pipeline WER (0.067 / 0.057) in the README** and move the 0.70 per-clip ceiling out of the hero narrative.
9. **Decide language axes:** UI language vs recognition language vs system language are three things today treated as one picker.

---

## Verdict

This is a good demo of a hard problem — live on-device ASR for a language pair the industry ignores — with field-test humility that most Hugging Face companion apps never reach. The streaming policy, model staging, and eval harness are the parts I would steal.

It is not yet the table product the README describes. Speaker identity is a spectral heuristic with sine-wave tests. The listen loop copies too much. The download will happily eat a prepaid data bundle. Several files still remember the Mac workshop and the talking enrolment agent.

If the next commit is “real speaker embeddings + Wi-Fi-only download + row naming + unit CI,” this stops being a clever private workshop and starts being something you can put in front of the person the README is written for.
