/**
 * download-wsdl-deps.js
 *
 * Recursively downloads all remote WSDL/XSD files referenced by the local
 * device_service.wsdl and media_service.wsdl, saves them under wsdl/remote/
 * preserving the URL path structure, and rewrites all remote schemaLocation
 * and location attributes in the downloaded files to use relative file paths.
 *
 * Safe to call repeatedly: skips files that already exist on disk.
 * Pass --force to re-download everything.
 */

const https = require('https');
const http = require('http');
const fs = require('fs');
const path = require('path');
const { URL } = require('url');

const ROOT_DIR = path.resolve(__dirname, '..', 'wsdl', 'remote');
const FORCE = process.argv.includes('--force');
const MAX_REDIRECTS = 5;

// Seed URLs extracted from the two local WSDL files
const SEED_URLS = [
    'https://www.onvif.org/ver10/device/wsdl/devicemgmt.wsdl',
    'https://www.onvif.org/ver10/media/wsdl/media.wsdl',
];

// Track visited URLs to avoid infinite loops
const visited = new Set();

// W3C namespace URIs that return 403 for automated requests.
// These are standard, stable schemas that rarely (if ever) change.
const FALLBACK_SCHEMAS = {
    'https://www.w3.org/2005/05/xmlmime': `<?xml version="1.0" encoding="UTF-8"?>
<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
           xmlns:xmime="http://www.w3.org/2005/05/xmlmime"
           targetNamespace="http://www.w3.org/2005/05/xmlmime">
  <xs:attribute name="contentType" type="xs:string"/>
  <xs:attribute name="expectedContentTypes" type="xs:string"/>
  <xs:complexType name="base64Binary">
    <xs:simpleContent>
      <xs:extension base="xs:base64Binary">
        <xs:attribute ref="xmime:contentType"/>
      </xs:extension>
    </xs:simpleContent>
  </xs:complexType>
  <xs:complexType name="hexBinary">
    <xs:simpleContent>
      <xs:extension base="xs:hexBinary">
        <xs:attribute ref="xmime:contentType"/>
      </xs:extension>
    </xs:simpleContent>
  </xs:complexType>
</xs:schema>`,
    'https://www.w3.org/2004/08/xop/include': `<?xml version="1.0" encoding="UTF-8"?>
<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
           xmlns:xop="https://www.w3.org/2004/08/xop/include"
           targetNamespace="https://www.w3.org/2004/08/xop/include">
  <xs:element name="Include">
    <xs:complexType>
      <xs:sequence>
        <xs:any namespace="##other" minOccurs="0" maxOccurs="unbounded" processContents="lax"/>
      </xs:sequence>
      <xs:attribute name="href" type="xs:anyURI" use="required"/>
      <xs:anyAttribute namespace="##other" processContents="lax"/>
    </xs:complexType>
  </xs:element>
</xs:schema>`,
    'https://www.w3.org/2003/05/soap-envelope': `<?xml version="1.0" encoding="UTF-8"?>
<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
           xmlns:tns="http://www.w3.org/2003/05/soap-envelope"
           targetNamespace="http://www.w3.org/2003/05/soap-envelope"
           elementFormDefault="qualified">
  <xs:import namespace="http://www.w3.org/XML/1998/namespace"
             schemaLocation="http://www.w3.org/2001/xml.xsd"/>
  <xs:complexType name="Envelope">
    <xs:sequence>
      <xs:element ref="tns:Header" minOccurs="0"/>
      <xs:element ref="tns:Body"/>
    </xs:sequence>
    <xs:anyAttribute namespace="##other" processContents="lax"/>
  </xs:complexType>
  <xs:element name="Envelope" type="tns:Envelope"/>
  <xs:complexType name="Header">
    <xs:sequence>
      <xs:any namespace="##other" processContents="lax" minOccurs="0" maxOccurs="unbounded"/>
    </xs:sequence>
    <xs:anyAttribute namespace="##other" processContents="lax"/>
  </xs:complexType>
  <xs:element name="Header" type="tns:Header"/>
  <xs:complexType name="Body">
    <xs:sequence>
      <xs:any namespace="##any" processContents="lax" minOccurs="0" maxOccurs="unbounded"/>
    </xs:sequence>
    <xs:anyAttribute namespace="##other" processContents="lax"/>
  </xs:complexType>
  <xs:element name="Body" type="tns:Body"/>
  <xs:complexType name="Fault">
    <xs:sequence>
      <xs:element name="Code" type="tns:faultcode"/>
      <xs:element name="Reason" type="tns:faultreason"/>
      <xs:element name="Node" type="xs:anyURI" minOccurs="0"/>
      <xs:element name="Role" type="xs:anyURI" minOccurs="0"/>
      <xs:element name="Detail" type="tns:detail" minOccurs="0"/>
    </xs:sequence>
  </xs:complexType>
  <xs:element name="Fault" type="tns:Fault"/>
  <xs:complexType name="faultreason">
    <xs:sequence>
      <xs:element name="Text" type="tns:reasontext" maxOccurs="unbounded"/>
    </xs:sequence>
  </xs:complexType>
  <xs:complexType name="reasontext">
    <xs:simpleContent>
      <xs:extension base="xs:string">
        <xs:attribute ref="xml:lang" use="required"/>
      </xs:extension>
    </xs:simpleContent>
  </xs:complexType>
  <xs:complexType name="faultcode">
    <xs:sequence>
      <xs:element name="Value" type="xs:QName"/>
      <xs:element name="Subcode" type="tns:subcode" minOccurs="0"/>
    </xs:sequence>
  </xs:complexType>
  <xs:complexType name="subcode">
    <xs:sequence>
      <xs:element name="Value" type="xs:QName"/>
      <xs:element name="Subcode" type="tns:subcode" minOccurs="0"/>
    </xs:sequence>
  </xs:complexType>
  <xs:complexType name="detail">
    <xs:sequence>
      <xs:any namespace="##any" processContents="lax" minOccurs="0" maxOccurs="unbounded"/>
    </xs:sequence>
    <xs:anyAttribute namespace="##other" processContents="lax"/>
  </xs:complexType>
  <xs:complexType name="NotUnderstoodType">
    <xs:attribute name="qname" type="xs:QName" use="required"/>
  </xs:complexType>
  <xs:element name="NotUnderstood" type="tns:NotUnderstoodType"/>
  <xs:complexType name="UpgradeType">
    <xs:sequence>
      <xs:element name="SupportedEnvelope" type="tns:SupportedEnvType" maxOccurs="unbounded"/>
    </xs:sequence>
  </xs:complexType>
  <xs:complexType name="SupportedEnvType">
    <xs:attribute name="qname" type="xs:QName" use="required"/>
  </xs:complexType>
  <xs:element name="Upgrade" type="tns:UpgradeType"/>
</xs:schema>`,
};

