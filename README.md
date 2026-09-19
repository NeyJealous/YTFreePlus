# YTFreePlus

YTFreePlus is an independent iOS YouTube tweak focused on free/open functionality and native Yandex Voice-Over Translation (VOT) integration.

## Distribution model

YTFreePlus produces **only a tweak package (`.deb`)**.

The intended flow is:

```text
YTFreePlus source
      |
      v
YTFreePlus.deb
      |
      v
Ksign
  + clean/decrypted YouTube IPA
  + YTFreePlus.deb
  + optional additional tweak .deb files
      |
      v
final signed/injected YouTube IPA
```

IPA assembly is intentionally outside this repository and belongs to the Ksign workflow.

## Baseline policy

- The project targets the free/open YTLite lineage, using **YouTube Plus / YTLite 5.2b4** as the last free functional reference.
- YTLite source/binaries are not bundled into this repository.
- YTFreePlus does not patch or bypass the paid subscription/account system used by later YouTube Plus releases.
- Features from newer versions are to be reimplemented independently or through compatible open-source components.

## Current status

**Phase 1 / protocol MVP**

The tweak builds successfully with GitHub Actions.

Implemented:
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

Still to verify on a physical iPhone:
- runtime compatibility with the selected YouTube IPA version
- final production overlay placement
- independent ducking of original YouTube audio
- Shorts/live VOT
- OAuth lively voices

See `docs/ARCHITECTURE.md` and `docs/ROADMAP.md`.

## Build the tweak

Requires Theos and an iOS SDK.

```sh
make clean package
```

The **Build YTFreePlus** GitHub Action produces a `YTFreePlus-deb` artifact containing the compiled tweak package.

Tagged versions can publish the resulting `.deb` as a GitHub Release asset.

## Ksign integration

Ksign should treat YTFreePlus as a normal tweak package:

1. select a clean/decrypted YouTube IPA;
2. add the compiled `YTFreePlus.deb`;
3. optionally add other compatible tweak `.deb` packages;
4. inject/sign/package the resulting IPA inside Ksign.

YTFreePlus itself does not download, modify, store, or redistribute YouTube IPA files.

## License

YTFreePlus original code is MIT licensed. Third-party components retain their own licenses.
