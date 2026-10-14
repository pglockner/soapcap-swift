# Changelog

## 0.11 (2026-10-12 – 2026-10-14)

- Added Save transcript…, which writes a de-identified transcript to a text file wherever you choose; it is the only thing the app saves, and only when asked.
- Changed De-identify from a toggle on the Ready screen to a button above the transcript, so a session can be de-identified after it stops; a De-identify by default setting (on) does it as the session stops.
- Added a note model chooser beside Draft note and Regenerate when both models are installed, the same choice as in Settings.
- Added a line in the transcript where the session was paused, saying for how long.
- Changed the Ready screen's check button to show only when something needs attention, with Check in the bar turning orange as well.

## 0.10 (2026-10-12)

- Added the minute of the session to the transcript's margin, and a ruler of minutes down its side: each mark goes to that minute, the minutes on screen are picked out, and the ruler takes the finest spacing its height has room for
- Changed a DAP note's Data and a BIRP note's Behavior to say they need completing by hand when only one side was heard, as a SOAP note's Subjective and Objective already did; before, such a note was left wholly to the model, with no caution under it
- Changed the transcript to show each turn a speaker took as its own line, a little apart from the next, with the speaker's name in bold; a selection now runs within one turn
- Added a mark on the ruler where the session was paused: clicking it goes to that minute, and pointing at it says when
- Changed the Ready screen to be laid out like the session it leads to: centred, with the clock standing at 00:00 where it will run and the reminders at the foot, so that nothing moves when a session starts

## 0.9 (2026-10-12)

- Added a bar across the top of the window: the app's name, the steps Record, Transcript and Note with the one in hand picked out, and buttons for the checks and Settings. From the note the transcript can be gone back to, and the note again
- Fixed a draft that failed costing the transcript: the only way off the error was Back, which began a new session. Back now returns to the transcript
- Added a question before work that hasn't been kept is lost: drafting again over a note not yet kept, and discarding a session, both ask first
- Changed the note models offered to the two the prompts were tested with, `llama3.1:8b` and Bonsai; another model pulled into Ollama can no longer be chosen
- Added the session's time to the menu bar while a session runs, with Pause and Resume
- Changed the drafting screen to list the draft's steps as they are done, with charts of memory in use and of swap, in place of a spinner
- Changed Stop to red, and Return no longer presses it. Discard and Uninstall are red too, and **Uninstall Soapcap…** moved from the app menu to the bottom of Settings
- Changed a SOAP note's Subjective to say it needs completing by hand when only one side was heard; the app writes it, as it does the Objective, because a model sometimes reported what no client had said
- Fixed the app and the README saying FaceTime calls can't be captured: with the Core Audio tap they are transcribed like any other call

## 0.8 (2026-10-10 – 2026-10-12)

- Fixed a note model's requests and replies being cached on disk: the transcript and the note were filed in the app's cache folder under `~/Library/Caches`. Nothing is cached now, and the app deletes its cache folder whenever it opens
- Changed how the call is heard to a Core Audio tap in place of ScreenCaptureKit: macOS now asks about System Audio Recording only, never the screen, and the answer counts without reopening the app
- Added `llama3.1:8b` as a 4.9 GB download in Settings, run on the app's own engine, so drafting no longer needs Ollama; a copy Ollama already has is used where it is
- Changed the app's identifier to `com.jukenzie.soapcap`; settings and permissions under the old one are not carried over
- Changed the checks screen into a setup screen that walks through the Microphone and System Audio Recording permissions, each with a button that says what macOS will show
- Fixed the microphone being lost for the rest of a session when the input device changed, as when AirPods connect or are put away; it is now read through Core Audio and retried until it is back
- Added a **Test** button for the note model, in Settings and on the checks screen: it drafts a note from a sample session and answers Good or Problem
- Added **Uninstall Soapcap…** to the app menu, which removes the models the app downloaded, its settings and its permissions, then moves the app to the Trash
- Fixed **Uninstall Soapcap…** leaving the app open: it removed everything and moved the app to the Trash, then stayed on screen as if nothing had happened. It now quits (0.8.1)
- Fixed **Start recording** staying on "Starting…" for ever when a recording could not start, as with the microphone refused; it now says what is wrong (0.8.1)
- Changed **Uninstall Soapcap…** to also remove the cache macOS keeps for the app under `/var/folders`; the size it shows now counts the models alone (0.8.1)

## 0.7 (2026-10-10)

- Added the note engine inside the app: `llama-server`, built from PrismML's pinned source by `engine.sh`, so Bonsai no longer needs soapcap's build. Building the app now needs cmake
- Added downloading Bonsai from Settings: size, time, free disk and memory are said first, a stopped download carries on where it left off, and **Remove** deletes it. A copy soapcap installed is used where it is
- Changed every build to run under the hardened runtime, and added `notarize.sh`, which has Apple notarize a build signed with a Developer ID
- Changed the note screen's **Discard** button to **New session** once the note has been copied
- Added llama.cpp and Bonsai to Acknowledgements

## 0.6 (2026-10-10)

- Added a line showing memory in use while a note is drafted: green, yellow from 75%, red from 90%, where it also shows swap in use
- Added advice on the transcript screen to close other apps when Bonsai is selected and less than 9 GB of memory is free; **Check permissions** has a Memory line saying the same
- Added a question before a Bonsai draft when 6 GB or less is free and 6 GB or more is already in swap, with Cancel as the default answer
- Added a **Stop drafting** button that gives up on a draft, frees the model's memory and goes back to the transcript
- Fixed **Stop drafting** going back to the transcript while the note model was still shutting down; the window now shows "Stopping…" until it has gone, so a new draft can't collide with the old one (0.6.1)
- Fixed Bonsai's server answering any program on the Mac, and any web page open in a browser: each server now has a key only the app knows (0.6.1)
- Fixed a Bonsai server given up on while it loads being force-killed and not waited for (0.6.1)
- Added `engine.sh`, which builds the note engine from PrismML's pinned source as one self-contained file (not yet used by the app), and a `gguf:PATH` option for `NoteProbe` (0.6.1)

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
