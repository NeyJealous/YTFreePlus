# Roadmap

## Phase 0 — foundation
- [x] independent Theos target
- [x] MIT license for original code
- [x] third-party notices
- [x] no paid YTPlus dependency
- [x] deb-only build model
- [x] GitHub Actions artifact for the compiled tweak

## Phase 1 — Yandex VOT MVP
- [x] protobuf encoder/decoder
- [x] HMAC signing
- [x] session lifecycle
- [x] request/poll model
- [x] AUDIO_REQUESTED fallback
- [x] AVPlayer sync foundation
- [ ] physical-device verification

## Phase 2 — UI
- [ ] production overlay integration through YTVideoOverlay
- [ ] OFF/PENDING/ACTIVE/ERROR visuals
- [ ] ETA display
- [ ] settings and language selection

## Phase 3 — audio
- [ ] per-player original-audio gain hook
- [ ] adaptive ducking
- [ ] seek/speed/background tests
- [ ] Bluetooth/AirPlay route changes

## Phase 4 — expanded VOT
- [ ] subtitles
- [ ] Shorts
- [ ] live translation
- [ ] user-supplied OAuth lively voices

## Phase 5 — modern YouTube compatibility
- [ ] compatibility shims by YouTube version
- [ ] smoke tests against current headers
- [ ] validate injection through Ksign into clean YouTube IPA

## Phase 6 — release pipeline
- [x] automatic `.deb` build artifact
- [ ] stable semantic versioning
- [ ] tagged GitHub Releases with `.deb` asset
- [ ] changelog generation
- [ ] Ksign compatibility notes per release
