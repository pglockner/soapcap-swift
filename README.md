# soapcap-swift

A native Swift rewrite of [soapcap](https://github.com/pglockner/soapcap):
on-device capture of a speaker-attributed telehealth transcript on a Mac,
and a locally drafted SOAP/DAP/BIRP note, with nothing leaving the machine.

**Status: in development.** Soapcap.app is a SwiftUI window for the
`soapcap session` flow. It captures and transcribes on its own; de-identifying,
drafting the note and the permission check still call the existing `soapcap`
command-line tool as child processes, so it needs a working soapcap install.
The shell version of soapcap remains the supported tool until this one
replaces it.

## Rewrite plan

Each step replaces one child-process call with Swift code behind the same
interface, so the app keeps working throughout.

- [x] Window front end for the session flow (record, pause/resume, optional
      de-identify, draft, keep and copy)
- [ ] Show `structured`/`combined` note reviews (the CLI prints them to
      stderr, which the window hides on success)
- [x] Capture and transcription in-process (Apple SpeechAnalyzer), replacing
      `soapcap live` and the `yap` dependency
- [x] Transcript rendering and echo de-duplication
- [ ] Note drafting against the local model servers, replacing `soapcap note`
      (prompts and the structured schema stay as data files)
- [ ] De-identification in-process
- [ ] `doctor` checks and model selection
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
| soapcap itself, installed with its `install.sh` | The app runs the `soapcap` in Homebrew's `bin`; set `SOAPCAP_BIN` to use another |
| soapcap's de-identification (optional) | The de-identify toggle only appears if it's set up (`tools/deidentify/install.sh` in soapcap) |

### Build and run

```sh
./build.sh && open build/Soapcap.app
```

`build.sh` signs ad hoc. To keep macOS privacy grants across rebuilds, set
`SOAPCAP_SIGN_IDENTITY` to a stable local code-signing identity. The app's
version comes from `VERSION`; its build number is the commit count.

To see SwiftUI previews, open this folder in Xcode and select the `SoapcapUI`
scheme (the window lives in that library; `Soapcap` is only the launcher).

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

Grant Microphone and Screen Recording to "Soapcap" the first time (quit and
reopen the app after granting). Screen Recording is how macOS lets an app
hear what the Mac is playing; no picture is kept. The **Check permissions**
button runs `soapcap doctor` as the app, so it reports what macOS lets the
app do.

While recording, the window shows the last few lines heard from each side.
Pause stops listening and stops the clock; Resume carries on in the same
session. `swift run CaptureProbe 15` records for 15 seconds from the
terminal and prints the transcript, for checking capture without the window.

### Tests

```sh
swift test
```

- `SoapcapCoreTests`: transcript rendering, echo de-duplication and joining,
  with the same cases as soapcap's own fixture tests.
- `SoapcapCaptureTests`: cutting recognizer output into segments, and
  transcribing a clip spoken by `say`, compared with `yap` if it is installed.
- `SoapcapUITests`: the session flow against a scripted capture and a stub
  `soapcap`: pause and resume, the clock, de-identify order, failure screens.

Live capture, Microphone/Screen Recording permissions, signing, and the window
itself are not covered; they need a person.

### Limitations

- Speaker labels are fixed (Therapist for the microphone, Client for the
  call) and the language is the Mac's; soapcap's `config.sh` is not read yet.
- FaceTime's call audio can't be captured (a macOS limit); Zoom, Meet, Teams
  and Doxy.me can.
