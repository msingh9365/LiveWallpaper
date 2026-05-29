# 🎬 LiveWallpaper for macOS

A lightweight, battery-friendly live wallpaper for macOS — no third-party apps, no subscriptions.

Your video plays behind your desktop icons, exactly like apps such as Wallspace, but entirely free and under your control.

---

## ✨ Features

- **Zero third-party dependencies** — pure Swift, uses only built-in macOS frameworks
- **Battery smart** — auto-pauses on battery power (toggleable from menu bar)
- **Sleep aware** — pauses on screen sleep, system sleep, and screensaver
- **Multi-monitor** — automatically spans all connected displays
- **Hot-plug displays** — adapts when you connect/disconnect external monitors
- **Menu bar control** — play/pause, battery toggle, status info, quit
- **Invisible** — no Dock icon, no window in Cmd+Tab, clicks pass through to desktop
- **Hardware accelerated** — uses Apple's VideoToolbox hardware decoder (near-zero CPU on M-series)

---

## 📋 Requirements

- **macOS 14.0 (Sonoma)** or newer
- **Apple Silicon** (M1/M2/M3/M4) or Intel Mac
- A looping video file in `.mp4`, `.m4v`, or `.mov` format

---

## 🚀 Quick Start

### Step 1: Get a Video

You need a short looping video. Good sources:
- [Pixabay Videos](https://pixabay.com/videos/) (free, no attribution needed)
- [Pexels Videos](https://www.pexels.com/videos/) (free)
- Any video you already have

Save it somewhere accessible, e.g. `~/Movies/wallpaper.mp4`

### Step 2: Build

Open Terminal and run:

```bash
cd /Users/manish/.gemini/antigravity/scratch/LiveWallpaper
chmod +x build.sh
./build.sh
```

You should see:
```
🔨  Compiling LiveWallpaper…
✅  Built: /Users/manish/.gemini/antigravity/scratch/LiveWallpaper/LiveWallpaper
```

### Step 3: Run

```bash
./LiveWallpaper ~/Movies/wallpaper.mp4
```

That's it! You should see:
- Your video playing as the desktop wallpaper
- A small ▶/⏸ icon in the menu bar

### Step 4: Stop

Either:
- Click the menu bar icon → **Quit Live Wallpaper**
- Or press `Ctrl+C` in the terminal

---

## 🔄 Auto-Start on Login

If you want the wallpaper to start automatically every time you log in:

### Install

```bash
# 1. Edit the plist to point to YOUR video file
#    (the binary path is already set — only change the video path)
nano /Users/manish/.gemini/antigravity/scratch/LiveWallpaper/com.manish.livewallpaper.plist

# 2. Copy to LaunchAgents
cp /Users/manish/.gemini/antigravity/scratch/LiveWallpaper/com.manish.livewallpaper.plist \
   ~/Library/LaunchAgents/

# 3. Load it
launchctl load ~/Library/LaunchAgents/com.manish.livewallpaper.plist
```

### Uninstall

```bash
launchctl unload ~/Library/LaunchAgents/com.manish.livewallpaper.plist
rm ~/Library/LaunchAgents/com.manish.livewallpaper.plist
```

---

## 🎛️ Menu Bar Controls

Once running, click the icon in your menu bar:

| Item | Description |
|------|-------------|
| 🎬 filename.mp4 | Shows which video is playing |
| ⏸ Pause / ▶ Play | Toggle wallpaper playback |
| 🔋 Battery toggle | Choose: auto-pause on battery (default) or allow playback |
| 🔌 AC / 🔋 Battery | Current power source |
| 🖥 Screen status | Awake or sleeping |
| 🖥 Display count | Number of screens with wallpaper |
| Quit | Stops the wallpaper completely |

---

## 🔋 Battery & Performance

This app is designed to be as lightweight as possible:

| Optimization | What it does |
|-------------|--------------|
| **Hardware decode** | Uses Apple's VideoToolbox chip — CPU stays near 0% |
| **Resolution capping** | Decodes only at your screen's resolution, not the video's native res |
| **2-second buffer** | Minimal memory usage (vs. unlimited default) |
| **Auto-pause on battery** | Stops all decoding and GPU work on battery |
| **Auto-pause on sleep** | Stops when screen sleeps, system sleeps, or screensaver activates |
| **Background priority** | LaunchAgent runs at Nice=10 — your apps always get priority |
| **Optimized build** | Compiled with `-O` for lower runtime overhead |

### Recommended Video Settings

For the best battery life, use videos matching these specs:

| Setting | Recommended | Why |
|---------|------------|-----|
| **Codec** | H.265 (HEVC) | M-series has dedicated HEVC hardware decoder |
| **Resolution** | Match your screen (e.g. 2880×1800 for 14" MBP) | Avoids downscale overhead |
| **Frame rate** | 24–30 fps | 60fps doubles GPU compositing for no visible benefit on a wallpaper |
| **Duration** | 10–60 seconds | Loops seamlessly; longer = more disk cache |
| **Audio** | Strip it | Wallpaper is always muted anyway |

### Convert Any Video with ffmpeg

```bash
# Install ffmpeg (if not already installed)
brew install ffmpeg

# Convert to optimal wallpaper format
ffmpeg -i input.mp4 -c:v hevc_videotoolbox -b:v 8M -r 30 -an wallpaper.mp4
```

Breakdown:
- `-c:v hevc_videotoolbox` — hardware-accelerated HEVC encoding
- `-b:v 8M` — 8 Mbps bitrate (good quality for wallpaper)
- `-r 30` — 30 fps
- `-an` — strip audio track

---

## ⚠️ Error Messages

The app validates everything **before** making any changes to your desktop:

| Error | Cause | Fix |
|-------|-------|-----|
| "No video file specified" | Ran without arguments | Add the video path: `./LiveWallpaper ~/Movies/wall.mp4` |
| "File not found" | Path doesn't exist | Check the path, use Tab-completion |
| "Unsupported format: .mkv" | Not a supported container | Convert to .mp4 with ffmpeg (see above) |
| "Cannot play" + codec error | File is corrupt or uses unsupported codec | Re-encode with ffmpeg (see above) |
| "Playback failed" (during playback) | Video stream error mid-playback | Try a different video file |

---

## 🗂️ Files

| File | Purpose |
|------|---------|
| `LiveWallpaper.swift` | Source code |
| `LiveWallpaper` | Compiled binary (after build) |
| `build.sh` | One-command build script |
| `com.manish.livewallpaper.plist` | LaunchAgent for auto-start on login |

---

## 🛠️ Troubleshooting

### "The wallpaper doesn't appear"
- Make sure the video file exists and is a valid `.mp4`/`.m4v`/`.mov`
- Try right-clicking your desktop → check if Finder's "Show Desktop Icons" is enabled
- On macOS Sequoia+, check System Settings → Desktop & Dock → Stage Manager is off (Stage Manager can interfere with desktop-level windows)

### "The wallpaper covers my desktop icons"
- This shouldn't happen — the window is placed *below* the desktop icon layer
- If it does: quit and relaunch. Display configuration changes can occasionally cause ordering issues

### "High CPU/GPU usage"
- Check your video: is it 4K 60fps? Use the ffmpeg command above to make a 30fps version
- Check Activity Monitor → Energy tab → make sure LiveWallpaper shows low energy impact
- Toggle the battery option off (default) — this ensures it pauses when unplugged

### "I want to change the video"
- Quit the current instance (menu bar → Quit)
- Relaunch with the new video path
- If using auto-start, edit the plist and reload:
  ```bash
  launchctl unload ~/Library/LaunchAgents/com.manish.livewallpaper.plist
  # Edit the video path in the plist
  launchctl load ~/Library/LaunchAgents/com.manish.livewallpaper.plist
  ```

---

## 📝 How It Works (Technical)

1. Creates a borderless, click-through window at `CGWindowLevelForKey(.desktopWindow) + 1` — this places it between macOS's wallpaper layer and Finder's desktop icons
2. Uses `AVQueuePlayer` + `AVPlayerLooper` for gapless video looping (no black frame flash at loop points)
3. Monitors power source via `IOKit` callbacks — pauses instantly when AC is unplugged
4. Listens for `screensDidSleep`, `willSleep`, `screensaver.didstart` notifications to pause during inactivity
5. `preferredMaximumResolution` tells the hardware decoder to output at screen resolution, not the video's native resolution — saves GPU work
6. Runs as `.accessory` activation policy — no Dock icon, no entry in Cmd+Tab
