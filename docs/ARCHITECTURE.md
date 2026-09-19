# Architecture

YTFreePlus is a separate tweak layer; it does not require modifying the YTLite 5.2b4 source tree.

```text
YouTube IPA
  + free YTLite 5.2b4
  + YTFreePlus.deb
  + optional OSS tweaks
        |
        v
       IPA
```

## VOT flow

```text
YouTube video ID + duration
        |
        v
https://youtu.be/<id>
        |
        v
VOTClient
  -> Yandex session
  -> protobuf request
  -> HMAC-SHA256 headers
  -> WAITING/LONG_WAITING: server-ETA polling
  -> AUDIO_REQUESTED: empty-audio fallback
  -> PART_CONTENT/FINISHED: translated audio URL
        |
        v
VOTAudioPlayer (AVPlayer)
        |
        v
VOTManager
  -> play/pause
  -> seek correction
  -> playback-rate sync
        |
        v
YouTube overlay
```

States: **OFF / PENDING / ACTIVE / ERROR**. No fake progress percentage is synthesized.

Protocol constants are isolated in `VOT/VOTConfig.m` because the unofficial Yandex protocol can change.
