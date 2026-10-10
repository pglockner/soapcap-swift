# De-identification samples

Three entirely fictional session transcripts for checking what the
de-identifier removes. They were written after the passes in
`OpenMedDetector` were chosen and were not used to choose them, so they show
whether that choice holds on text it wasn't fitted to. Don't tune against
them; add new files instead.

They follow soapcap's conventions for publishable samples: phone numbers
from `555-0100`–`555-0199`, email on the reserved `.example` domain, street
addresses with no city, and invented people, employers and insurers.

Each `NAME.txt` has a `NAME.remove` beside it: one string per line that
must not survive, matched as a whole word. A line starting with `? ` is a
known miss: it is listed so the gap is on record, and the test doesn't
require it.

`SoapcapPIITests` runs them when the model is installed. To try other
passes by hand:

```sh
swift run -c release DeidentifyProbe Samples/deidentify/h2-family-conflict.txt --windows 256/32,480/128
```

## Results (2026-10-10)

39 strings across the three files.

| Run | Removed | Left in |
|---|---|---|
| The app: detection 128/64 + context 480/128 | 37 | a name spelled out letter by letter (h1), "Hawthorn House" (h2) |
| soapcap's Python helper (256/32 + 480/128) | 37 | the spelled-out name (h1), a claim number "WC-2291-5530-7" (h3) |
| soapcap's pair in the app's runtime (256/32 + 480/128) | 34 | the spelled-out name, "Colm", "Redfern and Achebe", "Hawthorn House", the claim number |
| Detection pass alone | 37 | same two as the app |
| All three passes | 37 | same two as the app |

Nothing removes the spelled-out name. Which organisation name slips through
varies from one run to the next, as it did on soapcap's own samples.
