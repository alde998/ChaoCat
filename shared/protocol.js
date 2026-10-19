export const BRIDGE_PORT = 44777;
export const BRIDGE_ORIGIN = `http://localhost:${BRIDGE_PORT}`;
export const BRIDGE_WS = `ws://localhost:${BRIDGE_PORT}/ws`;

export const PetState = Object.freeze({
  Calm: "calm",
  PoopChaos: "poopChaos",
  BoxDive: "boxDive",
  BugChase: "bugChase"
});

export const EventType = Object.freeze({
  EditorCursorMoved: "editor.cursorMoved",
  EditorTextChanged: "editor.textChanged",
  EditorSelectionChanged: "editor.selectionChanged",
  PetStateChanged: "pet.stateChanged",
  PetActionRequested: "pet.actionRequested",
  CleanupRequested: "cleanup.requested",
  ClientHello: "client.hello"
});

export function makeEvent(type, payload = {}, source = "unknown") {
  return {
    id: `${Date.now()}-${Math.random().toString(16).slice(2)}`,
    type,
    source,
    payload,
    createdAt: new Date().toISOString()
  };
}

export async function postEvent(event, origin = BRIDGE_ORIGIN) {
  const response = await fetch(`${origin}/api/events`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(event)
  });

  if (!response.ok) {
    throw new Error(`Bridge rejected event: ${response.status}`);
  }

  return response.json();
}

export function connectBridge({ onEvent, onOpen, onClose, onError } = {}) {
  const socket = new WebSocket(BRIDGE_WS);

  socket.addEventListener("open", () => {
    onOpen?.(socket);
    socket.send(JSON.stringify(makeEvent(EventType.ClientHello, { role: "pet-web" }, "pet-web")));
  });

  socket.addEventListener("message", (message) => {
    try {
      onEvent?.(JSON.parse(message.data));
    } catch (error) {
      onError?.(error);
    }
  });

  socket.addEventListener("close", () => onClose?.());
  socket.addEventListener("error", (error) => onError?.(error));

  return socket;
}
