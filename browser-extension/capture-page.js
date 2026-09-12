(() => {
  const MAX_BODY_CHARS = 100_000;
  const clean = (value) => (value ?? "").replace(/\s+/g, " ").trim();
  const text = (selector, root = document) => clean(root.querySelector(selector)?.textContent);
  const attr = (selector, name, root = document) => root.querySelector(selector)?.getAttribute(name)?.trim() || null;

  function chooseReadableRoot() {
    const direct = document.querySelector("article, main, [role='main']");
    if (direct && clean(direct.textContent).length >= 300) return direct;

    let winner = document.body || document.documentElement;
    let bestScore = 0;
    const candidates = document.querySelectorAll("section, div");
    for (const candidate of candidates) {
      const paragraphs = candidate.querySelectorAll(":scope > p, :scope > section > p");
      if (paragraphs.length < 2) continue;
      const contentLength = [...paragraphs].reduce((sum, paragraph) => sum + clean(paragraph.textContent).length, 0);
      const linkLength = [...candidate.querySelectorAll("a")].reduce((sum, link) => sum + clean(link.textContent).length, 0);
      const score = contentLength - Math.min(contentLength, linkLength) * 0.6;
      if (score > bestScore) {
        winner = candidate;
        bestScore = score;
      }
    }
    return winner;
  }

  function extractReadableArticle() {
    try {
      if (typeof Readability === "function") {
        const parsed = new Readability(document.cloneNode(true), { charThreshold: 100 }).parse();
        if (parsed?.content) {
          const parsedDocument = new DOMParser().parseFromString(parsed.content, "text/html");
          return { root: parsedDocument.body, metadata: parsed, method: "mozilla-readability" };
        }
      }
    } catch {
      // Keep capture available on unusual pages and expose the fallback in
      // provenance rather than pretending Readability succeeded.
    }
    return { root: chooseReadableRoot(), metadata: null, method: "dom-fallback" };
  }

  function markdownFrom(root) {
    const copy = root.cloneNode(true);
    copy.querySelectorAll([
      "script", "style", "noscript", "svg", "canvas", "iframe", "form",
      "nav", "footer", "aside", "[hidden]", "[aria-hidden='true']",
      "[role='navigation']", "[role='banner']", "[role='contentinfo']",
      ".sr-only", ".visually-hidden"
    ].join(",")).forEach((node) => node.remove());

    const blocks = [];
    const push = (value) => {
      const normalized = value.replace(/[ \t]+\n/g, "\n").replace(/\n{3,}/g, "\n\n").trim();
      if (normalized && blocks.at(-1) !== normalized) blocks.push(normalized);
    };
    for (const node of copy.querySelectorAll("h1,h2,h3,h4,h5,h6,p,pre,blockquote,li,table")) {
      if (node.closest("table") && node.tagName !== "TABLE") continue;
      const value = clean(node.textContent);
      if (!value) continue;
      if (/^H[1-6]$/.test(node.tagName)) push(`${"#".repeat(Number(node.tagName[1]))} ${value}`);
      else if (node.tagName === "PRE") push(`\`\`\`\n${node.textContent.trim()}\n\`\`\``);
      else if (node.tagName === "BLOCKQUOTE") push(value.split("\n").map((line) => `> ${line}`).join("\n"));
      else if (node.tagName === "LI") push(`- ${value}`);
      else if (node.tagName === "TABLE") {
        const rows = [...node.querySelectorAll("tr")].map((row) =>
          [...row.querySelectorAll("th,td")].map((cell) => clean(cell.textContent)).filter(Boolean).join(" | ")
        ).filter(Boolean);
        push(rows.join("\n"));
      } else push(value);
    }
    return blocks.length ? blocks.join("\n\n") : clean(copy.textContent);
  }

  function githubData(url) {
    if (url.hostname !== "github.com") return null;
    const parts = url.pathname.split("/").filter(Boolean);
    if (parts.length < 2) return { kind: "github", pageType: "home" };
    const [owner, repository, section, identifier] = parts;
    const common = { kind: "github", owner, repository };

    if (section === "pull" && /^\d+$/.test(identifier || "")) {
      const files = [...document.querySelectorAll(".file, [data-file-type]")].slice(0, 250).map((file) => ({
        path: attr("[data-path]", "data-path", file) || text(".file-info a, .Link--primary", file),
        additions: text(".color-fg-success, .diffstat .text-green", file) || null,
        deletions: text(".color-fg-danger, .diffstat .text-red", file) || null
      })).filter((file) => file.path);
      return {
        ...common,
        pageType: "pullRequest",
        number: Number(identifier),
        state: text("[data-testid='header-state'], .State, .gh-header-meta .State") || null,
        author: text(".gh-header-meta .author, [data-testid='issue-metadata-fixed'] a") || null,
        base: attr("[data-hovercard-type='branch'][href*='/tree/']", "title") || null,
        files
      };
    }

    if ((section === "issues" || section === "issue") && /^\d+$/.test(identifier || "")) {
      return {
        ...common,
        pageType: "issue",
        number: Number(identifier),
        state: text("[data-testid='header-state'], .State") || null,
        author: text(".gh-header-meta .author, [data-testid='issue-metadata-fixed'] a") || null,
        labels: [...document.querySelectorAll("[data-testid='issue-labels'] a, .js-issue-labels a")]
          .map((label) => clean(label.textContent)).filter(Boolean),
        assignees: [...document.querySelectorAll("[data-testid='assignees'] a, .discussion-sidebar-item.sidebar-assignee a")]
          .map((assignee) => assignee.getAttribute("aria-label") || clean(assignee.textContent)).filter(Boolean)
      };
    }

    if (section === "blob" || section === "tree") {
      const code = [...document.querySelectorAll(".js-file-line, [data-testid='code-cell']")]
        .map((line) => line.textContent ?? "").join("\n");
      return {
        ...common,
        pageType: section === "blob" ? "code" : "tree",
        ref: parts[3] || null,
        path: parts.slice(4).join("/") || null,
        code: code ? code.slice(0, MAX_BODY_CHARS) : null,
        codeTruncated: code.length > MAX_BODY_CHARS
      };
    }

    return { ...common, pageType: "repository" };
  }

  try {
    const url = new URL(location.href);
    const article = extractReadableArticle();
    const fullBody = markdownFrom(article.root);
    const selection = globalThis.getSelection?.()?.toString() || "";
    const structured = githubData(url);
    const domainHint = structured?.pageType === "pullRequest" ? "github.pr"
      : structured?.pageType === "issue" ? "github.issue"
      : structured?.pageType === "code" ? "github.code"
      : structured ? "github.repo" : "generic";
    return {
      schemaVersion: 1,
      source: "browser",
      app: navigator.userAgentData?.brands?.find((brand) => brand.brand !== "Not_A Brand")?.brand || "Chromium",
      bundle: null,
      pid: null,
      capturedAt: new Date().toISOString(),
      url: url.href,
      domain: url.hostname,
      title: document.title,
      language: document.documentElement.lang || null,
      canonicalURL: attr("link[rel='canonical']", "href"),
      metaDescription: attr("meta[name='description']", "content") || attr("meta[property='og:description']", "content"),
      byline: article.metadata?.byline || null,
      excerpt: article.metadata?.excerpt || null,
      extractionMethod: article.method,
      selectedText: selection.trim() || null,
      extractedBody: fullBody.slice(0, MAX_BODY_CHARS),
      truncated: fullBody.length > MAX_BODY_CHARS,
      private: globalThis.chrome?.extension?.inIncognitoContext ?? null,
      domainHint,
      structured
    };
  } catch (error) {
    return { schemaVersion: 1, captureError: String(error?.message || error) };
  }
})();
