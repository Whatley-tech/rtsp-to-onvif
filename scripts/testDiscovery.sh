#!/usr/bin/env bash
set -euo pipefail

BASE="http://10.8.0.74:8096/onvif"
CONTENT_TYPE='Content-Type: application/soap+xml; charset=utf-8'

do_request() {
  local name="$1"
  local url="$2"
  local payload="$3"

  echo
  echo "=== $name ==="
  echo "URL: $url"
  echo ""

  curl -sS -X POST "$url" \
    -H "$CONTENT_TYPE" \
    -d "$payload"
  echo
}

request_get_capabilities() {
  cat <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<Envelope xmlns="http://www.w3.org/2003/05/soap-envelope">
  <Body>
    <GetCapabilities xmlns="http://www.onvif.org/ver10/device/wsdl">
      <Category>All</Category>
    </GetCapabilities>
  </Body>
</Envelope>
EOF
}

request_get_device_information() {
  cat <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<Envelope xmlns="http://www.w3.org/2003/05/soap-envelope">
  <Body>
    <GetDeviceInformation xmlns="http://www.onvif.org/ver10/device/wsdl"/>
  </Body>
</Envelope>
EOF
}

request_get_profiles() {
  cat <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<Envelope xmlns="http://www.w3.org/2003/05/soap-envelope">
  <Body>
    <GetProfiles xmlns="http://www.onvif.org/ver10/media/wsdl"/>
  </Body>
</Envelope>
EOF
}

request_get_stream_uri() {
  cat <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<Envelope xmlns="http://www.w3.org/2003/05/soap-envelope">
  <Body>
    <GetStreamUri xmlns="http://www.onvif.org/ver10/media/wsdl">
      <StreamSetup>
        <Stream xmlns="http://www.onvif.org/ver10/schema">RTP-Unicast</Stream>
        <Transport xmlns="http://www.onvif.org/ver10/schema">
          <Protocol>RTSP</Protocol>
        </Transport>
      </StreamSetup>
      <ProfileToken>main_stream</ProfileToken>
    </GetStreamUri>
  </Body>
</Envelope>
EOF
}

request_get_snapshot_uri() {
  cat <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<Envelope xmlns="http://www.w3.org/2003/05/soap-envelope">
  <Body>
    <GetSnapshotUri xmlns="http://www.onvif.org/ver10/media/wsdl">
      <ProfileToken>main_stream</ProfileToken>
    </GetSnapshotUri>
  </Body>
</Envelope>
EOF
}


do_request "GetCapabilities" "$BASE/device_service" "$(request_get_capabilities)"
do_request "GetDeviceInformation" "$BASE/device_service" "$(request_get_device_information)"
do_request "GetProfiles" "$BASE/media_service" "$(request_get_profiles)"
do_request "GetStreamUri" "$BASE/media_service" "$(request_get_stream_uri)"
do_request "GetSnapshotUri" "$BASE/media_service" "$(request_get_snapshot_uri)"
