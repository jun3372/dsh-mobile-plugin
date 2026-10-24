/**
 * Offline PNG QR encoder. No npm install required after unpacking the plugin.
 * QR matrix: Kazuhiko Arase's QRCode implementation, bundled under MIT/
 * Apache-2.0 terms; see docs/third-party and lib/vendor/QRCode/index.js.
 */
import { deflateSync } from 'node:zlib';
import QRCode from './vendor/QRCode/index.js';
import QRErrorCorrectLevel from './vendor/QRCode/QRErrorCorrectLevel.js';

const CRC_TABLE = new Uint32Array(256);
for (let n = 0; n < 256; n++) {
  let c = n;
  for (let i = 0; i < 8; i++) c = (c & 1) ? (0xedb88320 ^ (c >>> 1)) : (c >>> 1);
  CRC_TABLE[n] = c >>> 0;
}
const SIGNATURE = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
function chunk(tag, data) {
  const type = Buffer.from(tag, 'ascii');
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  let crc = 0xffffffff;
  for (const byte of type) crc = CRC_TABLE[(crc ^ byte) & 255] ^ (crc >>> 8);
  for (const byte of data) crc = CRC_TABLE[(crc ^ byte) & 255] ^ (crc >>> 8);
  const checksum = Buffer.alloc(4);
  checksum.writeUInt32BE((crc ^ 0xffffffff) >>> 0);
  return Buffer.concat([length, type, data, checksum]);
}

/** Encode a UTF-8 QR payload as a scannable PNG Data URL (8-bit gray, 4-module quiet zone). */
export function qrPngDataUrl(payload, {minPixels=280, maxPixels=1024}={}) {
  if (typeof payload !== 'string' || !payload) throw new Error('QR payload must be a nonempty string');
  const raw = Buffer.from(payload, 'utf8');
  if (raw.length > 2200) throw new Error('QR payload too large');
  const qr = new QRCode(-1, QRErrorCorrectLevel.M);
  // Old QR encoder stores one byte in each JavaScript character.
  qr.addData(raw.toString('latin1'));
  qr.make();
  const modules = qr.getModuleCount();
  const side = modules + 8; // >= 4 quiet modules on every side
  const scale = Math.max(3, Math.min(Math.floor(maxPixels / side), Math.ceil(minPixels / side)));
  const size = side * scale;
  const gray = Buffer.alloc(size * (size + 1), 255);
  for (let y = 0; y < size; y++) {
    const line = y * (size + 1);
    gray[line] = 0; // scanline PNG filter None
    const moduleY = Math.floor(y / scale) - 4;
    if (moduleY < 0 || moduleY >= modules) continue;
    for (let x = 0; x < size; x++) {
      const moduleX = Math.floor(x / scale) - 4;
      if (moduleX >= 0 && moduleX < modules && qr.isDark(moduleY, moduleX)) gray[line + 1 + x] = 0;
    }
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(size, 0);
  ihdr.writeUInt32BE(size, 4);
  ihdr[8] = 8; // grayscale at 8 bits
  const png = Buffer.concat([
    SIGNATURE,
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(gray, {level:9})),
    chunk('IEND', Buffer.alloc(0)),
  ]);
  return `data:image/png;base64,${png.toString('base64')}`;
}
