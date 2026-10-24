import test from 'node:test';
import assert from 'node:assert/strict';
import { createIdentity, identityFrom, hashPassword, checkPassword, safeUpstream, isLoopback, filterMobileCookies } from '../lib/security.js';
import { verify, createPublicKey } from 'node:crypto';

test('passwords use salted scrypt and reject incorrect strings',()=>{
  const a=hashPassword('abc12345'), b=hashPassword('abc12345');
  assert.notEqual(a,b);
  assert.equal(checkPassword('abc12345',a),true);
  assert.equal(checkPassword('abcd1234',a),false);
  assert.equal(checkPassword('',a),false);
});
test('identity remains stable and signs exact info',()=>{
  const key=createIdentity();const a=identityFrom(key.privateKey),b=identityFrom(key.privateKey);
  assert.equal(a.id,b.id);assert.equal(a.publicKey,b.publicKey);
  const message={instanceId:a.id};const signature=a.sign(message);
  const pk=createPublicKey({key:Buffer.from(a.publicKey,'base64url'),format:'der',type:'spki'});
  assert.equal(verify(null,Buffer.from(JSON.stringify(message)),pk,Buffer.from(signature,'base64url')),true);
  assert.equal(verify(null,Buffer.from(JSON.stringify({instanceId:'fake'})),pk,Buffer.from(signature,'base64url')),false);
});
test('upstream rejects non-loopback SSRF endpoints',()=>{
  for(const url of ['http://example.com:80','http://192.168.1.1:3080','https://127.0.0.1:3080','http://127.0.0.1:3080/foo','http://localhost:3080@evil.com']){
    assert.throws(()=>safeUpstream(url));
  }
  assert.equal(safeUpstream('http://127.0.0.1:3080').port,'3080');
});
test('loopback detection and cookies are strict',()=>{
  assert.ok(isLoopback('::ffff:127.0.0.1'));assert.ok(isLoopback('::1'));
  assert.equal(isLoopback('192.168.1.3'),false);
  assert.equal(filterMobileCookies('a=1; dsh_mobile_session=x; b=2'),'a=1; b=2');
});
