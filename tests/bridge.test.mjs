import test from "node:test";
import assert from "node:assert/strict";
import { decodeWsFrames, encodeWsFrame } from "../apps/bridge/server.mjs";

function maskedTextFrame(text) {
  const payload = Buffer.from(text);
  const mask = Buffer.from([0x13, 0x37, 0x42, 0x99]);
  const header = payload.length < 126
    ? Buffer.from([0x81, 0x80 | payload.length])
    : (() => { const h = Buffer.alloc(4); h[0] = 0x81; h[1] = 0xFE; h.writeUInt16BE(payload.length, 2); return h; })();
  const masked = Buffer.from(payload);
  for (let i = 0; i < masked.length; i += 1) masked[i] ^= mask[i % 4];
  return Buffer.concat([header, mask, masked]);
}

test("WebSocket parser retains a frame split across TCP chunks", () => {
  const frame = maskedTextFrame(JSON.stringify({ type: "split" }));
  const first = decodeWsFrames(frame.subarray(0, 3));
  assert.deepEqual(first.messages, []);
  assert.equal(first.remainder.length, 3);
  const second = decodeWsFrames(Buffer.concat([first.remainder, frame.subarray(3)]));
  assert.deepEqual(second.messages, [{ text: '{"type":"split"}' }]);
  assert.equal(second.remainder.length, 0);
});

test("WebSocket parser handles multiple frames in one TCP chunk", () => {
  const frames = Buffer.concat([maskedTextFrame("one"), maskedTextFrame("two")]);
  const parsed = decodeWsFrames(frames);
  assert.deepEqual(parsed.messages, [{ text: "one" }, { text: "two" }]);
  assert.equal(parsed.remainder.length, 0);
});

test("server frame encoder remains compatible with the parser", () => {
  const parsed = decodeWsFrames(encodeWsFrame("bridge.connected"));
  assert.deepEqual(parsed.messages, [{ text: "bridge.connected" }]);
});
