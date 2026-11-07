#!/bin/bash
set -e

# --- 1. CONFIGURATION ---
export TMP_DIR=$(mktemp -d)
OUTPUT_DIR="./output"
export ASSETS_DIR="./assets"
mkdir -p "$OUTPUT_DIR" "$ASSETS_DIR" "$TMP_DIR/audio"

export WALLPAPER_FOLDER_ID="1fgHvSyJQzNbc0etlfSyu3rnHfXne3oTi"
export ARCHIVE_FOLDER_ID="190G9vBYRwQb4VqHGfmGExdjhH0phgA4t" 
export AUDIO_FOLDER_ID="1IgGUF3cbHUU5YpG7s5QLKRBDQsuV81FU"
export EFFECTS_FOLDER_ID="1PPBV5ix-gOkCamAL5pyeLyIjCf1kawH4"
export SPOTIFY_FILE_ID="1fIcEuSGsSBaRWO9OsFZYCTcynhMs7XOh"
export SPOTIFY_PLAYLIST="https://open.spotify.com/playlist/7de3PjT9RXz0qhzdXjl34c?go=1"
export APPLE_MUSIC_PLAYLIST="https://music.apple.com/in/playlist/pl.u-r2yBDbPCREqBKRZ"
export YOUTUBE_MUSIC_PLAYLIST="https://music.youtube.com/playlist?list=PLJoTxH8aW35XwA_sFqMgbAzCae8LIdaWn"
export AMAZON_MUSIC_PLAYLIST="https://music.amazon.com/user-playlists/1661fcf9d5a345ae8a288b32472248f0i8n0"

export MIN_DURATION=3600  
export MAX_DURATION=3900  

# Add your Webhook URL here
export WEBHOOK_URL="https://connect.pabbly.com/webhook-listener/webhook/IjU3NjIwNTY1MDYzZTA0MzI1MjZlNTUzYyI_3D_pc/IjU3NjcwNTZiMDYzNDA0MzI1MjZjNTUzNjUxMzci_pc"

# --- 2. ASSET CHECK & RANDOM TITLE GENERATION ---
if [ ! -f "$ASSETS_DIR/titles.txt" ]; then
    echo "❌ Error: $ASSETS_DIR/titles.txt not found!"
    exit 1
fi

SELECTED_TITLE=$(shuf -n 1 "$ASSETS_DIR/titles.txt")
export SAFE_TITLE=$(echo "$SELECTED_TITLE" | tr ' ' '_')
echo "🏷️ Selected Title: $SELECTED_TITLE -> $SAFE_TITLE.mp4"

if [ -f "$ASSETS_DIR/effect.mp4" ]; then export NEED_EFFECT_DOWNLOAD="0"; else export NEED_EFFECT_DOWNLOAD="1"; fi
if [ -f "$ASSETS_DIR/spotify.png" ]; then export NEED_SPOTIFY_DOWNLOAD="0"; else export NEED_SPOTIFY_DOWNLOAD="1"; fi

echo "📥 Step 1: Fetching Wallpaper & Batch Audio..."

# --- 3. PYTHON GOOGLE DRIVE FETCHER ---
python3 - << 'EOF'
import os, json, random, subprocess
from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.http import MediaIoBaseDownload

tmp_dir = os.environ["TMP_DIR"]
assets_dir = os.environ["ASSETS_DIR"]
wallpaper_folder = os.environ["WALLPAPER_FOLDER_ID"]
audio_folder = os.environ["AUDIO_FOLDER_ID"]
effects_folder = os.environ["EFFECTS_FOLDER_ID"]
spotify_file_id = os.environ["SPOTIFY_FILE_ID"]
need_effect = os.environ["NEED_EFFECT_DOWNLOAD"] == "1"
need_spotify = os.environ["NEED_SPOTIFY_DOWNLOAD"] == "1"
min_dur = float(os.environ["MIN_DURATION"])

sa_info = json.loads(os.environ["GDRIVE_SERVICE_ACCOUNT"])
creds = service_account.Credentials.from_service_account_info(
    sa_info, scopes=["https://www.googleapis.com/auth/drive"]
)
service = build("drive", "v3", credentials=creds)

def download_file(file_id, dest_path):
    request = service.files().get_media(fileId=file_id)
    with open(dest_path, "wb") as f:
        downloader = MediaIoBaseDownload(f, request)
        done = False
        while not done:
            _, done = downloader.next_chunk()

wp_res = service.files().list(
    q=f"'{wallpaper_folder}' in parents and mimeType contains 'image/' and trashed=false",
    orderBy="createdTime asc", pageSize=1, fields="files(id, name)"
).execute()

