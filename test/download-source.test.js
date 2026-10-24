import test from 'node:test';
import assert from 'node:assert/strict';
import { buildDownloadUrl,allowedDownloadUrl,validateDownloadSource } from '../lib/download-source.js';
const asset='https://github.com/cloudflare/cloudflared/releases/download/2026.10.2/cloudflared-linux-amd64';
test('download source maps only official GitHub release assets to chosen HTTPS mirror',()=>{
  assert.equal(buildDownloadUrl(asset),asset);
  assert.equal(buildDownloadUrl(asset,'ghfast'),`https://ghfast.top/${asset}`);
  assert.equal(buildDownloadUrl(asset,'ghproxy'),`https://ghproxy.net/${asset}`);
  assert.equal(buildDownloadUrl(asset,'custom','https://mirror.example.com/'),`https://mirror.example.com/${asset}`);
  assert.equal(allowedDownloadUrl(`https://ghfast.top/${asset}`,'ghfast'),true);
  assert.equal(allowedDownloadUrl('https://release-assets.githubusercontent.com/item','ghfast'),true);
  assert.equal(allowedDownloadUrl('https://other.example.com/file','ghfast'),false);
});
test('download source rejects unsafe or arbitrary fetch URLs and redirects',()=>{
  for(const url of ['http://127.0.0.1/','https://localhost/','https://user:pass@example.com/','https://mirror.example.com:8443/','https://10.0.0.1/','ftp://mirror.example.com/'])
    assert.throws(()=>validateDownloadSource('custom',url));
  assert.throws(()=>validateDownloadSource('unknown',''));
  assert.throws(()=>buildDownloadUrl('https://example.com/a','ghfast'));
  assert.equal(allowedDownloadUrl('http://ghfast.top/https://github.com/frp','ghfast'),false);
  assert.equal(allowedDownloadUrl('https://ghfast.top/https://malicious.example/file','ghfast'),false);
  assert.equal(allowedDownloadUrl('https://ghfast.top/https://github.com/file','official'),false);
});
