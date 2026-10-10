# Changelog

## 0.1 (2026-09-18 – 2026-10-10)

- Added Soapcap.app, a native window for the `soapcap session` flow (record, optional de-identify, draft, keep and copy) that runs the `soapcap` command-line tool behind the scenes.
- Added pause and resume to recording.
- Added SoapcapCore, the transcript rendering and echo de-duplication logic ported from soapcap; the app does not use it yet.
- Moved the window into a SoapcapUI library so Xcode can show its previews.
- Fixed the lookup of soapcap's de-identify helper so it checks where soapcap's new installer puts it.
