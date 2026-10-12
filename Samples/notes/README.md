# Note sample

One entirely fictional session transcript, for checking that a note model
turns a session into a whole note. It is soapcap's
`03-selfreport-diagnosis-9min`, unchanged: nine minutes in which a client
describes episodes of chest tightness and anxiety, practises a breathing
exercise, and agrees a sleep routine and a possible referral. No risk is
disclosed. It follows soapcap's conventions for publishable samples: a
phone number from `555-0100`–`555-0199` and invented people.

To draft its note by hand, with the model Settings would use:

```sh
SOAPCAP_ENGINE=.build/engine/llama-server swift run NoteProbe Samples/notes/03-selfreport-diagnosis-9min.txt soap llama3.1:8b 9
```

`SampleNoteTests` does the same and checks the result: every section
filled, the Objective drafted, nothing for the clinician to be cautioned
about. It loads a model and takes about a minute, so it runs only when
asked:

```sh
SOAPCAP_MODEL_TESTS=1 swift test --filter SampleNoteTests
```

Give the variable a model's name instead of `1` to try that model
(`SOAPCAP_MODEL_TESTS=bonsai`). The test is skipped, not failed, when the
model isn't on this Mac.

It says a model is working, not how good its notes are: a note's wording
changes from one draft to the next, so there is no expected text to compare
with. soapcap's other seven samples, and the comparisons made with them,
are in soapcap.
