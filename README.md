# soapcap-swift

A native Swift rewrite of [soapcap](https://github.com/pglockner/soapcap):
on-device capture of a speaker-attributed telehealth transcript on a Mac,
and a locally drafted SOAP/DAP/BIRP note, with nothing leaving the machine.

**Status: in development.** Soapcap.app is a SwiftUI window for the
`soapcap session` flow. It captures, transcribes and drafts the note on its
own, talking to a local model directly. Only de-identifying still calls the
existing `soapcap` command-line tool, so that needs a soapcap install.
The shell version of soapcap remains the supported tool until this one
replaces it.

## Rewrite plan

Each step replaces one child-process call with Swift code behind the same
interface, so the app keeps working throughout.

- [x] Window front end for the session flow (record, pause/resume, optional
      de-identify, draft, keep and copy)
- [ ] The `structured` and `combined` note styles, and showing their review
- [x] Capture and transcription in-process (Apple SpeechAnalyzer), replacing
      `soapcap live` and the `yap` dependency
- [x] Transcript rendering and echo de-duplication
- [x] Note drafting against the local model servers, replacing `soapcap note`
      (narrative style; prompts and the schema stay as data files)
- [ ] De-identification in-process
- [x] Permission checks and settings in the app (labels, language)
- [x] Note-model checks and model selection
- [ ] A signed, notarized build that needs no Xcode to install

## Soapcap.app

Because it isn't a terminal program, nothing it shows can end up in terminal
scrollback or a terminal's window-restore snapshot. Data stays in memory; the
note is copied to the clipboard marked as concealed so clipboard managers that
honor that convention skip it.

### Requirements

| Requirement | Notes |
|---|---|
| macOS 26 (Tahoe) or newer, Apple silicon | Same as soapcap |
| Full Xcode (not just Command Line Tools) | To build |
| A note model (for drafting; recording works without one) | [Ollama](https://ollama.com) with a pulled model (`llama3.1:8b` is the tested default), or Bonsai set up by soapcap's `tools/bonsai/install.sh` |
| soapcap and its de-identification (optional) | The de-identify toggle only appears if soapcap's `tools/deidentify/install.sh` has been run. The app runs the `soapcap` in Homebrew's `bin`; set `SOAPCAP_BIN` to use another |

### Build and run

```sh
./build.sh && open build/Soapcap.app
```

`build.sh` signs ad hoc. To keep macOS privacy grants across rebuilds, set
`SOAPCAP_SIGN_IDENTITY` to a stable local code-signing identity. The app's
version comes from `VERSION`; its build number is the commit count.

To see SwiftUI previews, open this folder in Xcode and select the `SoapcapUI`
scheme (the window lives in that library; `Soapcap` is only the launcher).

### Using the app

Grant Microphone and Screen Recording to "Soapcap" the first time (quit and
reopen the app after granting). Screen Recording is how macOS lets an app
hear what the Mac is playing; no picture is kept. The **Check permissions**
button shows whether the app has both grants, whether speech recognition is
ready for your language, whether the note model is ready, and whether
de-identification is set up, with a button to the right pane of System
Settings.

Settings (Cmd-comma) holds the two speaker labels, the language to
transcribe in, the note model, and the session type that goes on the note's
first line ("53 minutes, telehealth"). Under Advanced is Ollama's address;
anything but this Mac sends the transcript over the network, and the note
says so.

A note is drafted up to three times if a section comes back missing or
empty, keeping the most complete draft. A SOAP note's Objective is a fixed
mental-status frame filled in by a separate pass; it never states "No SI/HI
reported" if either pass saw risk language. Anything you should know about a
draft (an untested model, a section still missing, a failed Objective pass)
appears under the note and is never copied with it. The model stays loaded
between drafts and is released when you discard the note, start a new
session or quit.

While recording, the window shows the last few lines heard from each side.
Pause stops listening and stops the clock; Resume carries on in the same
session. If the microphone changes mid-session (AirPods connecting or
dropping), capture carries on with the new one.

Two command-line checks work without the window: `swift run CaptureProbe 15`
records for 15 seconds and prints the transcript, and
`swift run NoteProbe FILE [soap|dap|birp] [MODEL] [MINUTES]` drafts a note
from a transcript file (`bonsai` as the model uses Bonsai).

### Signing

`build.sh` signs ad hoc unless `SOAPCAP_SIGN_IDENTITY` names a code-signing
identity, e.g. an Apple Development certificate (Xcode creates one for a
free Apple ID). Use one: with an ad-hoc signature, macOS treats each rebuild
as a different app and drops its Microphone and Screen Recording grants. To
reset a stuck grant: `tccutil reset ScreenCapture local.soapcap.session` and
`tccutil reset Microphone local.soapcap.session`. Do the same if Soapcap is
listed in Privacy & Security but recording still fails, which happens after
switching from an ad-hoc signature to a certificate.

```sh
SOAPCAP_SIGN_IDENTITY="Apple Development: you@example.com (TEAMID)" ./build.sh
```

### Tests

```sh
swift test
```

- `SoapcapCoreTests`: transcript rendering, echo de-duplication and joining,
  with the same cases as soapcap's own fixture tests.
- `SoapcapCaptureTests`: cutting recognizer output into segments, and
  transcribing a clip spoken by `say`, compared with `yap` if it is installed.
- `SoapcapNoteTests`: the checks and fixes applied to a draft (soapcap's own
  cases), the drafting sequence against a scripted model, and both model
  backends against a stubbed HTTP layer and a stand-in `llama-server`.
- `SoapcapUITests`: the session flow against a scripted capture, a scripted
  drafter and a stub `soapcap`: pause and resume, the clock, de-identify
  order, failure screens, the checks screen and settings.

Live capture, real model output, Microphone/Screen Recording permissions,
signing, and the window itself are not covered; they need a person.

### Limitations

- The app keeps its own settings and does not read soapcap's `config.sh`.
- Notes are drafted in soapcap's narrative style only.
- FaceTime's call audio can't be captured (a macOS limit); Zoom, Meet, Teams
  and Doxy.me can.
