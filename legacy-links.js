// Preserve bookmarks into the former homepage essay; homepage anchors stay here.
(() => {
  const oldEssayAnchors = new Set(['finding', 'sending', 'delivery-log', 'pocket']);
  const fragment = location.hash.slice(1);
  if (oldEssayAnchors.has(fragment)) {
    const page = document.documentElement.lang === 'en' ? 'handoff.en.html' : 'handoff.html';
    location.replace(new URL(page + location.hash, location.href).href);
  }
})();
