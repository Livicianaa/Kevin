const character = document.getElementById('character');
const hook = document.getElementById('hook');
const bubble = document.getElementById('bubble');

const CHAR_SIZE = 64;
const SPEED = 1.2;

let pos = { x: window.innerWidth / 2, y: window.innerHeight - 120 };
let target = pickNewTarget();
let sleeping = false;

function pickNewTarget() {
  const margin = 60;
  return {
    x: margin + Math.random() * (window.innerWidth - margin * 2 - CHAR_SIZE),
    y: window.innerHeight - 120 - Math.random() * 200,
  };
}

function tick() {
  if (!sleeping) {
    const dx = target.x - pos.x;
    const dy = target.y - pos.y;
    const dist = Math.hypot(dx, dy);

    if (dist < 4) {
      target = pickNewTarget();
    } else {
      pos.x += (dx / dist) * SPEED;
      pos.y += (dy / dist) * SPEED;
    }

    character.style.left = `${pos.x}px`;
    character.style.top = `${pos.y}px`;
  }

  requestAnimationFrame(tick);
}

// idle icin rastgele bekleme molalari
setInterval(() => {
  if (sleeping) return;
  if (Math.random() < 0.3) {
    const wasTarget = target;
    target = pos;
    setTimeout(() => {
      target = wasTarget !== pos ? wasTarget : pickNewTarget();
    }, 1500 + Math.random() * 2000);
  }
}, 4000);

function setInteractive(el, interactive) {
  el.addEventListener('mouseenter', () => window.kevinAPI.setIgnoreMouseEvents(false));
  el.addEventListener('mouseleave', () => window.kevinAPI.setIgnoreMouseEvents(true, { forward: true }));
}

setInteractive(character);
setInteractive(hook);

function showBubble(text, x, y) {
  bubble.textContent = text;
  bubble.style.left = `${x}px`;
  bubble.style.top = `${Math.max(0, y - 60)}px`;
  bubble.classList.remove('hidden');
  clearTimeout(showBubble._t);
  showBubble._t = setTimeout(() => bubble.classList.add('hidden'), 3000);
}

character.addEventListener('click', () => {
  showBubble('Naber? (sohbet sistemi bir sonraki fazda gelecek)', pos.x, pos.y);
});

hook.addEventListener('click', () => {
  sleeping = false;
  showBubble('Kevin cagrildi!', pos.x, pos.y);
});

requestAnimationFrame(tick);
