const root = document.documentElement;
let locale = root.lang === 'zh-CN' ? 'zh-Hans' : 'en';
let appearance = 'light';
function render() {
  root.dataset.appearance = appearance;
  document.querySelectorAll('[data-scenario]').forEach(link => {
    const path = `./assets/${link.dataset.scenario}-${locale}-${appearance}.png`;
    link.href = path;
    link.querySelector('img').src = path;
  });
  document.querySelectorAll('[data-locale]').forEach(button => button.setAttribute('aria-pressed', String(button.dataset.locale === locale)));
  document.querySelectorAll('[data-theme]').forEach(button => button.setAttribute('aria-pressed', String(button.dataset.theme === appearance)));
  document.getElementById('report').href = `./assets/report-${locale}-${appearance}.json`;
  const count = root.getAttribute('data-checks-' + locale + '-' + appearance);
  document.getElementById('view-status').textContent = root.lang === 'zh-CN'
    ? `${locale === 'en' ? '英文' : '中文'} · ${appearance === 'light' ? '浅色' : '深色'} · ${count} / ${count} 项检查通过`
    : `${locale === 'en' ? 'English' : 'Chinese'} · ${appearance} · ${count} / ${count} checks passed`;
}
document.querySelectorAll('[data-locale]').forEach(button => button.addEventListener('click', () => { locale = button.dataset.locale; render(); }));
document.querySelectorAll('[data-theme]').forEach(button => button.addEventListener('click', () => { appearance = button.dataset.theme; render(); }));
render();
