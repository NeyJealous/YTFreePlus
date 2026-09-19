# YTFreePlus

YTFreePlus is an independent iOS YouTube tweak layer focused on free/open functionality and native Yandex Voice-Over Translation (VOT) integration.

## Baseline policy

- Targets the last free YouTube Plus / YTLite release: **5.2b4**.
- YTLite 5.2b4 is **not vendored** into this repository.
- YTFreePlus does not patch or bypass the paid subscription/account system used by later YouTube Plus releases.
- Intended packaging: decrypted YouTube IPA + official free YTLite 5.2b4 package + YTFreePlus + optional open-source integrations.

Official free asset: `com.dvntm.ytlite_5.2b4_iphoneos-arm.deb`  
Published SHA-256: `56130dd4c7a1c9c80acc38c88d12002de3d099ca8de3698f87729331258ed9fa`

## Current status

**Phase 1 / protocol MVP**

Implemented in source:
- Theos tweak scaffold
- native Yandex VOT protocol layer
- protobuf writer/reader
- Yandex session + HMAC-SHA256 signing
- translation request and polling
- translated-audio playback/synchronization foundation

Still to verify on a physical iPhone:
- current YouTube hooks
- final overlay placement
- independent ducking of original YouTube audio
- Shorts/live VOT
- OAuth lively voices

See `docs/ARCHITECTURE.md` and `docs/ROADMAP.md`.

## Build

```sh
make clean package
```

## License

YTFreePlus original code is MIT licensed. Third-party components retain their own licenses.
