#!/system/bin/sh
# Media Keep Screen On - Magisk boot service
# Watches for apps holding the SCREEN_BRIGHT wake lock (video/keep-screen-on).
# If held  -> timeout = 24h (screen never auto-locks while playing)
# If not   -> timeout = user's normal timeout (default 60s, respects manual changes)

MODDIR=${0%/*}

VIDEO_TIMEOUT=86400000
NORMAL_TIMEOUT=60000
STATE=$MODDIR/last_timeout
prev=$(cat "$STATE" 2>/dev/null)

# Wait for boot to complete
while [ "$(getprop sys.boot_completed)" != "1" ]; do
  sleep 5
done
sleep 15

while true; do
  if dumpsys power 2>/dev/null | grep -q "SCREEN_BRIGHT_WAKE_LOCK"; then
    target=$VIDEO_TIMEOUT
  else
    target=$NORMAL_TIMEOUT
  fi

  cur=$(settings get system screen_off_timeout 2>/dev/null)

  # Detect manual change made by user between our writes: value differs from
  # what we last wrote AND differs from current target
  if [ -n "$cur" ] && [ "$cur" != "null" ] && [ -n "$prev" ] && [ "$cur" != "$prev" ] && [ "$cur" != "$target" ]; then
    NORMAL_TIMEOUT=$cur
    target=$NORMAL_TIMEOUT
  fi

  if [ "$cur" != "$target" ]; then
    settings put system screen_off_timeout "$target"
  fi
  echo "$target" > "$STATE"
  prev=$target

  sleep 5
done &
