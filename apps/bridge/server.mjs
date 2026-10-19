import crypto from "node:crypto";
import fs from "node:fs/promises";
import http from "node:http";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, "../..");
const petRoot = path.join(repoRoot, "apps/pet-web");
const sharedRoot = path.join(repoRoot, "shared");
const port = Number(process.env.CHAOS_CAT_PORT || 44777);
const host = process.env.CHAOS_CAT_HOST || "127.0.0.1";

const clients = new Set();
const events = [];

const contentTypes = new Map([
  [".html", "text/html; charset=utf-8"],
  [".js", "text/javascript; charset=utf-8"],
  [".css", "text/css; charset=utf-8"],
  [".svg", "image/svg+xml; charset=utf-8"],
  [".json", "application/json; charset=utf-8"]
]);

function addEvent(event) {
  const normalized = {
    id: event.id || `${Date.now()}-${Math.random().toString(16).slice(2)}`,
    type: event.type || "unknown",
    source: event.source || "unknown",
    payload: event.payload || {},
    createdAt: event.createdAt || new Date().toISOString()
  };

  events.push(normalized);
  while (events.length > 250) events.shift();
  broadcast(normalized);
  return normalized;
}

function broadcast(data) {
  const message = encodeWsFrame(JSON.stringify(data));
  for (const client of clients) {
    try {
      client.write(message);
    } catch {
      clients.delete(client);
    }
  }
}

function readBody(request) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    request.on("data", (chunk) => chunks.push(chunk));
    request.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    request.on("error", reject);
  });
}

function sendJson(response, statusCode, payload) {
  response.writeHead(statusCode, {
    "content-type": "application/json; charset=utf-8",
    "access-control-allow-origin": "*",
    "access-control-allow-methods": "GET,POST,OPTIONS",
    "access-control-allow-headers": "content-type"
  });
  response.end(JSON.stringify(payload, null, 2));
}

async function serveStatic(request, response) {
  const url = new URL(request.url, `http://${request.headers.host}`);
  let pathname = decodeURIComponent(url.pathname);

  let root = petRoot;
  if (pathname.startsWith("/shared/")) {
    root = sharedRoot;
    pathname = pathname.replace(/^\/shared\//, "/");
  }

  const filePath = path.resolve(root, pathname === "/" ? "index.html" : pathname.slice(1));
  if (!filePath.startsWith(root)) {
    response.writeHead(403);
    response.end("Forbidden");
    return;
  }

  try {
    const content = await fs.readFile(filePath);
    response.writeHead(200, {
      "content-type": contentTypes.get(path.extname(filePath)) || "application/octet-stream",
      "cache-control": "no-store"
    });
    response.end(content);
  } catch {
    response.writeHead(404);
    response.end("Not found");
  }
}

function encodeWsFrame(text) {
  const payload = Buffer.from(text);
  const length = payload.length;

  if (length < 126) {
    return Buffer.concat([Buffer.from([0x81, length]), payload]);
  }

  if (length < 65536) {
    const header = Buffer.alloc(4);
    header[0] = 0x81;
    header[1] = 126;
    header.writeUInt16BE(length, 2);
    return Buffer.concat([header, payload]);
  }

  const header = Buffer.alloc(10);
  header[0] = 0x81;
  header[1] = 127;
  header.writeBigUInt64BE(BigInt(length), 2);
  return Buffer.concat([header, payload]);
}

function decodeWsFrames(buffer) {
  const messages = [];
  let offset = 0;

  while (offset + 2 <= buffer.length) {
    const byte1 = buffer[offset];
    const byte2 = buffer[offset + 1];
    const opcode = byte1 & 0x0f;
    const masked = Boolean(byte2 & 0x80);
    let length = byte2 & 0x7f;
    let headerLength = 2;

    if (length === 126) {
      if (offset + 4 > buffer.length) break;
      length = buffer.readUInt16BE(offset + 2);
      headerLength = 4;
    } else if (length === 127) {
      if (offset + 10 > buffer.length) break;
      length = Number(buffer.readBigUInt64BE(offset + 2));
      headerLength = 10;
    }

    const maskLength = masked ? 4 : 0;
    const frameEnd = offset + headerLength + maskLength + length;
    if (frameEnd > buffer.length) break;

    if (opcode === 0x8) {
      messages.push({ close: true });
    } else if (opcode === 0x1) {
      const payloadStart = offset + headerLength + maskLength;
      const payload = Buffer.from(buffer.subarray(payloadStart, frameEnd));
      if (masked) {
        const mask = buffer.subarray(offset + headerLength, offset + headerLength + 4);
        for (let i = 0; i < payload.length; i += 1) {
          payload[i] ^= mask[i % 4];
        }
      }
      messages.push({ text: payload.toString("utf8") });
    }

    offset = frameEnd;
  }

  return messages;
}

const server = http.createServer(async (request, response) => {
  if (request.method === "OPTIONS") {
    sendJson(response, 200, { ok: true });
    return;
  }

  const url = new URL(request.url, `http://${request.headers.host}`);

  if (request.method === "GET" && url.pathname === "/api/health") {
    sendJson(response, 200, {
      ok: true,
      service: "chaos-cat-bridge",
      clients: clients.size,
      events: events.length
    });
    return;
  }

  if (request.method === "GET" && url.pathname === "/api/events") {
    const limit = Math.max(1, Math.min(250, Number(url.searchParams.get("limit") || 50)));
    sendJson(response, 200, { events: events.slice(-limit) });
    return;
  }

  if (request.method === "POST" && url.pathname === "/api/events") {
    try {
      const body = await readBody(request);
      const event = addEvent(JSON.parse(body || "{}"));
      sendJson(response, 200, { ok: true, event });
    } catch (error) {
      sendJson(response, 400, { ok: false, error: error.message });
    }
    return;
  }

  await serveStatic(request, response);
});

server.on("upgrade", (request, socket) => {
  if (request.url !== "/ws") {
    socket.destroy();
    return;
  }

  const key = request.headers["sec-websocket-key"];
  const accept = crypto
    .createHash("sha1")
    .update(`${key}258EAFA5-E914-47DA-95CA-C5AB0DC85B11`)
    .digest("base64");

  socket.write([
    "HTTP/1.1 101 Switching Protocols",
    "Upgrade: websocket",
    "Connection: Upgrade",
    `Sec-WebSocket-Accept: ${accept}`,
    "",
    ""
  ].join("\r\n"));

  clients.add(socket);
  socket.write(encodeWsFrame(JSON.stringify({
    type: "bridge.connected",
    source: "bridge",
    payload: { clients: clients.size },
    createdAt: new Date().toISOString()
  })));

  socket.on("data", (buffer) => {
    for (const frame of decodeWsFrames(buffer)) {
      if (frame.close) {
        clients.delete(socket);
        socket.end();
        return;
      }

      if (frame.text) {
        try {
          addEvent(JSON.parse(frame.text));
        } catch {
          addEvent({ type: "bridge.invalidMessage", source: "bridge", payload: { text: frame.text } });
        }
      }
    }
  });

  socket.on("close", () => clients.delete(socket));
  socket.on("error", () => clients.delete(socket));
});

server.on("error", (error) => {
  console.error(`Chaos Cat bridge failed to start on ${host}:${port}`);
  console.error(error);
  process.exitCode = 1;
});

server.listen(port, host, () => {
  console.log(`Chaos Cat bridge running at http://localhost:${port}`);
});
