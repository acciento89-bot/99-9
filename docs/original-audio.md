# Original precision audio

The active scene now uses `main_audio.gd`, extending the unchanged Practice/gameplay chain. A single scene-owned `PrecisionAudio` node owns one looping music player, one UI player and one result player, each with maximum polyphony 1. Rapid UI feedback cannot stack unbounded voices. The 24-second original synth loop runs at −20 dB; short UI/hit/miss effects run at −12 dB. Both switches default on.

Normal Settings contains separate **MUSIC: ON/OFF** and **SOUND: ON/OFF** buttons. They persist independently in `user://audio-v1.cfg`; existing `save.json`, Practice archive, themes, purchases and counters keep their schemas. A write error restores the previous setting and shows `NOT SAVED`. Settings cards retain their original controls/callbacks inside touch scrolling; Back remains fixed. Small layouts stack the audio switches and retain a minimum touch height. No timing-screen control moves.

Focus/background loss pauses music and stops effects. Foreground may resume music, but Classic and Practice remain paused until their existing explicit Resume action. Godot dispatches `_notification` throughout the script inheritance chain; the audio subclass deliberately does not call the inherited notification a second time. New successful persisted Practice outcomes emit one result effect; failed saves/repeated retries do not falsely sound successful.

## Reproduce and test

```sh
python3 scripts/generate_original_audio.py
python3 scripts/test_original_audio.py
python3 scripts/test_android_release_source.py
bash scripts/run-audio-tests.sh /path/to/Godot-4.7.2
bash scripts/run-audio-tests.sh /path/to/Godot-4.7.2 practice
bash scripts/run-audio-tests.sh /path/to/Godot-4.7.2 settings
bash scripts/run-practice-core-tests.sh /path/to/Godot-4.7.2
bash scripts/run-practice-archive-tests.sh /path/to/Godot-4.7.2
```

The generator uses only Python standard-library oscillators/envelopes and the original score embedded in its source. `assets/audio/PROVENANCE.json` binds generator/output SHA-256 values. `NOTICE.txt` describes actual authorship; no outside sample, artist, plugin/example recording, voice, downloaded audio or CC0 claim is involved. Runtime only loads the bounded precomputed files. Android explicitly includes the WAVs and these two notices; imported-resource remapping is also supported without changing the preserved iOS preset. Hearing, final Android package inclusion and native lifecycle verification still require the new genuine candidate.

The no-Editor headless fixture copies the real UI/model/archive chain and original font into a temporary project, with inert providers. Only its font-loader declaration changes from preload/import to direct raw `FontFile` loading. It does not run the original main scene's providers, access real user data, import native addons, or supply native/device evidence. The same fixture also runs the unchanged Practice integration suite. Music tests use the Dummy driver and do not claim listening evidence.

## Android successor and platform captions

Android is **1.2.0 (8)**. Saved provider maximum remains **6** from the retained preflight. Code **7** at `d2790fd808d1f218e6bdf72e2ef8102916826893` was built/QA-tested but, per Root, never uploaded. It is reserved as an unpublished predecessor; the metadata does not mislabel it as live. Fresh provider/all-track maximum and independent source review are required before a new normal build/sign/delivery. Existing Android workflow/version/certificate/immutable-artifact gates remain; only version pins, artifact name and audio test steps change. Old code-7 source/sign/QA evidence stays historical.

The root-requested caption formatter gives iOS `GLOBAL RANKINGS` in both the real menu footer and ranking caption. Android retains its existing cross-platform wording. The old inactive main source uses the same formatter. This addresses only the specific inherited wording; it does not prove an Apple policy outcome or authorize an Apple build/submission. Shared project version and all iOS export-preset bytes remain unchanged.
