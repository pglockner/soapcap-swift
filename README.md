# soapcap-swift

A Mac app that turns a telehealth session into a **speaker-attributed
transcript** and a **drafted SOAP, DAP or BIRP note**, entirely on the Mac.
No cloud, no audio recorded, and nothing saved to disk unless you ask.

It has the same goal as [soapcap](https://github.com/pglockner/soapcap),
the command-line tool, and shares its prompts and test cases. It is its own
implementation: one window that captures, de-identifies and drafts by
itself.

**Beta.** Everything below works. The app is a signed, notarized download
from [jukenzie.com](https://jukenzie.com); for a finished command-line
tool, use soapcap.

**Not a medical device.** Soapcap drafts notes for a clinician to check; it
does not diagnose or advise. A language model writes the draft, and it can
leave out what was said or add what wasn't: read every note before it goes in
a record. It is free software provided as is, with no warranty (see
[LICENSE](LICENSE)).

To report a problem, use **Help › Report a Problem…** in the app, or write
to support@jukenzie.com. This repository doesn't take issues.

[How it works](#how-it-works) ·
[Requirements](#requirements) ·
[Install](#install) ·
[Build and run](#build-and-run) ·
[Using the app](#using-the-app) ·
[Privacy](#privacy) ·
[Roadmap](#roadmap) ·
[soapcap and this app](#soapcap-and-this-app) ·
[Development](#development)

## How it works

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Assets/how-it-works-dark.svg">
  <img src="Assets/how-it-works-light.svg" alt="Call audio and your microphone feed Record (Apple SpeechAnalyzer, no audio recorded), which produces a transcript. The transcript goes straight to Draft note (Llama 3.1 or Bonsai, a local model), or first through the optional De-identify step, which redacts names and identifiers. The draft note is shown in the window, and Keep copies it. Everything runs on this Mac and is held in memory only; nothing is saved to disk unless you ask.">
</picture>

The app listens to **what the Mac is playing** and to **your microphone**,
so it works with any conferencing tool, FaceTime included, and never talks
to one.

## Requirements

| Requirement | Notes |
|---|---|
| macOS 26 (Tahoe) or newer, Apple silicon | Built for macOS 26 and tested on macOS 27; not yet run on macOS 26 itself |
| Full Xcode, its Metal Toolchain, and cmake | Only to build it yourself. The Command Line Tools alone are not enough. The Metal Toolchain compiles the de-identifier's GPU code and is a separate download (`xcodebuild -downloadComponent MetalToolchain`); cmake (`brew install cmake`) builds the note engine |
| A note model | `llama3.1:8b` (the tested default, 4.9 GB) or Bonsai (5.9 GB), each a download from Settings. An [Ollama](https://ollama.com) on the Mac that has `llama3.1:8b` is used until the app has its own copy. Recording works without one |
| The de-identification model (optional) | OpenMed's PII model, about 130 MB, installed from Settings |

## Install

Download the latest version from **[jukenzie.com](https://jukenzie.com)**
(or from this repository's [Releases](https://github.com/pglockner/soapcap-swift/releases/latest)).
Unzip it, drag **Soapcap** into Applications, and open it from
there. It is signed and notarized, so macOS asks once whether to open an
app from the internet and then lets it run. The first run walks through
setup. Updating and uninstalling are in the app's Help (see
[Using the app](#using-the-app)).

## Build and run

```sh
./build.sh && open build/Soapcap.app
```

The first build fetches the de-identifier's packages and builds the note
engine, and takes a few minutes longer. Sign with a stable identity (see
[Signing and notarizing](#signing-and-notarizing)), or macOS forgets the
app's permissions on every rebuild.

## Using the app

How to use Soapcap is in its own Help, under **Help › Soapcap Help** in
the app, and in this repository as
[`Sources/SoapcapUI/Resources/Help/help.md`](Sources/SoapcapUI/Resources/Help/help.md).
It covers setup and the checks, a session, the transcript and
de-identifying it, drafting a note, the note models and their memory,
Settings, updating and uninstalling. It is kept there and not repeated
here.

Below version 1.0 the app is a beta: each new version opens on a notice to
acknowledge, and the Ready screen carries a Beta mark. **Help › Report a
Problem…** gives the address to write to, with the version, macOS, memory
and note model to include.

## Privacy

- **Nothing is saved unless you ask.** Audio is never recorded. The
  transcript and the note live in memory and are gone when you start a new
  session or quit. The one exception is yours to make: **Save transcript…**
  writes a de-identified transcript to a file you choose. De-identifying is
  best effort, so that file can still hold a detail it missed: read it
  through before sharing it.
- **Nothing lands in a terminal.** A window has no scrollback and no
  window-restore snapshot.
- **The copied note is marked concealed**, so clipboard managers that honor
  that convention skip it.
- **Downloads only, nothing uploaded.** The note models and the
  de-identification model come from huggingface.co, and each file is
  checked against a pinned checksum. Ollama's `llama3.1:8b` is used only
  when the app has no copy of its own. Those downloads are the only time the
  app goes online, and nothing from a session is sent.
- **Ollama on another machine breaks the promise.** If its address is not
  this Mac, the transcript travels over the network, and the note says so.

## Roadmap

- [ ] Later: go over the rules the note model is given, and rework them to
      say less of what not to do and show more examples to follow. A change
      to them needs a full comparison run before it can be trusted
- [ ] Stretch: the `structured` and `combined` note styles (nobody is
      asking for them yet). Notes are drafted in the narrative style only
- [ ] Idea, not scoped: note structure from a settings file, so a note's
      sections and their rules can be tailored without editing prompts and
      code

## soapcap and this app

| | soapcap | soapcap-swift |
|---|---|---|
| Form | Command-line tool | Mac app, one window |
| Setup | `./install.sh`, with Homebrew | Drag into Applications, or build with Xcode |
| Speech recognition | Apple SpeechAnalyzer, through `yap` | Apple SpeechAnalyzer, built in |
| De-identification | OpenMed's PII model, through a Python helper | The same model, built in |
| Saving to a file | Only if you ask | A de-identified transcript, only if you ask |
| Note styles | narrative, structured, combined | narrative |
| Settings | `config.sh` | Its own Settings window |

They share the prompts, the Objective frame and the checks applied to a
draft, and the app's tests reuse soapcap's cases so the two agree. Nothing
soapcap installed is used: its models and its `llama-server` are left alone,
and the app downloads and checks its own.

## Development

To see SwiftUI previews, open this folder in Xcode and select the
`SoapcapUI` scheme. The window lives in that library; `Soapcap` is only the
launcher. The app's version comes from `VERSION`, and its build number is
the commit count.

### Command-line checks

Three probes run a piece of the app without the window:

- `swift run CaptureProbe 15` records for 15 seconds and prints the
  transcript. `swift run CaptureProbe check` only says whether the Mac's
  audio can be heard. From a terminal, the permissions are the terminal's.
- `swift run NoteProbe FILE [soap|dap|birp] [MODEL] [MINUTES]` drafts a
  note from a transcript file, or from the sample session with `sample` in
  place of the file. The model is run the way the app would run it, and
  `gguf:PATH` runs any model file on the app's engine.
- `swift run -c release DeidentifyProbe FILE [note]` de-identifies a file.
  `--install` sets up the model first; `--windows` tries other passes.

### Note engine

`engine.sh` builds `llama-server` from PrismML's llama.cpp, at a pinned
commit, into `.build/engine`. `build.sh` runs it and puts the result inside
the app, which starts it for a draft and gives it a key only the app knows.
`SOAPCAP_ENGINE` names a different `llama-server`, for trying a build with
the probes.

The note models' files go in
`~/Library/Application Support/Soapcap/note-models`. `llama3.1:8b` is Meta's
Llama 3.1 8B Instruct in second-state's 4-bit conversion, under the Llama 3.1
Community License.

### De-identification model

The model is kept in
`~/Library/Application Support/Soapcap/deidentify-model`; delete that
folder to remove it. The text is read twice and the findings merged: a
detection pass in short overlapping chunks, and a context pass in long
ones. When the app is started from a terminal, `SOAPCAP_DEIDENTIFY_MODEL`
names a different folder.

### Signing and notarizing

`build.sh` signs ad hoc unless `SOAPCAP_SIGN_IDENTITY` names a code-signing
identity, such as an Apple Development certificate (Xcode creates one for a
free Apple ID):

```sh
SOAPCAP_SIGN_IDENTITY="Apple Development: you@example.com (TEAMID)" ./build.sh
```

With an ad-hoc signature, macOS treats each rebuild as a different app and
drops its Microphone and System Audio Recording grants. To reset a stuck
grant, which also happens after switching from ad hoc to a certificate:

```sh
tccutil reset AudioCapture com.jukenzie.soapcap
tccutil reset Microphone com.jukenzie.soapcap
```

Every build runs under the hardened runtime. For a build that opens on
another Mac without a warning, sign with a Developer ID Application
identity and have Apple notarize it. `notarize.sh` uploads the app to
Apple, attaches the ticket and leaves a zip to ship, then removes the app,
which the zip holds (unless that copy is running):

```sh
SOAPCAP_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build.sh
./notarize.sh
```

It uses credentials stored once with
`xcrun notarytool store-credentials soapcap-notary`. `SOAPCAP_BUNDLE_ID` and
`SOAPCAP_OUT` give a build its own identifier and folder, so that it can sit
beside the usual one with permissions of its own.

### Releases and the download page

`docs/` is the download page, served by GitHub Pages at
[jukenzie.com](https://jukenzie.com). Its Download button links to
`releases/latest/download/Soapcap.zip`, so the page needs no change for a
new version, but every release must have the notarized zip attached under
that name:

```sh
gh release upload vX.Y.Z build/release/Soapcap.zip
```

A release published without it breaks the button. The `Release download`
workflow checks for it whenever a release is published, and fails if the
link doesn't find it.

### Tests

```sh
swift test
```

The `Test` workflow runs them on GitHub's Xcode 27 runner for every push
and pull request. The runner has no on-device speech recognition, so the
transcription tests skip there along with the opt-in ones below.

| Bundle | Covers |
|---|---|
| `SoapcapCoreTests` | Transcript rendering and echo de-duplication (soapcap's cases); memory figures; downloads that stop, carry on and are checked against a checksum |
| `SoapcapCaptureTests` | Cutting recognizer output into segments; transcribing a clip spoken by `say`; the microphone following a change of input device; the permission rows of the checks screen; a recording that can't start; Core Audio's buffer callback on this Mac's output, playing silence |
| `SoapcapNoteTests` | The checks and fixes on a draft (soapcap's cases); the drafting sequence, a session with no client heard included; both model backends against stand-ins; which model runs where |
| `SoapcapDeidentifyTests` | The rules (soapcap's cases); speaker labels left alone; installing the model |
| `SoapcapPIITests` | The real PII model on the transcripts in `Samples/deidentify`; skipped when the model isn't installed |
| `SoapcapUITests` | The session flow against scripted stand-ins, with its steps and what asks first; the transcript's minute index and pauses; what Save transcript writes, and when it is offered; starting and stopping the note model; the Test button; model downloads; what Uninstall removes; settings; credits |

A whole live session, the permission grants, signing and the window itself
are not covered. They need a person.

Three sets of tests run only when asked, and are skipped otherwise:

```sh
SOAPCAP_MODEL_TESTS=1 swift test --filter SampleNoteTests
SOAPCAP_NETWORK_TESTS=1 swift test --filter FetcherNetworkTests
SOAPCAP_AUDIO_TESTS=1 swift test --filter AudioHardwareTests
```

The first drafts the sample session's note with the default model and
checks that it comes out whole, as the app's Test button does: the baseline
check that a model on this Mac is working. It takes about a minute. Give
the variable a model's name instead of `1` to try that one. The second
stops and resumes a real 130 MB download. The third listens through the
call's tap for the tone the app plays itself, as the checks screen does,
and starts and stops the microphone. From a terminal those need the
terminal to have the Microphone and System Audio Recording permissions;
nothing is recorded or heard.

The sample session is soapcap's `03-selfreport-diagnosis-9min`, an
entirely fictional nine-minute session, in
`Sources/SoapcapNote/Resources/samples`. It says a model is working, not
how good its notes are: a note's wording changes from one draft to the
next, so there is no expected text to compare with.

## Credits

The app menu's **Acknowledgements** lists the projects the app is built on
and their licences.
