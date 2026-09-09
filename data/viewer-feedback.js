/* Local press feedback: acknowledges pointer input without waiting for replay
 * or network work. The authoritative play/pause icon still comes from Nim. */
(function () {
  function transportButton(width, height, x, y) {
    let zoom = 1;
    for (let z = 3; z >= 2; --z) {
      if (width >= 320 * z * 1.5 && height >= 128 * z * 1.5) {
        zoom = z; break;
      }
    }
    if (width < 1800 && zoom > 2) zoom = 2;
    const left = Math.floor((width - 320 * zoom) / 2);
    const top = height - 42 * zoom;
    const px = (x - left) / zoom, py = (y - top) / zoom;
    if (py < 4 || py >= 24) return null;
    let lane = -1, stride = 14, origin = 10;
    if (px >= 10 && px < 94) lane = Math.floor((px - 10) / 14);
    else if (px >= 174 && px < 310) {
      lane = Math.floor((px - 174) / 17); stride = 17; origin = 174;
    }
    return lane < 0 ? null : {
      x: left + (origin + lane * stride) * zoom,
      y: top + 4 * zoom, width: stride * zoom, height: 20 * zoom
    };
  }
  if (typeof module !== 'undefined') module.exports = { transportButton };
  if (typeof document === 'undefined') return;
  const canvas = document.getElementById('canvas') || document.getElementById('c');
  if (!canvas) return;
  const flash = document.createElement('div');
  flash.setAttribute('aria-hidden', 'true');
  Object.assign(flash.style, { position: 'fixed', pointerEvents: 'none',
    zIndex: '9999', display: 'none', boxSizing: 'border-box',
    border: '3px solid #7c491e', background: '#ffe6a050',
    boxShadow: '3px 3px 0 #b17d3d', imageRendering: 'pixelated' });
  document.body.appendChild(flash);
  let animation;
  canvas.addEventListener('pointerdown', function (event) {
    if (event.button !== 0) return;
    const bounds = canvas.getBoundingClientRect();
    const button = transportButton(bounds.width, bounds.height,
      event.clientX - bounds.left, event.clientY - bounds.top);
    if (!button) return;
    if (animation) animation.cancel();
    Object.assign(flash.style, { display: 'block',
      left: bounds.left + button.x + 'px', top: bounds.top + button.y + 'px',
      width: button.width + 'px', height: button.height + 'px' });
    const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    animation = flash.animate(reduced ? [{ opacity: 1 }, { opacity: 0 }] : [
      { transform: 'translate(2px,2px) scale(.9)', opacity: 1 },
      { transform: 'translate(0,0) scale(1.12)', opacity: 1, offset: .4 },
      { transform: 'scale(1)', opacity: 0 }
    ], { duration: 220, easing: 'steps(3,end)' });
    animation.onfinish = function () { flash.style.display = 'none'; };
  }, { capture: true });
})();
