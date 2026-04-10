BASE="http://10.8.0.74:8096/onvif"

# 1. GetCapabilities
curl -s -X POST $BASE/device_service \
  -H 'Content-Type: application/soap+xml; charset=utf-8' \
  -d '<?xml version="1.0" encoding="UTF-8"?>
<Envelope xmlns="http://www.w3.org/2003/05/soap-envelope">
  <Body>
    <GetCapabilities xmlns="http://www.onvif.org/ver10/device/wsdl">
      <Category>All</Category>
    </GetCapabilities>
  </Body>
</Envelope>'

# 2. GetDeviceInformation
curl -s -X POST $BASE/device_service \
  -H 'Content-Type: application/soap+xml; charset=utf-8' \
  -d '<?xml version="1.0" encoding="UTF-8"?>
<Envelope xmlns="http://www.w3.org/2003/05/soap-envelope">
  <Body>
    <GetDeviceInformation xmlns="http://www.onvif.org/ver10/device/wsdl"/>
  </Body>
</Envelope>'

# 3. GetProfiles
curl -s -X POST $BASE/media_service \
  -H 'Content-Type: application/soap+xml; charset=utf-8' \
  -d '<?xml version="1.0" encoding="UTF-8"?>
<Envelope xmlns="http://www.w3.org/2003/05/soap-envelope">
  <Body>
    <GetProfiles xmlns="http://www.onvif.org/ver10/media/wsdl"/>
  </Body>
</Envelope>'

# 4. GetStreamUri (main_stream)
curl -s -X POST $BASE/media_service \
  -H 'Content-Type: application/soap+xml; charset=utf-8' \
  -d '<?xml version="1.0" encoding="UTF-8"?>
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
</Envelope>'

# 5. GetSnapshotUri
curl -s -X POST $BASE/media_service \
  -H 'Content-Type: application/soap+xml; charset=utf-8' \
  -d '<?xml version="1.0" encoding="UTF-8"?>
<Envelope xmlns="http://www.w3.org/2003/05/soap-envelope">
  <Body>
    <GetSnapshotUri xmlns="http://www.onvif.org/ver10/media/wsdl">
      <ProfileToken>main_stream</ProfileToken>
    </GetSnapshotUri>
  </Body>
</Envelope>'