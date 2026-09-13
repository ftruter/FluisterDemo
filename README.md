# Fluister Demo

A small macOS app that **listens on this Mac and transcribes on this Mac**. No cloud, no Apple TV, no LAN session. It exists to prove that the Core ML / Metal conversion of [Fluister-turbo](https://huggingface.co/digiphyte/fluister-turbo-transformers) actually runs.

Fluister (“to whisper” in Afrikaans) is DigiPhyte’s South African Whisper: Afrikaans, South African English, and the code-switching that is everyday SA speech. Stock Whisper drifts Afrikaans toward Dutch. This model does not.

## What you get

- Live microphone transcription with [WhisperKit](https://github.com/argmaxinc/WhisperKit)
- Language forced to **Afrikaans** or **English** (autodetect stays off)
- Confirmed lines plus a live partial
- On-device only: audio never leaves the process

You need an **Apple Silicon Mac**, Xcode 16+, and the converted Fluister-turbo WhisperKit folder (~1.6 GB uncompressed).

## The model

This repository does **not** contain weights. Point the app at a folder that looks like this:

```
fluister-turbo-v2/
  MelSpectrogram.mlmodelc/
  AudioEncoder.mlmodelc/
  TextDecoder.mlmodelc/
  tokenizer.json
  config.json
```

`TextDecoderContextPrefill.mlmodelc` is optional.

### Convert it yourself

From a Fluister-turbo Transformers checkpoint:

```sh
# see FluisterTV Tools/convert/README.md, or:
whisperkit-generate-model \
  --model-version digiphyte/fluister-turbo-transformers \
  --output-dir ./out \
  --generate-decoder-context-prefill-data
```

Then **Listen → Choose model…** and select that folder. The app stores a security-scoped bookmark so you only pick it once.

Other ways to supply the folder:

- Environment: `FLUISTER_MODEL_FOLDER=/path/to/fluister-turbo-v2`
- Copy or symlink to `~/Library/Application Support/truter.com.fluister.demo/fluister-turbo-v2`
- Debug builds also look next to this repo for `FluisterTV/Tools/convert/out/fluister-turbo-v2`

```sh
./Scripts/link-model.sh
```

## Build

Open `FluisterDemo.xcodeproj` in Xcode, select **My Mac**, Run. Grant microphone access when asked.

```sh
xcodebuild -scheme FluisterDemo -destination 'platform=macOS' build
```

First Listen compiles Core ML for this GPU/ANE. That can take a minute. Later starts are faster.

## Credits

- **DigiPhyte** — Fluister-turbo (MIT)
- **OpenAI** — Whisper large-v3-turbo (Apache 2.0)
- **Argmax** — WhisperKit / whisperkittools (MIT)

See `NOTICE`. Training data licences are listed there (CC BY). If you ship this model, credit DigiPhyte.

## Licence

The app source is MIT (`LICENSE`). Whisper’s Apache 2.0 text is `LICENSE-whisper-apache-2.0.txt`.
