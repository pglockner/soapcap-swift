# Changelog

## 0.6 (2026-10-10)

- Added a line showing memory in use while a note is drafted: green, yellow from 75%, red from 90%, where it also shows swap in use
- Added advice on the transcript screen to close other apps when Bonsai is selected and less than 9 GB of memory is free; **Check permissions** has a Memory line saying the same
- Added a question before a Bonsai draft when 6 GB or less is free and 6 GB or more is already in swap, with Cancel as the default answer
- Added a **Stop drafting** button that gives up on a draft, frees the model's memory and goes back to the transcript

## 0.5 (2026-10-10)

- Added de-identification inside the app, replacing `soapcap deidentify`; the app no longer needs soapcap or Python
- Added setting up OpenMed's PII model from Settings: soapcap's copy is used if present, otherwise it is downloaded and each file checked against a pinned checksum
- Added a red "Not de-identified" banner when de-identifying fails, in place of a small notice
- Added an Acknowledgements window crediting each source with its licence
- Fixed the app possibly hanging at quit after force-stopping a Bonsai server that ignored a polite stop
- Added three de-identification sample transcripts the passes were not chosen on, and a test that runs the model over them (0.5.1)
- Fixed `build.sh` producing an app without the Metal library de-identifying needs; it now stops with an error (0.5.1)
- Changed SOAP notes drafted with Bonsai to read the transcript once instead of once per pass, saving about two minutes on an hour-long session (0.5.2)


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
