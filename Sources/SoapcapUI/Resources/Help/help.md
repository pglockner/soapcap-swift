# Soapcap Help

## Getting started

Soapcap opens on a setup screen the first time. It asks for the two permissions macOS needs to give it: **Microphone**, for your side, and **System Audio Recording**, for what the Mac plays, which is the other side of the call. Each button says what you are about to see. Soapcap hears sound only, never the screen.

Then download a note model in **Settings** (Cmd-comma). `llama3.1:8b` is 4.9 GB and Bonsai 5.9 GB; a download that stops carries on where it left off. The de-identification model, about 130 MB, is downloaded there too.

**Check**, in the bar at the top, brings the setup screen back at any time. It turns into an orange warning sign when something needs attention.

## A session

- Use headphones, so your own voice isn't heard twice, and turn on Do Not Disturb.
- **Start session** begins transcribing. Nothing is recorded: Soapcap listens, and what it hears becomes text.
- **Pause** stops listening and stops the clock; **Resume** carries on in the same session.
- The session's time shows in the menu bar while it runs, where the call's window can't cover it. Its menu can pause and resume too.
- **Stop** ends the session. A stopped session can't be taken up again.

Closing the window doesn't quit Soapcap, so a session can't be lost by accident. Quit with Cmd-Q.

## The transcript

The transcript is shown a turn at a time, with the minute of the session in the margin. The ruler down the right goes to any minute, and to where the session was paused.

**De-identify** replaces names, dates and other identifying details with tokens such as `[FIRST_NAME_1]`. With **De-identify by default** on in Settings, this happens as the session stops. It is best effort, so read the result before sharing it.

**Save transcript…** writes a de-identified transcript to a file you choose. It is the only thing Soapcap ever saves, and only when you ask.

## Drafting a note

Pick SOAP, DAP or BIRP and choose **Draft note**. With both note models installed, the menu beside it picks which one drafts.

- **Keep** copies the note, ready to paste into your records.
- **Regenerate** drafts it again. **Transcript**, in the bar, goes back to the transcript.
- Cautions under the note, such as a section still missing, are never copied with it.
- When only your side was heard, the sections about the client say they need completing by hand.
- **Discard** asks first while the note hasn't been kept: it can't be undone.

Read every note before you use it. The model can leave out what was said or add what wasn't.

## Note models

`llama3.1:8b` is fast, usually under a minute a note. Bonsai is more careful and slower, a few minutes a note, and needs about 8 GB of memory. While a note drafts, two small charts show memory in use and how much has spilled over to disk; close other apps if they turn red.

**Test**, under the model's name in Settings, drafts a note from a made-up session and answers Good or Problem.

## Privacy

Audio is never recorded. The transcript and the note are held in memory and are gone when you start a new session or quit. The models are downloaded from huggingface.co, and nothing from a session is sent anywhere.

## When something goes wrong

- Choose **Check** in the bar. Each line that isn't green has a button that puts it right.
- If you allow the microphone in System Settings after refusing it, quit and reopen Soapcap: macOS only tells an app at launch.
- If a note comes out with a section missing, **Regenerate**, or try the other model.
- **Help › Report a Problem** starts an email with this copy's version and Mac already filled in. Please describe what happened, but don't include anything from a session.

## Uninstalling

**Uninstall Soapcap…**, at the bottom of Settings, removes the models Soapcap downloaded, its settings and its permissions, then moves the app to the Trash. A transcript you saved is left where you put it.