wp_files = wp_res.get("files", [])
if not wp_files: raise RuntimeError("❌ No wallpaper found!")

wp = wp_files[0]
print(f"🖼️ Oldest Wallpaper: {wp['name']}")
download_file(wp["id"], os.path.join(tmp_dir, "wallpaper.jpg"))

with open(os.path.join(tmp_dir, "wp_id.txt"), "w") as f:
    f.write(wp["id"])

if need_effect:
    eff_res = service.files().list(q=f"'{effects_folder}' in parents and mimeType contains 'video/' and trashed=false", pageSize=1, fields="files(id)").execute()
    if eff_res.get("files"): download_file(eff_res["files"][0]["id"], os.path.join(assets_dir, "effect.mp4"))

if need_spotify:
    try: download_file(spotify_file_id, os.path.join(assets_dir, "spotify.png"))
    except: pass

aud_res = service.files().list(
    q=f"'{audio_folder}' in parents and (mimeType contains 'audio/' or name contains '.mp3') and trashed=false",
    pageSize=200, fields="files(id, name)"
).execute()

audio_files = aud_res.get("files", [])
if not audio_files: raise RuntimeError("❌ No audio files found!")

random.shuffle(audio_files)
batch = audio_files[:8]
downloaded_tracks = []

for idx, aud in enumerate(batch):
    local_aud = os.path.join(tmp_dir, "audio", f"track_{idx}.mp3")
    download_file(aud["id"], local_aud)
    
    probe = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", local_aud],
        capture_output=True, text=True
    )
    try:
        dur = float(probe.stdout.strip())
        downloaded_tracks.append((local_aud, dur))
    except ValueError:
        os.remove(local_aud)

if not downloaded_tracks: raise RuntimeError("❌ Failed to process any audio tracks!")

total_duration = 0.0
selected_paths = []
track_idx = 0

print("⏳ Assembling 1-hour audio playlist...")
while total_duration < min_dur:
    track_path, track_dur = downloaded_tracks[track_idx % len(downloaded_tracks)]
    selected_paths.append(track_path)
    total_duration += track_dur
    track_idx += 1
    
print(f"🎵 Playlist Complete: {len(selected_paths)} tracks queued | Total Time: {total_duration/60:.2f} mins")

with open(os.path.join(tmp_dir, "audio_list.txt"), "w") as list_file:
    for p in selected_paths:
        list_file.write(f"file '{p}'\n")
EOF

