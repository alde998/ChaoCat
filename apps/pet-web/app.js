import { EventType, PetState, connectBridge, makeEvent } from "/shared/protocol.js";

const workspace = document.querySelector("#workspace");
const documentLayer = document.querySelector("#documentLayer");
const virtualTextLayer = document.querySelector("#virtualTextLayer");
const dirtyImageLayer = document.querySelector("#dirtyImageLayer");
const propLayer = document.querySelector("#propLayer");
const catSprite = document.querySelector("#catSprite");
const status = document.querySelector("#status");

let currentState = PetState.Calm;
let socket;
let lastInputPoint = { x: 480, y: 320 };

const sprites = {
  [PetState.Calm]: "/assets/cat-sit.svg",
  poop: "/assets/cat-poop.svg",
  paw: "/assets/cat-paw.svg",
  box: "/assets/cat-box.svg",
  bug: "/assets/cat-run.svg",
  shy: "/assets/cat-shy.svg"
};

function bounds() {
  return workspace.getBoundingClientRect();
}

function randomPoint(padding = 110) {
  const rect = bounds();
  return {
    x: padding + Math.random() * Math.max(1, rect.width - padding * 2),
    y: padding + Math.random() * Math.max(1, rect.height - padding * 2)
  };
}

function setStatus(extra = "") {
  status.textContent = `${currentState}${extra ? ` · ${extra}` : ""}`;
}

function moveCat(point, sprite = sprites[PetState.Calm]) {
  catSprite.src = sprite;
  catSprite.style.left = `${Math.max(24, point.x - 58)}px`;
  catSprite.style.top = `${Math.max(24, point.y - 58)}px`;
}

function addElement(layer, className, html, point, style = {}) {
  const element = document.createElement("div");
  element.className = className;
  element.innerHTML = html;
  element.style.left = `${point.x}px`;
  element.style.top = `${point.y}px`;
  for (const [key, value] of Object.entries(style)) {
    element.style.setProperty(key, value);
  }
  layer.append(element);
  return element;
}

function addImage(layer, className, src, point, style = {}) {
  const image = document.createElement("img");
  image.className = className;
  image.src = src;
  image.alt = "";
  image.style.left = `${point.x}px`;
  image.style.top = `${point.y}px`;
  for (const [key, value] of Object.entries(style)) {
    image.style.setProperty(key, value);
  }
  layer.append(image);
  return image;
}

function clearEffects() {
  virtualTextLayer.replaceChildren();
  dirtyImageLayer.replaceChildren();
  propLayer.replaceChildren();
  catSprite.classList.remove("shake");
  currentState = PetState.Calm;
  moveCat({ x: 160, y: 590 }, sprites[PetState.Calm]);
  setStatus("clean");
}

function poopChaos() {
  currentState = PetState.PoopChaos;
  const target = randomPoint();
  moveCat({ x: target.x - 60, y: target.y + 70 }, sprites.paw);
  setStatus("making trouble");

  for (let i = 0; i < 8; i += 1) {
    const point = { x: target.x + Math.random() * 260 - 130, y: target.y + Math.random() * 140 - 70 };
    addElement(virtualTextLayer, "poop-text", "shit", point, { "--r": `${Math.random() * 34 - 17}deg` });
  }

  for (let i = 0; i < 5; i += 1) {
    const point = { x: target.x + Math.random() * 210 - 105, y: target.y + Math.random() * 120 - 40 };
    addImage(dirtyImageLayer, "poop-img", "/assets/poop.svg", point, { "--s": `${30 + Math.random() * 34}px` });
  }

  setTimeout(() => {
    catSprite.src = sprites.poop;
  }, 360);
}

function scatterPoop() {
  catSprite.src = sprites.shy;
  catSprite.classList.remove("shake");
  void catSprite.offsetWidth;
  catSprite.classList.add("shake");
  setStatus("scattered");

  for (let i = 0; i < 14; i += 1) {
    const point = randomPoint(70);
    addElement(virtualTextLayer, "poop-text", "shit", point, { "--r": `${Math.random() * 70 - 35}deg` });
    if (i % 2 === 0) {
      addElement(dirtyImageLayer, "splat", "", { x: point.x + 18, y: point.y + 14 }, { "--r": `${Math.random() * 60 - 30}deg` });
    }
  }

  setTimeout(() => moveCat(randomPoint(), sprites[PetState.Calm]), 520);
}

function boxDive() {
  currentState = PetState.BoxDive;
  const point = randomPoint();
  addImage(propLayer, "box", "/assets/box.svg", { x: point.x - 18, y: point.y + 20 });
  moveCat({ x: point.x, y: point.y }, sprites.box);
  setStatus("diving into text gap");

  for (const char of ["{", "}", ";", "=", "("]) {
    addElement(virtualTextLayer, "char-kick", char, {
      x: point.x + Math.random() * 190 - 95,
      y: point.y + Math.random() * 100 - 40
    }, {
      "--dy": `${Math.random() * -18}px`,
      "--r": `${Math.random() * 28 - 14}deg`
    });
  }
}

function bugChase(point = lastInputPoint) {
  currentState = PetState.BugChase;
  setStatus("chasing bug");
  const bugPoint = { x: point.x + 36, y: point.y - 24 };
  addImage(propLayer, "bug", "/assets/bug.svg", bugPoint);
  moveCat({ x: Math.max(80, point.x - 90), y: Math.max(80, point.y + 70) }, sprites.bug);

  for (let i = 0; i < 3; i += 1) {
    addElement(dirtyImageLayer, "paw", "🐾", {
      x: point.x - 70 + i * 34,
      y: point.y + 20 + Math.random() * 40
    }, {
      "--r": `${Math.random() * 42 - 21}deg`
    });
  }
}

function calm() {
  currentState = PetState.Calm;
  moveCat({ x: 160, y: 590 }, sprites[PetState.Calm]);
  setStatus("watching");
}

function handleAction(action) {
  if (action === "clear") clearEffects();
  if (action === "calm") calm();
  if (action === "poopChaos") poopChaos();
  if (action === "boxDive") boxDive();
  if (action === "bugChase") bugChase();
  if (action === "scatter") scatterPoop();
}

document.querySelectorAll("[data-action]").forEach((button) => {
  button.addEventListener("click", () => handleAction(button.dataset.action));
});

documentLayer.addEventListener("input", () => {
  const rect = bounds();
  lastInputPoint = {
    x: 240 + Math.random() * (rect.width - 440),
    y: 180 + Math.random() * (rect.height - 320)
  };
  if (currentState !== PetState.PoopChaos) bugChase(lastInputPoint);
});

catSprite.addEventListener("click", scatterPoop);

function handleBridgeEvent(event) {
  if (!event?.type) return;
  if (event.type === EventType.EditorTextChanged) bugChase(event.payload?.point || lastInputPoint);
  if (event.type === EventType.PetActionRequested) handleAction(event.payload?.action);
  if (event.type === EventType.CleanupRequested) clearEffects();
}

try {
  socket = connectBridge({
    onOpen: () => setStatus("bridge connected"),
    onClose: () => setStatus("bridge disconnected"),
    onError: () => setStatus("bridge unavailable"),
    onEvent: handleBridgeEvent
  });
} catch {
  setStatus("bridge unavailable");
}

calm();
