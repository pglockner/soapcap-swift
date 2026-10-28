# Soapcap Help

## Getting started

Soapcap opens on a setup screen the first time. It asks for the two permissions macOS needs to give it: **Microphone**, for your side, and **System Audio Recording**, for what the Mac plays, which is the other side of the call. Each button says what you are about to see, and the answer counts at once. Soapcap hears sound only, never the screen. macOS can't tell an app whether it has System Audio Recording, so Soapcap finds out by playing itself a tone you won't hear.

Then download a note model in **Settings** (Cmd-comma). Gemma 4 E4B, the default, is 5.0 GB, Qwen3.5 9B 5.7 GB and Bonsai 5.9 GB; a download that stops carries on where it left off. The de-identification model, about 130 MB, is downloaded there too.

**Check**, in the bar at the top, brings the setup screen back at any time, with speech recognition for your language, the note model, the de-identification model and free memory as well. Soapcap looks these over whenever it opens: if a permission or the note model is missing, Check turns into an orange warning sign and the Ready screen offers to show what needs attention.

## The bar

The bar across the top says where a session is: **Record**, **Transcript**, **Note**, with the current step on a grey pill and the steps you can't go to dimmed. Once there is a note, Transcript and Note are both lit, so you can go back to the transcript and return.

## A session

- Use headphones, so your own voice isn't heard twice, and turn on Do Not Disturb.
- **Start session** begins transcribing. Nothing is recorded: Soapcap listens, and what it hears becomes text. The last few lines heard from each side show at the foot of the window.
- **Pause** stops listening and stops the clock; **Resume** carries on in the same session.
- The session's time shows in the menu bar while it runs, where the call's window can't cover it. Its menu can pause and resume too.
- A microphone that changes mid-session, such as AirPods connecting, is picked up.
- **Stop** ends the session. A stopped session can't be taken up again.

Closing the window doesn't quit Soapcap, so a session can't be lost by accident. Quit with Cmd-Q.

## The transcript

The transcript is shown a turn at a time, with the minute of the session in the margin. The ruler down the right goes to any minute. Where the session was paused, the transcript says so and for how long, and the ruler has a mark for it.

**De-identify** replaces names, phone numbers, dates and similar details with tokens such as `[FIRST_NAME_1]`, in the transcript and in the note. With **De-identify by default** on in Settings, as it starts out, this happens as the session stops. With it off, **De-identify** above the transcript does it when chosen, and goes over a note already drafted as well; any note drafted afterwards follows. Speaker labels and times are kept. It is best effort, so read the result before sharing it. If it fails, the text is shown under a red "Not de-identified" banner, and De-identify can be tried again.

**Save transcript…** takes De-identify's place once the transcript is de-identified, and writes it to a text file wherever you choose. It is the only thing Soapcap ever saves, and only when you ask; a transcript that was not de-identified can't be saved.

## Drafting a note

Pick SOAP, DAP or BIRP and choose **Draft note**. With both note models installed, the menu beside it, and beside **Regenerate** on the note, picks which one drafts; it is the same choice as in Settings.

- A draft with a missing or empty section is redone, up to three times, and the most complete one is kept.
- A SOAP note's Objective is a fixed mental-status frame filled in by a separate pass. It never says "No SI/HI reported" if risk language was heard.
- When only your side was heard, the sections about the client say they need completing by hand: a SOAP note's Subjective and Objective, a DAP note's Data, and a BIRP note's Behavior and Response.
- Cautions under the note, such as a section still missing, are never copied with it.
- **Keep** copies the note, ready to paste into your records. **Regenerate** drafts it again. **Transcript**, in the bar, goes back to the transcript.
- Until a note has been kept, **Discard** and drafting again both ask first: neither can be undone.

Read every note before you use it. The model can leave out what was said or add what wasn't.

## While a note drafts

The window lists the steps of the draft as they are done, with two small charts: memory in use, and how much has spilled over to disk as swap. They turn yellow and then red as the Mac fills up.

**Stop drafting** ends a draft and frees the model's memory. If you were drafting again, the note you already had is still there. Otherwise the model stays loaded until you discard the note, start a new session or quit.

## Note models

Gemma 4 E4B, the default, is fast, under two minutes for a long session, and needs about 6.5 GB of memory. Qwen3.5 9B writes a little differently, takes about two minutes, and needs up to 8.5 GB. Bonsai is slower, a few minutes a note, and needs about 8 GB. They are the ones the prompts were tested with, and no other model is offered. All run inside Soapcap from files it downloaded and checked itself.

- When memory is short for the chosen model, the transcript suggests closing other apps first. When the Mac is also deep in swap, Soapcap asks before drafting. A Mac with too little memory for the model is told that drafting will be very slow.
- **Test**, under the model's name in Settings and on the checks screen's Note model line, drafts a note from a made-up session and answers Good when every section came out filled, or Problem with what was wrong. The note can be read either way. It takes as long as drafting a note does, nothing is kept, and it isn't offered while a session is being recorded.

## Settings

Open Settings with Cmd-comma.

- **Speaker labels**: who your microphone is and who the call is. Each transcript line starts with one of them.
- **Language**: the language to transcribe in, this Mac's unless you choose another.
- **Note**: the model that drafts, and the session type on the note's first line ("53 minutes, telehealth").
- **Gemma 4 E4B**, **Qwen3.5 9B**, **Bonsai** and **De-identification**: each model says how big it is before it downloads. **Remove** deletes a note model again. **De-identify by default** is here too.

## Privacy

- Audio is never recorded. The transcript and the note are held in memory and are gone when you start a new session or quit. The only exception is a de-identified transcript you choose to save.
- The models are downloaded from huggingface.co and checked against a fixed checksum. Nothing from a session is sent anywhere.
- A copied note is marked as concealed, so clipboard managers that honour that skip it.

## When something goes wrong

- Choose **Check** in the bar. Each line that isn't green has a button that puts it right.
- If you allow the microphone in System Settings after refusing it, quit and reopen Soapcap: macOS only tells an app at launch.
- If Soapcap says it can't find a working microphone, connect one, such as a headset or AirPods, and start again. A Mac mini or Mac Studio has none built in.
- If a note comes out with a section missing, **Regenerate**, or try the other model.
- **Help › Report a Problem** shows where to write, with this copy's version and Mac to include. **Open in Mail** starts the email with both filled in; if your mail is in a browser, copy them into a new message. Please describe what happened, but don't include anything from a session.

## Updating to a new version

1. Quit Soapcap with Cmd-Q. Closing the window isn't enough: Soapcap keeps running so that a session can't be lost.
2. Unzip the new version and drag it into Applications. Choose **Replace** when asked.
3. Open it.

Your models, settings and permissions are kept. Don't use **Uninstall Soapcap…** to update: it deletes the models, and they would have to be downloaded again.

## Uninstalling

**Uninstall Soapcap…**, at the bottom of Settings, removes the models Soapcap downloaded, its settings and its permissions, then moves the app to the Trash. A transcript you saved is left alone: that file is yours, wherever you put it.

After an update, Soapcap deletes the file of any note model it no longer offers the next time it opens.
