# Changelog

## 0.4 (2026-10-10)

- Added note drafting inside the app, with a model in Ollama or with Bonsai, replacing `soapcap note`; the `soapcap` tool is now only needed for de-identification
- Added the checks and fixes soapcap applies to a drafted note: up to three drafts when a section is missing or empty, and a SOAP Objective built by a separate pass
- Added a note model picker, session type and Ollama address to Settings, and a Note model line to the permissions check
- Added warnings under the note (untested model, missing section, failed Objective pass) that are never copied with it
- Fixed capture to carry on when the microphone changes mid-session
- Added an icon for the app

## 0.3 (2026-10-10)

- Changed **Check permissions** to report what the app itself can do: its Microphone and Screen Recording grants, speech recognition for your language, and whether the `soapcap` tool and de-identify helper are found, with a button to the right pane of System Settings. It no longer runs `soapcap doctor`, so it does not check the note model.
- Added a Settings window (Cmd-comma) for the two speaker labels and the language to transcribe in.
- Changed the note format and the de-identify choice to be remembered between launches.


## 0.2 (2026-10-10)

- Changed recording to capture and transcribe inside the app (Apple SpeechAnalyzer); it no longer runs `soapcap live` or needs `yap`. The app itself now needs the Microphone and Screen Recording permissions.
- Changed pause and resume to continue one session: pause stops listening and stops the clock, and the 3-second wait before pausing or stopping is gone.
- Added a live strip on the recording screen showing the last few lines heard from each side.
- Added a warning on the transcript when only the microphone was heard.
- Added `CaptureProbe`, a command-line check that records for a few seconds and prints the transcript.



## 0.1 (2026-09-18 – 2026-10-10)

- Added Soapcap.app, a native window for the `soapcap session` flow (record, optional de-identify, draft, keep and copy) that runs the `soapcap` command-line tool behind the scenes.
- Added pause and resume to recording.
- Added SoapcapCore, the transcript rendering and echo de-duplication logic ported from soapcap; the app does not use it yet.
- Moved the window into a SoapcapUI library so Xcode can show its previews.
- Fixed the lookup of soapcap's de-identify helper so it checks where soapcap's new installer puts it.