/**
 * Convert a remote URL to its local filesystem path under wsdl/remote/
 * e.g. https://www.onvif.org/ver10/schema/onvif.xsd
 *   -> <root>/wsdl/remote/www.onvif.org/ver10/schema/onvif.xsd
 */
function urlToLocalPath(remoteUrl) {
    const parsed = new URL(remoteUrl);
    // Use hostname + pathname, strip any query/hash
    let filePath = path.join(ROOT_DIR, parsed.hostname, parsed.pathname);
    // If path ends with / or has no extension, treat it as an XSD fetched by namespace URI
    // (e.g. https://www.w3.org/2005/05/xmlmime returns an XSD)
    if (!path.extname(filePath)) {
        filePath += '.xsd';
    }
    return filePath;
}

/**
 * Fetch a URL, following redirects, returning the body as a string.
 */
function fetchUrl(targetUrl, redirectCount = 0) {
    return new Promise((resolve, reject) => {
        if (redirectCount > MAX_REDIRECTS) {
            return reject(new Error(`Too many redirects for ${targetUrl}`));
        }

        const mod = targetUrl.startsWith('https') ? https : http;
        const req = mod.get(targetUrl, { headers: { 'User-Agent': 'onvif-wsdl-downloader/1.0' }, timeout: 15000 }, (res) => {
            if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
                let redirect = res.headers.location;
                if (!redirect.startsWith('http')) {
                    redirect = new URL(redirect, targetUrl).href;
                }
                return resolve(fetchUrl(redirect, redirectCount + 1));
            }
            if (res.statusCode !== 200) {
                return reject(new Error(`HTTP ${res.statusCode} for ${targetUrl}`));
            }
            let data = '';
            res.on('data', (chunk) => data += chunk);
            res.on('end', () => resolve(data));
        });
        req.on('error', reject);
        req.on('timeout', () => { req.destroy(); reject(new Error(`Timeout fetching ${targetUrl}`)); });
    });
}

/**
 * Extract all remote and relative import/include URLs from WSDL/XSD content.
 * Returns an array of absolute URL strings.
 */
function extractImportUrls(content, baseUrl) {
    const urls = [];
    // Match location="..." and schemaLocation="..."
    const re = /(?:schemaLocation|location)\s*=\s*"([^"]+)"/g;
    let match;
    while ((match = re.exec(content)) !== null) {
        const loc = match[1];
        try {
            // Resolve relative URLs against the base
            const absolute = new URL(loc, baseUrl).href;
            if (absolute.startsWith('http://') || absolute.startsWith('https://')) {
                urls.push(absolute);
            }
        } catch (e) {
            // Skip malformed URLs
        }
    }
    return urls;
}

