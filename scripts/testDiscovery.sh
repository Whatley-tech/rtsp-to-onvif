#!/bin/bash
BASE="http://10.8.0.74:8096/onvif"
SOAP_HEADERS='-H "Content-Type: text/xml" -H "SOAPAction: \"\""'

# 1. GetCapabilities
curl -s -X POST $BASE/device_service \
  -H 'Content-Type: text/xml' \
  -d '<?xml version="1.0"?>
<Envelope xmlns="http://schemas.xmlsoap.org/soap/envelope/">
  <Body><GetCapabilities xmlns="http://www.onvif.org/ver10/device/wsdl">
    <Category>All</Category>
  </GetCapabilities></Body>
</Envelope>'

# 2. GetProfiles
curl -s -X POST $BASE/media_service \
  -H 'Content-Type: text/xml' \
  -d '<?xml version="1.0"?>
<Envelope xmlns="http://schemas.xmlsoap.org/soap/envelope/">
  <Body><GetProfiles xmlns="http://www.onvif.org/ver10/media/wsdl"/></Body>
</Envelope>'

# 3. GetStreamUri
curl -s -X POST $BASE/media_service \
  -H 'Content-Type: text/xml' \
  -d '<?xml version="1.0"?>
<Envelope xmlns="http://schemas.xmlsoap.org/soap/envelope/">
  <Body><GetStreamUri xmlns="http://www.onvif.org/ver10/media/wsdl">
    <StreamSetup>
      <Stream xmlns="http://www.onvif.org/ver10/schema">RTP-Unicast</Stream>
      <Transport xmlns="http://www.onvif.org/ver10/schema"><Protocol>RTSP</Protocol></Transport>
    </StreamSetup>
    <ProfileToken>Profile_1</ProfileToken>
  </GetStreamUri></Body>
</Envelope>'