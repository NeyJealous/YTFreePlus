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

The tweak builds successfully with GitHub Actions.

Implemented in source:
- Theos tweak scaffold
- current YouTube player/overlay compatibility declarations
- native Yandex VOT protocol layer
- protobuf writer/reader
- Yandex session + HMAC-SHA256 signing
- translation request and ETA-based polling
- AUDIO_REQUESTED empty-audio fallback
- translated-audio playback with AVPlayer
- media-time/playback-rate synchronization foundation
- temporary VOT player button
- automatic `.deb` CI artifact
- manual IPA packaging workflow using free YTLite 5.2b4

Still to verify on a physical iPhone:
- runtime compatibility with the selected YouTube IPA version
- final production overlay placement
- independent ducking of original YouTube audio
- Shorts/live VOT
- OAuth lively voices

See `docs/ARCHITECTURE.md` and `docs/ROADMAP.md`.

## Build tweak

Requires Theos and an iOS SDK.

```sh
make clean package
```

The normal **Build YTFreePlus** GitHub Action produces a `YTFreePlus-deb` artifact.

## Build an IPA

Open **Actions → Build YTFreePlus IPA → Run workflow** and provide:

1. a direct URL to your decrypted YouTube IPA;
2. the desired display name;
3. the desired bundle ID.

The workflow:
- builds YTFreePlus from the current commit;
- downloads the official free YTLite 5.2b4 package;
- verifies its published SHA-256;
- validates the supplied IPA structure;
- injects YTLite 5.2b4 and YTFreePlus;
- uploads `YTFreePlus.ipa` as a private GitHub Actions artifact.

No decrypted YouTube IPA is stored in this repository.

## License

YTFreePlus original code is MIT licensed. Third-party components retain their own licenses.
