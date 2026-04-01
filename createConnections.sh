#!/bin/bash
set -euo pipefail

# ── Prompt for encoder config ─────────────────────────────────────────
read -p "Number of RTSP/HDMI encoders: " NUM_ENCODERS
read -p "Ports per encoder: " PORTS_PER_ENCODER

PARENT=eth0

# ── Remove ALL existing onvif-* connections ───────────────────────────
echo "Cleaning up existing onvif connections..."
EXISTING=$(nmcli -t -f NAME con show | grep '^onvif-' || true)
if [ -n "$EXISTING" ]; then
  echo "$EXISTING" | while read -r NAME; do
    echo "  Removing: $NAME"
    nmcli con delete "$NAME"
  done
else
  echo "  None found."
fi

echo ""
echo "Creating $((NUM_ENCODERS * PORTS_PER_ENCODER)) virtual interfaces across $NUM_ENCODERS encoders x $PORTS_PER_ENCODER ports..."
echo ""

# ── Create interfaces ─────────────────────────────────────────────────
for enc in $(seq 1 "$NUM_ENCODERS"); do
  for port in $(seq 1 "$PORTS_PER_ENCODER"); do
    NAME="onvif-${enc}-${port}"
    MAC=$(printf '02:00:ee:%02x:%02x:00' "$enc" "$port")

    echo "  Creating: $NAME  MAC: $MAC"
    nmcli con add \
      type macvlan \
      ifname "$NAME" \
      dev "$PARENT" \
      mode bridge \
      connection.id "$NAME" \
      802-3-ethernet.cloned-mac-address "$MAC" \
      ipv4.method auto \
      ipv6.method ignore \
      connection.autoconnect yes
  done
done

# ── Bring up all interfaces ───────────────────────────────────────────
echo ""
echo "Activating interfaces..."
FAILED=()
for enc in $(seq 1 "$NUM_ENCODERS"); do
  for port in $(seq 1 "$PORTS_PER_ENCODER"); do
    NAME="onvif-${enc}-${port}"
    if nmcli con up "$NAME"; then
      echo "  UP: $NAME"
    else
      echo "  FAILED: $NAME"
      FAILED+=("$NAME")
    fi
  done
done

# ── Summary ───────────────────────────────────────────────────────────
echo ""
TOTAL=$((NUM_ENCODERS * PORTS_PER_ENCODER))
SUCCEEDED=$((TOTAL - ${#FAILED[@]}))
echo "Done: $SUCCEEDED/$TOTAL interfaces up"

if [ ${#FAILED[@]} -gt 0 ]; then
  echo ""
  echo "Failed interfaces:"
  for f in "${FAILED[@]}"; do
    echo "  - $f"
  done
  exit 1
fi