/**
 * Rewrite all remote URLs in the content to relative file paths.
 * The paths are relative from the file at `localFilePath` to the downloaded copy.
 */
function rewriteToLocal(content, localFilePath, baseUrl) {
    const re = /((?:schemaLocation|location)\s*=\s*")([^"]+)(")/g;
    return content.replace(re, (fullMatch, prefix, loc, suffix) => {
        let absolute;
        try {
            absolute = new URL(loc, baseUrl).href;
        } catch (e) {
            return fullMatch; // leave malformed URLs alone
        }

        if (!absolute.startsWith('http://') && !absolute.startsWith('https://')) {
            return fullMatch; // already local
        }

        const targetLocal = urlToLocalPath(absolute);
        let rel = path.relative(path.dirname(localFilePath), targetLocal);
        // Normalize to forward slashes for XML
        rel = rel.split(path.sep).join('/');
        return prefix + rel + suffix;
    });
}

/**
 * Recursively download a URL and all its imports.
 */
async function downloadRecursive(remoteUrl) {
    if (visited.has(remoteUrl)) return;
    visited.add(remoteUrl);

    const localPath = urlToLocalPath(remoteUrl);

    // Skip if already on disk (unless --force)
    if (!FORCE && fs.existsSync(localPath)) {
        // Still need to parse it for child imports
        const existing = fs.readFileSync(localPath, 'utf8');
        const childUrls = extractImportUrls(existing, remoteUrl);
        // But wait, existing file has rewritten paths. Re-extract from original?
        // Actually we need to re-check children from the rewritten file too.
        // Safest: just scan existing for any remaining remote URLs and download those.
        // If file is already rewritten, there won't be remote URLs, so this is a no-op.
        // For correctness with --force, we handle it below.
        // For incremental, we read the ORIGINAL if needed. But we don't have it.
        // Simple approach: if file exists and not --force, assume deps are satisfied.
        return;
    }

    let content;
    try {
        process.stdout.write(`  Downloading ${remoteUrl} ... `);
        content = await fetchUrl(remoteUrl);
        console.log('OK');
    } catch (err) {
        // Check for embedded fallback (known W3C schemas that block automated requests)
        if (FALLBACK_SCHEMAS[remoteUrl]) {
            content = FALLBACK_SCHEMAS[remoteUrl];
            console.log(`OK (using embedded fallback)`);
        } else {
            console.log(`FAILED (${err.message})`);
            // Write a placeholder comment so we don't retry every startup
            fs.mkdirSync(path.dirname(localPath), { recursive: true });
            fs.writeFileSync(localPath, `<!-- download failed: ${err.message} -->\n`);
            return;
        }
    }

    // Extract child imports BEFORE rewriting (so we have the original remote URLs)
    const childUrls = extractImportUrls(content, remoteUrl);

    // Rewrite remote URLs to local relative paths
    const rewritten = rewriteToLocal(content, localPath, remoteUrl);

    // Save to disk
    fs.mkdirSync(path.dirname(localPath), { recursive: true });
    fs.writeFileSync(localPath, rewritten, 'utf8');

    // Recurse into children
    for (const childUrl of childUrls) {
        await downloadRecursive(childUrl);
    }
}

/**
 * Main entry point. Returns a promise so callers can await it.
 */
async function downloadWsdlDeps() {
    console.log('WSDL: Checking remote dependencies...');

    // Check if all seed files already exist locally (fast path for normal startup)
    const allExist = SEED_URLS.every(u => fs.existsSync(urlToLocalPath(u)));

    if (allExist && !FORCE) {
        console.log('WSDL: All dependencies already cached locally. Skipping.');
        return;
    }

    // Download all remote dependencies recursively
    for (const seedUrl of SEED_URLS) {
        await downloadRecursive(seedUrl);
    }

    // Note: we do NOT rewrite the local wrapper WSDLs (device_service.wsdl,
    // media_service.wsdl). They keep their original remote URLs so that
    // clients fetching ?wsdl see valid imports. Server-side resolution to
    // local files is handled by overrideImportLocation in onvif-server.js.

    console.log(`WSDL: Done. Downloaded ${visited.size} files to wsdl/remote/`);
}

module.exports = { downloadWsdlDeps };

// Allow running standalone: node scripts/download-wsdl-deps.js [--force]
if (require.main === module) {
    downloadWsdlDeps().catch(err => {
        console.error('WSDL download failed:', err);
        process.exit(1);
    });
}