#!/bin/bash
set -euo pipefail

# ── Prompt for encoder config ─────────────────────────────────────────
read -p "Number of RTSP/HDMI encoders: " NUM_ENCODERS
read -p "Ports per encoder: " PORTS_PER_ENCODER

BRIDGE=br0

# ── Create bridge if it doesn't exist ────────────────────────────────
if ! ip link show "$BRIDGE" &>/dev/null; then
  echo "Bridge $BRIDGE not found."
  read -p "Physical uplink interface (e.g. eth0): " UPLINK

  if ! ip link show "$UPLINK" &>/dev/null; then
    echo "ERROR: Interface $UPLINK does not exist."
    exit 1
  fi

  echo "Creating $BRIDGE and enslaving $UPLINK..."

  # Remove any existing NM connection on the uplink so it doesn't fight us
  NM_UPLINK=$(nmcli -t -f NAME,DEVICE con show --active | grep ":${UPLINK}$" | cut -d: -f1 || true)
  if [ -n "$NM_UPLINK" ]; then
    echo "  Releasing NM connection '$NM_UPLINK' from $UPLINK"
    nmcli con down "$NM_UPLINK" 2>/dev/null || true
  fi

  ip link add name "$BRIDGE" type bridge
  ip link set "$BRIDGE" up
  ip link set "$UPLINK" master "$BRIDGE"
  ip link set "$UPLINK" up

  # Pin br0's MAC to the uplink NIC so it never floats to a cam-*-sw interface
  UPLINK_MAC=$(ip link show "$UPLINK" | awk '/link\/ether/{print $2}')
  ip link set "$BRIDGE" address "$UPLINK_MAC"
  echo "  Pinned $BRIDGE MAC to $UPLINK_MAC"

  # Get a DHCP lease for the bridge itself
  nmcli con add \
    type bridge \
    ifname "$BRIDGE" \
    connection.id "${BRIDGE}-bridge" \
    ipv4.method auto \
    ipv6.method ignore \
    connection.autoconnect yes
  nmcli con up "${BRIDGE}-bridge"

  echo "  $BRIDGE is up."
  echo ""
else
  echo "Bridge $BRIDGE already exists — skipping creation."
  # Pin br0's MAC to its uplink NIC to prevent it floating to a cam-*-sw interface
  UPLINK=$(bridge link show | awk '/master br0/{print $2}' | sed 's/://' | grep -v '^cam-' | head -1 || true)
  if [ -n "$UPLINK" ]; then
    UPLINK_MAC=$(ip link show "$UPLINK" | awk '/link\/ether/{print $2}')
    ip link set "$BRIDGE" address "$UPLINK_MAC"
    echo "  Pinned $BRIDGE MAC to $UPLINK_MAC (from $UPLINK)"
  fi
  echo ""
fi

# Naming convention:
#   cam-ENC-PORT      → camera/service side (gets DHCP IP, ONVIF binds here)
#   cam-ENC-PORT-sw   → switchport side (plugged into br0, like a switch port)

# ── Remove ALL existing onvif-* NM connections and cam-* interfaces ───
echo "Cleaning up existing onvif connections..."
EXISTING=$(nmcli -t -f NAME con show | grep '^onvif-' || true)
if [ -n "$EXISTING" ]; then
  echo "$EXISTING" | while read -r NAME; do
    echo "  Removing NM connection: $NAME"
    nmcli con delete "$NAME" 2>/dev/null || true
  done
else
  echo "  No NM connections found."
fi

echo "Cleaning up existing cam-* interfaces..."
for iface in $(ip -br link show | awk '{print $1}' | sed 's/@.*//' | grep '^cam-' || true); do
  # Only delete the camera side (not -sw — it goes away automatically)
  if [[ "$iface" != *"-sw" ]]; then
    echo "  Removing: $iface"
    ip link delete "$iface" 2>/dev/null || true
  fi
done

echo ""
echo "Creating $((NUM_ENCODERS * PORTS_PER_ENCODER)) interfaces across $NUM_ENCODERS encoders x $PORTS_PER_ENCODER ports..."
echo ""

# ── Create veth pairs and attach to bridge ────────────────────────────
for enc in $(seq 1 "$NUM_ENCODERS"); do
  for port in $(seq 1 "$PORTS_PER_ENCODER"); do
    NM_NAME="onvif-${enc}-${port}"
    CAM="cam-${enc}-${port}"        # camera/service side — ONVIF binds here
    CAM_SW="cam-${enc}-${port}-sw"  # switchport side — plugged into br0
    MAC=$(printf '02:00:ee:%02x:%02x:00' "$enc" "$port")

    echo "  Creating: $CAM (MAC: $MAC)  switchport: $CAM_SW"

    # Create the veth pair
    ip link add "$CAM" type veth peer name "$CAM_SW"

    # Set deterministic MAC on the camera-facing side
    ip link set "$CAM" address "$MAC"

    # Plug the switchport end into br0 and bring it up
    ip link set "$CAM_SW" master "$BRIDGE"
    ip link set "$CAM_SW" up

    # Bring the camera side up
    ip link set "$CAM" up

    # Create NM connection for DHCP on the camera-facing interface
    nmcli con add \
      type ethernet \
      ifname "$CAM" \
      connection.id "$NM_NAME" \
      ipv4.method auto \
      ipv6.method ignore \
      connection.autoconnect yes
  done
done

# ── Bring up all NM connections (triggers DHCP) ───────────────────────
echo ""
echo "Activating interfaces (DHCP)..."
FAILED=()
for enc in $(seq 1 "$NUM_ENCODERS"); do
  for port in $(seq 1 "$PORTS_PER_ENCODER"); do
    NM_NAME="onvif-${enc}-${port}"
    if nmcli con up "$NM_NAME"; then
      echo "  UP: $NM_NAME"
    else
      echo "  FAILED: $NM_NAME"
      FAILED+=("$NM_NAME")
    fi
  done
done

# ── Summary ───────────────────────────────────────────────────────────
echo ""
TOTAL=$((NUM_ENCODERS * PORTS_PER_ENCODER))
SUCCEEDED=$((TOTAL - ${#FAILED[@]}))
echo "Done: $SUCCEEDED/$TOTAL interfaces up"

echo ""
echo "Bridge switchports:"
bridge link show | grep "master $BRIDGE" || true

echo ""
echo "IP assignments:"
ip -br addr show | grep '^cam-' | grep -v '\-sw' || true

if [ ${#FAILED[@]} -gt 0 ]; then
  echo ""
  echo "Failed interfaces:"
  for f in "${FAILED[@]}"; do
    echo "  - $f"
  done
  exit 1
fi