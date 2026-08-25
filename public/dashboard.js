(() => {
  // The one value of the page that grows while the page stands: how old the
  // whole page is. Every other value keeps the moment of the request, so it
  // must not count up, or the page would disagree with itself.
  const element = document.querySelector('[data-page-age]');
  if (!element) return;

  const start = Date.now();

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

  // The page reloads every 30 seconds, so this normally counts to 30. It runs
  // longer when the tab sleeps in the background, or when the server is slow.
  const tick = () => {
    const next = formatDuration((Date.now() - start) / 1000);
    if (element.textContent !== next) element.textContent = next;
  };

  setInterval(tick, 1000);
})();
