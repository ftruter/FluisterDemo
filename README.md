# Fluister Demo

An iPhone/iPad **table captioner** for a social setting: several people talking, one person who can no longer hear (hearing aids gone, no lip-reading or SASL in time) but can still read. Fluister listens on this device, transcribes on this device, and shows who said what.

The Mac was the workshop. This app is the product shape: a large transcript, a **Start listening** button (Apple requires a tap before the microphone turns on), and **Afrikaans | English** for the UI.

Fluister (“to whisper” in Afrikaans) is DigiPhyte’s South African Whisper: Afrikaans, South African English, and the code-switching that is everyday SA speech. Stock Whisper drifts Afrikaans toward Dutch. This model does not. Audio never leaves the process.

## First: set your development team

The project ships with **no development team** — running on a device needs your own. In Xcode, select the `FluisterDemo` project, then for **both targets** (`FluisterDemo` and `FluisterDemoTests`) open **Signing & Capabilities** and pick your team under **Team** (signing is Automatic, so that is the only change). If you regenerate the project instead, pass your Team ID in the environment:

```sh
DEVELOPMENT_TEAM=YOURTEAMID ruby Scripts/generate_xcodeproj.rb
```

## Goal: voices you can tell apart

ASR alone dumps an unlabelled stream. That is unreadable at a table. Fluister:

1. Takes a **voice print** of each pause-delimited line (spectral fingerprint of the slice — not pitch).
2. Labels each new print **Speaker 1**, **Speaker 2**, … in its own colour, silently. Caption type uses Dynamic Type so it follows the user’s accessibility text size.
3. Naming is user-initiated only: tap **This is me…** to type a name for the last speaker; earlier lines from that voice are relabelled.

An earlier build had a spoken enrolment agent: a new voice made Fluister ask aloud *“We have a new participant in the conversation. What is your name?”* and parse the reply on-device. Field tests killed it — the recogniser transcribed straight past the answer instead of capturing it, and stopping the conversation did more harm than good. Fluister never interrupts to ask anything now.

## What you get today

