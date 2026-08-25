(() => {
  const start = Date.now();
  const elapsed = () => (Date.now() - start) / 1000;

  // The same format as `format_duration` of the server. Both must agree,
  // because the script continues the value that the server rendered.
  const formatDuration = (total) => {
    const s = Math.max(0, Math.floor(total));
    const days = Math.floor(s / 86_400);
    const hours = Math.floor((s % 86_400) / 3600);
    const minutes = Math.floor((s % 3600) / 60);
    const seconds = s % 60;

    const parts = [];
    if (days > 0) parts.push(`${days}d`);
    if (hours > 0 || days > 0) parts.push(`${hours}h`);
    if (minutes > 0 || hours > 0) parts.push(`${minutes}m`);
    if (days === 0 && hours === 0) parts.push(`${seconds}s`);

    return parts.join(' ');
  };

  // Every duration of the page that grows, with the value that the server
  // measured. An age carries a suffix ("ago"), an uptime carries none. The
  // header holds one too, with a value of 0.
  const ages = [...document.querySelectorAll('[data-age]')]
    .map((el) => ({
      el,
      base: Number(el.dataset.age),
      suffix: el.dataset.ageSuffix ? ` ${el.dataset.ageSuffix}` : '',
    }))
    .filter(({ base }) => Number.isFinite(base));

  const tick = () => {
    const seconds = elapsed();

    ages.forEach(({ el, base, suffix }) => {
      const next = `${formatDuration(base + seconds)}${suffix}`;
      if (el.textContent !== next) el.textContent = next;
    });
  };

  tick();
  setInterval(tick, 1000);
})();
