var sha = require('lib/sha');

assert(typeof(sha.jsSHA) === "object");

var test = new sha.jsSHA("This is a Test", "TEXT");

assert(typeof(test.getHMAC) === "function");
assert(typeof(test.getHash) === "function");

/* Test getHash for sha-256 and sha-512 in hex, bytes, and b64 */
var hash256_hex = test.getHash("SHA-256", "HEX");
var hash512_hex = test.getHash("SHA-512", "HEX");
var hash256_bytes = test.getHash("SHA-256", "BYTES");
var hash512_bytes = test.getHash("SHA-512", "BYTES");
var hash256_b64 = test.getHash("SHA-256", "B64");
var hash512_b64 = test.getHash("SHA-512", "B64");

/* Test getHMAC for sha-256 and sha-512 in hex, bytes, and b64 */
var hmac256_hex = test.getHMAC("sOmeXyZkEy", "TEXT", "SHA-256", "HEX");
var hmac512_hex = test.getHMAC("sOmeXyZkEy", "TEXT", "SHA-512", "HEX");
var hmac256_bytes = test.getHMAC("sOmeXyZkEy", "TEXT", "SHA-256", "BYTES");
var hmac512_bytes = test.getHMAC("sOmeXyZkEy", "TEXT", "SHA-512", "BYTES");
var hmac256_b64 = test.getHMAC("sOmeXyZkEy", "TEXT", "SHA-256", "B64");
var hmac512_b64 = test.getHMAC("sOmeXyZkEy", "TEXT", "SHA-512", "B64");

assert(hash256_hex.length === 64);
assert(hash512_hex.length === 128);
assert(hash256_bytes.length === 32);
assert(hash512_bytes.length === 64);
assert(hash256_b64.length === 44);
assert(hash512_b64.length === 88);

assert(hmac256_hex.length === 64);
assert(hmac512_hex.length === 128);
assert(hmac256_bytes.length === 32);
assert(hmac512_bytes.length === 64);
assert(hmac256_b64.length === 44);
assert(hmac512_b64.length === 88);