- Live microphone transcription with [WhisperKit](https://github.com/argmaxinc/WhisperKit)
- **Start listening** / **Stop listening** (user-initiated capture)
- While listening, an input level meter to the right of the red **Stop listening** button shows the microphone is live
- Segmented **Afrikaans | English** UI (and recognition) language
- The rest of the screen is the transcript — except the first-run Core ML compile
- Live partial updates; 1.2 s of trailing silence commits the line — the committed text comes from one clean decode of the whole utterance (with temperature fallback), not from the last streaming partial, so trailing words are never lost to a stale preview
- A **stable live line**: earlier decodes restarted the sentence token-by-token every 0.3 s and re-rendered settled words (“power” → “public”), so the line collapsed and re-typed itself constantly. `PartialStabiliser` locks words once two consecutive decodes agree; locked text repaints only when two consecutive decodes settle on the same correction, and mid-decode updates are append-only. Churn is confined to the last few words
- New voices are auto-labelled **Speaker 1**, **Speaker 2**, … in their own colours; **This is me…** names the last speaker
- The screen stays awake while listening — auto-lock is suspended during a session and restored when it ends
- On-device only: audio never leaves the process

You need an **Apple Silicon iPhone or iPad**, Xcode 16+, and a one-time download of the Fluister-turbo WhisperKit folder (~1.6 GB) from Hugging Face.

## The model

This repository does **not** contain weights. On launch the app asks [`FTruter/fluister-turbo-coreml`](https://huggingface.co/FTruter/fluister-turbo-coreml) for the date and size of the latest Core ML package.

- No local copy: **Download the speech recognition model (N GB)**. Listening stays off until that finishes and the checksums match.
- Local copy is current: **Start listening**.
- Local copy is older: listening still works; **Update the speech recognition model (N GB)** only starts if you tap it. The old files stay until the new folder is complete and the SHA-256 values in `manifest.json` match.

The live folder is replaced only after the incoming copy verifies. A listen session that is already open keeps the old files until you stop.

Tests can still point at a converted folder with `FLUISTER_MODEL_FOLDER` (or `Scripts/link-model.sh`). That path is not offered in the UI.

The Hub tree nests the WhisperKit folder:

```
fluister-turbo-v2/
  MelSpectrogram.mlmodelc/
  AudioEncoder.mlmodelc/
  TextDecoder.mlmodelc/
  tokenizer.json
  config.json
  manifest.json
```

The app downloads that inner folder (not the repo-root README/LICENSE) into Application Support as `fluister-turbo-v2`.

`TextDecoderContextPrefill.mlmodelc` is optional and is not in this build.

## Build

Open `FluisterDemo.xcodeproj` in Xcode, select an **iPhone** or **iPad**, Run. Grant microphone access when asked. **Start listening** stays off until Core ML has compiled for this GPU/ANE (first launch can take a minute).

```sh
xcodebuild -scheme FluisterDemo -destination 'platform=iOS Simulator,name=iPhone 16' build
```

## Tests

`Cmd-U` downloads **500** speaker-diverse 30-second clips from [`andreoosthuizen/afrikaans-30s`](https://huggingface.co/datasets/andreoosthuizen/afrikaans-30s) (not stored in git) and runs them through the local Fluister-turbo Core ML / Metal conversion. The sermons are slow, so each clip is also replayed at **1.5× and 2.0×** by sample-rate conversion (same PCM, treated as a higher capture rate, then resampled back to Whisper’s 16 kHz) to approximate faster talkers. Each clip is its own test case with its own 10-minute time allowance — as one monolithic test the sweep blew the runner’s 1-hour limit whenever the WAV cache was cold — and a per-clip WER ceiling: native below 0.70, 1.5× below 0.85, 2.0× below 1.00. The 2.0× rate is a stress test where isolated clips are known to collapse (measured worst 0.99 across the 500-clip sweep), so its ceiling only catches hallucination loops, whose insertions push WER past 1.0; per-rate aggregates live in the eval CSV.

Wavs land in the app’s Caches folder under `truter.com.fluister.demo.tests/afrikaans-30s/`.

Watch the run in **Console.app**: subsystem `truter.com.fluister.demo.tests`, category `AfrikaansASR`. Rows are also flushed to a CSV next to the wavs (usable if you stop mid-run).

Columns: `Index,Rate,Duration(s),WER,Temperature,SourceWAVPath`. Sort by WER vs rate, then open `SourceWAVPath` to inspect the sermon clip (audio_id in the filename is the speaker/source).

A second eval, `livePipelineWERTracksWholeClipDecode`, replays a speaker-diverse subset of 40 clips through the exact pipeline the app ships — the same 100 ms energy frames, the same silence segmentation, one final decode per utterance — and compares it against whole-clip decoding. Live mean WER must stay below 0.25 and within 0.10 of the whole-clip number, so a streaming-policy regression fails even when the model itself is fine. Measured on device: live 0.067 against whole-clip 0.057, a gap of 0.010 — streaming costs about one word in a hundred.

This eval caught the live-accuracy fix now baked into `LiveListen`: the Fluister fine-tune was not trained with `<|startofprev|>` previous-text conditioning, and decodes conditioned on the previous caption come back **empty** — 0.41 mean WER prompted against 0.06 unprompted — so live decoding never sets `promptTokens`. Utterances commit after 1.2 s of trailing silence (a breath at a sentence break must not split the line), and slices with under 0.7 s of voiced audio are dropped as decoder noise rather than becoming captions.

You need a Fluister-turbo folder (`FLUISTER_MODEL_FOLDER` or `Scripts/link-model.sh`). Without it `fluisterModelIsInstalled` **fails** — one loud failure; the 500 per-clip cases are disabled rather than producing 500 duplicates.

Memory discipline matters on device: the model is ~1.6 GB resident, and **two WhisperKit instances alive at once get the test runner jetsam-killed**. Everything that decodes therefore lives in one `.serialized` suite sharing a single `AfrikaansEvalKit` instance, and the app itself stays dormant while hosting tests — before that guard, `RootView`’s bootstrap loaded a second model inside the test host and the live UI once started a real microphone session mid-sweep, killing the run.

Hymns, singing, and unusable microphone noise are dropped in `Scripts/select-afrikaans-clips.py` and replaced from the same sermon so the suite stays at 500 spoken clips.

To rebuild the 500-clip manifest (round-robin across sermons/speakers, seed `20260913`):

```sh
python3 Scripts/select-afrikaans-clips.py
```

## Contributing 

Any contributions welcome. Just raise a PR and ask FTruter to review. A good place to start would be with the [AI Critique](./CRITIQUE.md). 

## Credits

- **DigiPhyte** — Fluister-turbo (MIT)
- **OpenAI** — Whisper large-v3-turbo (Apache 2.0)
- **Argmax** — WhisperKit / whisperkittools (MIT)

See `NOTICE`. Training data licences are listed there (CC BY). If you ship this model, credit DigiPhyte.

## Licence

The app source is MIT (`LICENSE`). Whisper’s Apache 2.0 text is `LICENSE-whisper-apache-2.0.txt`.