# --- 4. THUMBNAIL GENERATION ---
echo "🖼️ Generating Thumbnail..."
TARGET_WORD=$(python3 -c "
import sys, re
title = sys.argv[1].strip()
words = title.split()
first = words[0].lower() if words else 'music'
res = re.sub(r'[^a-z0-9]', '', first)
final_text = f'{res}.'.lower()
print(final_text)
" "$SELECTED_TITLE")

echo "Extracted Word for Thumbnail: $TARGET_WORD"

FONT_FILE="$ASSETS_DIR/font.ttf"
if [ ! -f "$FONT_FILE" ]; then
    echo "Downloading extra-bold cinematic font..."
    curl -L -o "$FONT_FILE" "https://github.com/google/fonts/raw/main/ofl/montserrat/Montserrat-Black.ttf"
fi

export THUMBNAIL_FILE="$OUTPUT_DIR/thumbnail.jpg"

ffmpeg -i "$TMP_DIR/wallpaper.jpg" -vf "scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080,drawtext=fontfile=$FONT_FILE:text='$TARGET_WORD':fontsize=150:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2" -frames:v 1 "$THUMBNAIL_FILE" -y -loglevel error

# --- 5. MERGE AUDIO ---
echo "🔊 Step 2: Merging audio tracks..."
RAW_AUDIO="$TMP_DIR/raw_audio.m4a"
MERGED_AUDIO="$TMP_DIR/merged_audio.m4a"

ffmpeg -f concat -safe 0 -i "$TMP_DIR/audio_list.txt" \
  -vn -ar 44100 -ac 2 -c:a aac -b:a 128k "$RAW_AUDIO" -y -loglevel error

DURATION=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$RAW_AUDIO" | tr -d '\n' | tr -d '\r')
AUDIO_FADE_START=$(awk -v d="$DURATION" 'BEGIN { printf "%.2f", (d > 3) ? d - 3 : 0 }')

# 3-second audio fades
ffmpeg -i "$RAW_AUDIO" \
  -af "afade=t=in:st=0:d=3,afade=t=out:st=${AUDIO_FADE_START}:d=3" \
  -c:a aac -b:a 128k "$MERGED_AUDIO" -y -loglevel error

# --- 6. RENDER VIDEO ---
echo "🎬 Step 3: Fast chunking with synchronized loop..."

# Dynamically measure the exact length of the effect video
EFFECT_DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$ASSETS_DIR/effect.mp4" | tr -d '\n' | tr -d '\r')
if ! [[ $EFFECT_DUR =~ ^[0-9]+(\.[0-9]+)?$ ]]; then EFFECT_DUR=10.0; fi

read INTRO_DUR MID_DUR NUM_MIDS OUTRO_DUR OUTRO_FADE_START CHUNK_DUR <<< $(python3 -c "
import math
dur = float('$DURATION')
effect_dur = float('$EFFECT_DUR')
if effect_dur <= 0: effect_dur = 10.0

# Create a chunk large enough to fit the Spotify logo, ending EXACTLY on an effect loop boundary
multiplier = max(1, math.ceil(10.0 / effect_dur))
chunk_dur = round(effect_dur * multiplier, 3)

intro_dur = chunk_dur
mid_dur = chunk_dur
num_mids = int((dur - intro_dur) // mid_dur)
outro_dur = round(dur - intro_dur - (num_mids * mid_dur), 2)

# Ensure the outro is at least 3 seconds for the fade-out
if outro_dur < 3.0 and num_mids > 0:
    num_mids -= 1
    outro_dur += mid_dur

fade_start = round(max(0.1, outro_dur - 3.0), 2)
print(f'{intro_dur} {mid_dur} {num_mids} {outro_dur} {fade_start} {chunk_dur}')
")

BLENDED_MASTER="$TMP_DIR/blended_master.mp4"

# Generate a master chunk that matches your effect's exact duration
ffmpeg -loop 1 -framerate 24 -i "$TMP_DIR/wallpaper.jpg" \
  -stream_loop -1 -i "$ASSETS_DIR/effect.mp4" -t "$CHUNK_DUR" \
  -filter_complex "\
    [0:v]scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080,setsar=1,fps=24,format=gbrp[bg];\
    [1:v]scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080,setsar=1,fps=24,format=gbrp[eff];\
    [bg][eff]blend=all_mode=screen:all_opacity=1.0,format=yuv420p[v]" \
  -map "[v]" -c:v libx264 -preset veryfast -crf 20 -an "$BLENDED_MASTER" -y -loglevel error

ENC_FLAGS="-c:v libx264 -profile:v high -level:v 4.0 -preset veryfast -crf 26 -maxrate 1500k -bufsize 3000k -r 24 -pix_fmt yuv420p -video_track_timescale 12288 -an"

# Apply 3-second video fade in to intro
ffmpeg -i "$BLENDED_MASTER" -loop 1 -framerate 24 -i "$ASSETS_DIR/spotify.png" \
  -filter_complex "\
    [0:v]fade=t=in:st=0:d=3[base];\
    [1:v]scale=180:-1,format=rgba,fade=t=in:st=1:d=1:alpha=1,fade=t=out:st=6:d=1:alpha=1[logo];\
    [base][logo]overlay=x=30:y=30:enable='between(t,1,7)',format=yuv420p[outv]" \
  -map "[outv]" -t "$INTRO_DUR" $ENC_FLAGS "$TMP_DIR/intro.mp4" -y -loglevel error

ffmpeg -i "$BLENDED_MASTER" -t "$MID_DUR" $ENC_FLAGS "$TMP_DIR/middle.mp4" -y -loglevel error

# Apply 3-second video fade out to outro
ffmpeg -i "$BLENDED_MASTER" -t "$OUTRO_DUR" -vf "fade=t=out:st=${OUTRO_FADE_START}:d=3" $ENC_FLAGS "$TMP_DIR/outro.mp4" -y -loglevel error

VIDEO_LIST="$TMP_DIR/video_list.txt"
echo "file '$TMP_DIR/intro.mp4'" > "$VIDEO_LIST"
for ((i=1; i<=NUM_MIDS; i++)); do
    echo "file '$TMP_DIR/middle.mp4'" >> "$VIDEO_LIST"
done
echo "file '$TMP_DIR/outro.mp4'" >> "$VIDEO_LIST"

export OUT_FILENAME="${SAFE_TITLE}.mp4"
export OUT_FILE="$OUTPUT_DIR/$OUT_FILENAME"

ffmpeg -f concat -safe 0 -i "$VIDEO_LIST" -i "$MERGED_AUDIO" \
  -map 0:v:0 -map 1:a:0 -c:v copy -c:a copy -t "$DURATION" \
  -movflags +faststart "$OUT_FILE" -y -loglevel warning

echo "✅ Video created: $OUT_FILE ($(du -h "$OUT_FILE" | cut -f1))"

# --- 7. GITHUB RELEASES & CLEANUP ---
if [ -f "$OUT_FILE" ]; then
    echo "📤 Step 4: Pushing to GitHub Releases..."
    
DESCRIPTION="🎧 Listen on Spotify:
$SPOTIFY_PLAYLIST

🎵 Listen on Apple Music:
$APPLE_MUSIC_PLAYLIST

▶️ Listen on YouTube Music:
$YOUTUBE_MUSIC_PLAYLIST

🎧 Listen on Amazon Music:
$AMAZON_MUSIC_PLAYLIST

🚀 Want your track featured:
https://www.fiverr.com/hitblazz/promote-your-ambient-music-tracks

#aesthetic #snow #winter #moody #cinematic #vibes #nyc #snowing #nature"

    TAG_NAME="video-$(date +%s)"
    CLEAN_TITLE=$(echo "$SELECTED_TITLE" | tr '_' ' ')
    
    gh release create "$TAG_NAME" "$OUT_FILE" "$THUMBNAIL_FILE" --title "$CLEAN_TITLE" --notes "$DESCRIPTION"
    echo "✅ GitHub Release created successfully!"
    
   # --- 8. SEND WEBHOOK ---
    echo "🌐 Step 5: Sending Webhook..."
    
    # Extract asset URLs from the release (Fixed to ignore GitHub name changes)
    VIDEO_URL=$(gh release view "$TAG_NAME" --json assets --jq '.assets[] | select(.name | endswith(".mp4")) | .url')
    THUMB_URL=$(gh release view "$TAG_NAME" --json assets --jq '.assets[] | select(.name == "thumbnail.jpg") | .url')
    
    # Generate custom caption with actual links
    CAPTION="Listen on $SPOTIFY_PLAYLIST
$APPLE_MUSIC_PLAYLIST
$YOUTUBE_MUSIC_PLAYLIST
$AMAZON_MUSIC_PLAYLIST"

    # Use jq to securely build the JSON payload
    JSON_PAYLOAD=$(jq -n \
      --arg video "$VIDEO_URL" \
      --arg thumb "$THUMB_URL" \
      --arg caption "$CAPTION" \
      '{video_url: $video, thumbnail_url: $thumb, caption: $caption}')

    if [ -n "$WEBHOOK_URL" ] && [ "$WEBHOOK_URL" != "https://your-webhook-endpoint.com/here" ]; then
        curl -s -X POST "$WEBHOOK_URL" \
             -H "Content-Type: application/json" \
             -d "$JSON_PAYLOAD"
        echo -e "\n✅ Webhook dispatched successfully!"
    else
        echo "⚠️ WEBHOOK_URL not configured. Skipping webhook step."
    fi

  # ---------------------------------------------------------
    # SMART CLEANUP: Keeps the latest 3 releases, deletes the rest
    # ---------------------------------------------------------
    echo "🧹 Cleaning up old releases (Keeping latest 3 for Zapier)..."
    
    # Safely extract tag names using JSON to avoid filename space issues
    gh release list --limit 100 --json tagName --jq '.[].tagName' | grep '^video-' | tail -n +4 | while read -r OLD_TAG; do
        if [ -n "$OLD_TAG" ]; then
            echo "Deleting old release and tag: $OLD_TAG"
            gh release delete "$OLD_TAG" -y --cleanup-tag || true
        fi
    done
    
    # Secondary cleanup for orphaned git tags on the remote
    git fetch --tags --force
    git tag -l "video-*" | sort -rV | tail -n +4 | while read -r LEFTOVER_TAG; do
        if [ -n "$LEFTOVER_TAG" ]; then
            git push --delete origin "$LEFTOVER_TAG" || true
        fi
    done
    
    echo "📦 Archiving Wallpaper..."
    python3 - << 'EOF2'
import os, json
from google.oauth2 import service_account
from googleapiclient.discovery import build

wp_id = open(os.path.join(os.environ["TMP_DIR"], "wp_id.txt")).read().strip()
archive_folder = os.environ["ARCHIVE_FOLDER_ID"]
wallpaper_folder = os.environ["WALLPAPER_FOLDER_ID"]

sa_info = json.loads(os.environ["GDRIVE_SERVICE_ACCOUNT"])
creds = service_account.Credentials.from_service_account_info(sa_info, scopes=["https://www.googleapis.com/auth/drive"])
service = build("drive", "v3", credentials=creds)

service.files().update(
    fileId=wp_id,
    addParents=archive_folder,
    removeParents=wallpaper_folder,
    fields='id, parents'
).execute()
print("✅ Wallpaper archived successfully.")
EOF2

fi

rm -rf "$TMP_DIR"
