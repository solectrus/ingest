(() => {
  const el = document.querySelector('.brand__updated');
  if (!el) return;

  const start = Date.now();
  let lastText = '';

  const format = (s) => {
    if (s < 5) return 'just now';
    if (s < 60) return `${s}s ago`;
    const m = Math.floor(s / 60);
    if (m < 60) return `${m}m ago`;
    return `${Math.floor(m / 60)}h ago`;
  };

  const tick = () => {
    const s = Math.floor((Date.now() - start) / 1000);
    const next = `Updated ${format(s)}`;
    if (next !== lastText) {
      el.textContent = next;
      lastText = next;
    }
  };

  tick();
  setInterval(tick, 1000);
})();
