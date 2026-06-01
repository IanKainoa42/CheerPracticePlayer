# App Store Preview videos

Per-device App Store Preview MP4s for PracticeMix, derived from `source.mp4`.

## Files

| File | Resolution | Use for |
|---|---|---|
| `source.mp4` | 1080×1080 | Trimmed 30s source. Input to `scripts/make-previews.sh`. |
| `preview-iphone-6.9.mp4` | 886×1920 | iPhone 6.5" / 6.7" / 6.9" preview slots. |
| `preview-ipad-13.mp4` | 1200×1600 | iPad Pro 12.9" / 13" preview slots. |
| `preview-*-poster.png` | match video | Optional poster frame (ASC lets you pick a frame from the video itself too). |

All variants: H.264 high@4.0, AAC 48kHz stereo, 30fps, ≤30s. Square source is letterboxed (black bars top/bottom) into portrait.

## Regenerate from source

```bash
./scripts/make-previews.sh
```

Re-runs if `source.mp4` changes. Requires `ffmpeg` (brew install ffmpeg).

## Upload — option A: manual via App Store Connect (fastest)

1. App Store Connect → My Apps → PracticeMix → 1.0/1.1 version page
2. For each device size under "App Previews and Screenshots":
   - iPhone 6.9": drag `preview-iphone-6.9.mp4`
   - iPhone 6.7" / 6.5": same file (886×1920 covers all three)
   - iPad Pro 13" / 12.9": drag `preview-ipad-13.mp4`
3. ASC will let you pick a poster frame from inside the video
4. Save

## Upload — option B: via fastlane `ship_screenshots`

The existing `ship_screenshots` lane uploads everything under `fastlane/screenshots/` via deliver. To wire the previews into it:

```bash
mkdir -p fastlane/screenshots/en-US
cp marketing/app_previews/preview-iphone-6.9.mp4  "fastlane/screenshots/en-US/iPhone 6.9 Display.mp4"
cp marketing/app_previews/preview-ipad-13.mp4     "fastlane/screenshots/en-US/iPad Pro (6th generation) 13 inch.mp4"
bundle exec fastlane ship_screenshots
```

Folder/filename conventions deliver expects can shift between fastlane releases. If the upload fails with "unrecognized device", check `fastlane action deliver` for the exact device folder names your fastlane version recognizes and rename to match. Manual upload (option A) is the safer route for a first release.
