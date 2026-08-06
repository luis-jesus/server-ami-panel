const state = {
  currentView: "home",
  statusPayload: null,
  homeBriefingPayload: null,
  briefingModalKind: "headlines",
  servicesPayload: null,
  serviceActionPending: null,
  serviceActionResult: null,
  serviceActionHistory: [],
  serviceLogPending: null,
  serviceLogResult: null,
  selectedServiceLogId: "",
  reportModalKind: "inventory",
  selectedReport: null,
  selectedPreview: null,
  reportViewerDismissed: false,
  reportMenuKind: "inventory",
  inventoryReports: [],
  updateReports: [],
  selectedDetail: null,
  comparisonDetail: null,
  pendingApplyRequest: null,
  jobLaunchPending: {
    inventory: null,
    update: null,
  },
  pendingServiceConfirmation: null,
  compareFileSelection: {
    inventory: "",
    update: "",
  },
  compareSelection: {
    inventory: "",
    update: "",
  },
};

const pollTimers = {
  home: null,
  dashboard: null,
  services: null,
  briefing: null,
};

const particleState = {
  frame: 0,
  particles: [],
  canvas: null,
  context: null,
  width: 0,
  height: 0,
};

const VALID_VIEWS = new Set(["home", "inventory", "services"]);
const VALID_REPORT_MENUS = new Set(["inventory", "update"]);

function statusClass(value) {
  if (!value) {
    return "";
  }
  return `status-${String(value).toLowerCase().replace(/[^a-z0-9]+/g, "-")}`;
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
}

function escapeAttribute(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll('"', "&quot;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
}

function searchableText(parts) {
  return parts
    .filter(Boolean)
    .join(" ")
    .toLowerCase();
}

function toNumber(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function shortTimestamp(value) {
  if (!value) {
    return "sin fecha";
  }
  return value.slice(5, 16).replace("T", " ");
}

function compactText(value, limit = 140) {
  const normalized = String(value || "").replace(/\s+/g, " ").trim();
  if (normalized.length <= limit) {
    return normalized;
  }

  const shortened = normalized.slice(0, Math.max(0, limit - 3));
  const safeCut = shortened.includes(" ") ? shortened.slice(0, shortened.lastIndexOf(" ")) : shortened;
  return `${safeCut || shortened}...`;
}

function briefingDateLabel(value) {
  if (!value) {
    return "sin fecha";
  }

  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) {
    return String(value).slice(0, 16);
  }

  return new Intl.DateTimeFormat("es-MX", {
    month: "short",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  }).format(parsed);
}

function briefingTimestamp(value) {
  if (!value) {
    return 0;
  }
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? 0 : parsed.getTime();
}

function filterBriefingEntriesByDays(entries, days) {
  const cutoff = Date.now() - (days * 24 * 60 * 60 * 1000);
  return (entries || []).filter((entry) => briefingTimestamp(entry?.published_at) >= cutoff);
}

function pickNearestBriefingEntries(entries, limit = 3) {
  return [...(entries || [])]
    .sort((left, right) => briefingTimestamp(right?.published_at) - briefingTimestamp(left?.published_at))
    .slice(0, limit);
}

function selectHomeBriefingEntries(entries, visibleDays, fallbackLimit = 3) {
  const recentEntries = filterBriefingEntriesByDays(entries, visibleDays);
  if (recentEntries.length) {
    return { entries: recentEntries, fallback: false };
  }
  return {
    entries: pickNearestBriefingEntries(entries, fallbackLimit),
    fallback: true,
  };
}

function renderSecurityBriefingItems(entries) {
  return entries.map((entry) => `
    <article class="briefing-item">
      <div class="briefing-headline-meta">
        <p class="briefing-kicker">${escapeHtml(entry.source || "Fuente")}</p>
        <span class="briefing-time">${escapeHtml(briefingDateLabel(entry.published_at))}</span>
      </div>
      <h3>${escapeHtml(entry.title || "Titular sin nombre")}</h3>
      <p>${escapeHtml(compactText(entry.summary || "Sin resumen disponible.", 150))}</p>
      <div class="briefing-tags">
        <span class="pill">${escapeHtml(briefingCategoryLabel(entry.category))}</span>
      </div>
      <a class="ghost-link" href="${escapeAttribute(entry.link || entry.source_url || "#")}" target="_blank" rel="noreferrer noopener">Abrir sitio</a>
    </article>
  `).join("");
}

function renderVulnerabilityBriefingItems(entries) {
  return entries.map((entry) => `
    <article class="briefing-item vulnerability-item">
      <div class="briefing-headline-meta">
        <p class="briefing-kicker">${escapeHtml(entry.cve_id || "CVE")}</p>
        <span class="briefing-time">${escapeHtml(briefingDateLabel(entry.published_at))}</span>
      </div>
      <h3>${escapeHtml(entry.title || "Vulnerabilidad sin titulo")}</h3>
      <p>${escapeHtml(compactText(entry.summary || "Sin descripcion disponible.", 150))}</p>
      <div class="briefing-tags">
        <span class="pill">${escapeHtml(entry.vendor || "Proveedor no identificado")}</span>
        <span class="pill">${escapeHtml(entry.product || "Producto no identificado")}</span>
        <span class="pill ${statusClass(entry.ransomware_use)}">Ransomware: ${escapeHtml(entry.ransomware_use || "Unknown")}</span>
      </div>
      <p class="briefing-footnote">${escapeHtml(compactText(entry.required_action || "Accion recomendada no disponible.", 170))}</p>
      <a class="ghost-link" href="${escapeAttribute(entry.link || "#")}" target="_blank" rel="noreferrer noopener">CVE</a>
    </article>
  `).join("");
}

function signedNumber(value, digits = 2) {
  const number = toNumber(value);
  const sign = number > 0 ? "+" : "";
  return `${sign}${number.toFixed(digits)}`;
}

function briefingCategoryLabel(category) {
  switch (category) {
    case "official":
      return "Fuente oficial";
    case "blog":
      return "Blog";
    case "analysis":
      return "Analisis";
    case "news":
      return "Sitio web";
    default:
      return "Actualizacion";
  }
}

function downloadText(filename, content, mimeType = "text/plain;charset=utf-8") {
  const blob = new Blob([content], { type: mimeType });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  link.remove();
  window.setTimeout(() => URL.revokeObjectURL(url), 0);
}

function csvEscape(value) {
  const text = String(value ?? "");
  if (/[",\n]/.test(text)) {
    return `"${text.replaceAll('"', '""')}"`;
  }
  return text;
}

function getReportsByKind(kind) {
  return kind === "update" ? state.updateReports : state.inventoryReports;
}

function normalizeReportMenuKind(kind) {
  return VALID_REPORT_MENUS.has(kind) ? kind : "inventory";
}

function loadPreferredReportMenu() {
  try {
    return normalizeReportMenuKind(window.localStorage.getItem("serveram1.reportMenu") || "inventory");
  } catch {
    return "inventory";
  }
}

function savePreferredReportMenu(kind) {
  try {
    window.localStorage.setItem("serveram1.reportMenu", normalizeReportMenuKind(kind));
  } catch {
    return;
  }
}

function loadPreferredReportId(kind) {
  const normalizedKind = normalizeReportMenuKind(kind);
  try {
    return window.localStorage.getItem(`serveram1.reportId.${normalizedKind}`) || "";
  } catch {
    return "";
  }
}

function savePreferredReportId(kind, reportId) {
  const normalizedKind = normalizeReportMenuKind(kind);
  try {
    window.localStorage.setItem(`serveram1.reportId.${normalizedKind}`, reportId || "");
  } catch {
    return;
  }
}

function renderReportMenuCounts() {
  const inventoryCount = document.getElementById("inventory-menu-count");
  const updateCount = document.getElementById("update-menu-count");
  if (inventoryCount) {
    inventoryCount.textContent = String(state.inventoryReports.length || 0);
  }
  if (updateCount) {
    updateCount.textContent = String(state.updateReports.length || 0);
  }
}

function renderReportSelectorSummary() {
  const root = document.getElementById("report-selector-summary");
  const inventory = state.inventoryReports[0] || null;
  const update = state.updateReports[0] || null;

  const cards = [
    inventory
      ? {
        label: "Ultimo inventario",
        value: inventory.id,
        note: `${inventory.manifest?.os_name || "Host desconocido"} · warnings ${inventory.warnings_count || 0}`,
      }
      : {
        label: "Ultimo inventario",
        value: "Sin datos",
        note: "Todavia no hay snapshots disponibles.",
      },
    update
      ? {
        label: "Ultima actualizacion",
        value: update.id,
        note: `${update.summary?.mode || update.manifest?.mode || "modo desconocido"} · trust ${update.trust?.status || "unknown"}`,
      }
      : {
        label: "Ultima actualizacion",
        value: "Sin datos",
        note: "Todavia no hay reportes de paquetes.",
      },
  ];

  root.innerHTML = cards.map((card) => `
    <article class="summary-tile selector-summary-tile">
      <p>${escapeHtml(card.label)}</p>
      <strong>${escapeHtml(card.value)}</strong>
      <span>${escapeHtml(card.note)}</span>
    </article>
  `).join("");
}

function openReportModal(kind) {
  state.reportModalKind = normalizeReportMenuKind(kind);
  const modal = document.getElementById("report-modal");
  const title = document.getElementById("report-modal-title");
  const subtitle = document.getElementById("report-modal-subtitle");
  title.textContent = state.reportModalKind === "update" ? "Seleccionar actualizacion" : "Seleccionar inventario";
  subtitle.textContent = state.reportModalKind === "update"
    ? "Se muestran todas las actualizaciones filtradas para abrir una en el visor."
    : "Se muestran todos los inventarios filtrados para abrir uno en el visor.";
  modal.classList.remove("hidden-panel");
  modal.setAttribute("aria-hidden", "false");
  renderReportModal();
}

function closeReportModal() {
  const modal = document.getElementById("report-modal");
  modal.classList.add("hidden-panel");
  modal.setAttribute("aria-hidden", "true");
}

function renderReportModal() {
  const kind = state.reportModalKind;
  const reports = getReportsByKind(kind);
  renderReportList("report-modal-list", reports, kind, { limit: null, footerId: "" });
}

function closeSelectedReport(message = "Selecciona una ejecucion para inspeccionar su salida.") {
  state.reportViewerDismissed = true;
  state.selectedReport = null;
  state.selectedDetail = null;
  state.comparisonDetail = null;
  state.selectedPreview = null;
  resetDetailView(message);
  renderReportList("inventory-reports", state.inventoryReports, "inventory", { limit: 4, footerId: "inventory-reports-more" });
  renderReportList("update-reports", state.updateReports, "update", { limit: 4, footerId: "update-reports-more" });
  if (!document.getElementById("report-modal").classList.contains("hidden-panel")) {
    renderReportModal();
  }
}

function setReportMenuKind(kind, options = {}) {
  const { persist = true } = options;
  state.reportMenuKind = normalizeReportMenuKind(kind);
  if (persist) {
    savePreferredReportMenu(state.reportMenuKind);
  }
  document.querySelectorAll("[data-report-menu]").forEach((node) => {
    const isActive = node.dataset.reportMenu === state.reportMenuKind;
    node.classList.toggle("active-switch", isActive);
  });
  document.querySelectorAll("[data-report-panel]").forEach((node) => {
    const isActive = node.dataset.reportPanel === state.reportMenuKind;
    node.classList.toggle("hidden-panel", !isActive);
  });
}

function defaultCompareId(kind, reportId) {
  return getReportsByKind(kind).find((report) => report.id !== reportId)?.id || "";
}

function sharedPreviewableFiles(currentDetail, compareDetail) {
  if (!currentDetail || !compareDetail) {
    return [];
  }

  const currentPaths = new Set((currentDetail.files || []).filter((file) => file.previewable).map((file) => file.path));
  return (compareDetail.files || [])
    .filter((file) => file.previewable && currentPaths.has(file.path))
    .map((file) => file.path)
    .sort();
}

function defaultCompareFilePath(currentDetail, compareDetail) {
  const candidates = sharedPreviewableFiles(currentDetail, compareDetail);
  if (!candidates.length) {
    return "";
  }
  if (candidates.includes("manifest.txt")) {
    return "manifest.txt";
  }
  return candidates[0];
}

function normalizeView(viewName) {
  return VALID_VIEWS.has(viewName) ? viewName : "home";
}

function loadPreferredView() {
  try {
    return normalizeView(window.localStorage.getItem("serveram1.view") || "home");
  } catch {
    return "home";
  }
}

function savePreferredView(viewName) {
  try {
    window.localStorage.setItem("serveram1.view", viewName);
  } catch {
    return;
  }
}

function normalizeServiceActionHistory(entries) {
  if (!Array.isArray(entries)) {
    return [];
  }

  return entries
    .filter((entry) => entry && typeof entry === "object")
    .map((entry) => ({
      service_id: String(entry.service_id || "service"),
      action: String(entry.action || "accion"),
      status: String(entry.status || "unknown"),
      stdout: String(entry.stdout || ""),
      stderr: String(entry.stderr || ""),
      command: Array.isArray(entry.command) ? entry.command.map((item) => String(item)) : [],
      recorded_at: String(entry.recorded_at || ""),
    }))
    .slice(0, 6);
}

function loadServiceActionHistory() {
  try {
    const rawValue = window.localStorage.getItem("serveram1.serviceActionHistory");
    if (!rawValue) {
      return [];
    }
    return normalizeServiceActionHistory(JSON.parse(rawValue));
  } catch {
    return [];
  }
}

function saveServiceActionHistory(entries) {
  try {
    window.localStorage.setItem(
      "serveram1.serviceActionHistory",
      JSON.stringify(normalizeServiceActionHistory(entries)),
    );
  } catch {
    return;
  }
}

function sparklineSvg(values, color) {
  const width = 320;
  const height = 116;
  const padding = 12;
  const maxValue = Math.max(...values, 1);
  const stepX = values.length > 1 ? (width - padding * 2) / (values.length - 1) : 0;
  const points = values.map((value, index) => {
    const x = padding + stepX * index;
    const y = height - padding - ((height - padding * 2) * value / maxValue);
    return `${x},${y}`;
  }).join(" ");
  const area = `${padding},${height - padding} ${points} ${width - padding},${height - padding}`;

  return `
    <svg viewBox="0 0 ${width} ${height}" preserveAspectRatio="none" aria-hidden="true">
      <line x1="${padding}" y1="${height - padding}" x2="${width - padding}" y2="${height - padding}" stroke="rgba(255,255,255,0.1)" stroke-width="1" />
      <polygon points="${area}" fill="${color}22"></polygon>
      <polyline points="${points}" fill="none" stroke="${color}" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"></polyline>
    </svg>
  `;
}

function trendCard(config) {
  if (!config.values.length) {
    return `
      <article class="card trend-card">
        <div>
          <h3>${escapeHtml(config.title)}</h3>
          <p>${escapeHtml(config.subtitle)}</p>
        </div>
        <div class="trend-empty">${escapeHtml(config.emptyMessage || "Sin datos disponibles todavia.")}</div>
      </article>
    `;
  }

  return `
    <article class="card trend-card">
      <div>
        <h3>${escapeHtml(config.title)}</h3>
        <p>${escapeHtml(config.subtitle)}</p>
      </div>
      <div class="trend-stat">
        <div>
          <p>${escapeHtml(config.statLabel)}</p>
          <strong>${escapeHtml(config.statValue)}</strong>
        </div>
        <div class="trend-legend">${config.legend.join("")}</div>
      </div>
      <div class="trend-chart">
        ${sparklineSvg(config.values, config.color)}
        <div class="trend-axis">
          <span>${escapeHtml(config.startLabel)}</span>
          <span>${escapeHtml(config.endLabel)}</span>
        </div>
      </div>
    </article>
  `;
}

async function fetchJson(url, options = {}) {
  const response = await fetch(url, {
    headers: { "Content-Type": "application/json" },
    ...options,
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(errorText || `HTTP ${response.status}`);
  }

  return response.json();
}

function buildSummaryTiles(entries) {
  return `
    <div class="detail-summary">
      ${entries.map((entry) => `
        <article class="summary-tile">
          <p>${escapeHtml(entry.label)}</p>
          <strong>${escapeHtml(entry.value)}</strong>
        </article>
      `).join("")}
    </div>
  `;
}

function renderHomeSystemSummary(systemInfo) {
  const root = document.getElementById("home-system-summary");
  const cards = [
    { label: "Sistema operativo", value: systemInfo?.os_name || "desconocido" },
    { label: "Hostname", value: systemInfo?.hostname || "desconocido" },
    { label: "IP principal", value: systemInfo?.primary_ip || "desconocida" },
    { label: "Kernel", value: systemInfo?.kernel || "desconocido" },
    { label: "Init", value: systemInfo?.init_system || "desconocido" },
    { label: "Firewall", value: systemInfo?.firewall_backend || "none" },
  ];

  root.innerHTML = cards.map((entry) => `
    <article class="summary-tile">
      <p>${escapeHtml(entry.label)}</p>
      <strong>${escapeHtml(entry.value)}</strong>
    </article>
  `).join("");
}

function renderHomeBriefingMeta(payload) {
  const securityMeta = document.getElementById("home-security-meta");
  const vulnerabilityMeta = document.getElementById("home-vulnerability-meta");
  const security = payload?.security || {};
  const headlineSources = security.headline_sources || [];
  const activeSources = headlineSources.filter((entry) => entry.status === "ok");
  const nonOfficialSources = activeSources.filter((entry) => entry.label !== "CISA");
  const historyDays = security.history_window_days || 7;
  const visibleDays = security.visible_window_days || 2;
  const headlineHistory = security.headlines_7d || security.headlines || [];
  const vulnerabilityHistory = security.vulnerabilities_7d || security.vulnerabilities || [];

  securityMeta.innerHTML = `
    <span class="pill">Blogs y sitios</span>
    <span class="pill">${escapeHtml(headlineHistory.length)} titulares</span>
    <span class="pill">${escapeHtml(nonOfficialSources.length || activeSources.length || headlineSources.length || 0)} fuentes</span>
    <span class="pill">${escapeHtml(`2/${historyDays} dias`)}</span>
  `;

  vulnerabilityMeta.innerHTML = `
    <span class="pill">KEV ${escapeHtml(security.catalog_version || "n/d")}</span>
    <span class="pill">${escapeHtml(vulnerabilityHistory.length || security.catalog_count || 0)} registros</span>
    <span class="pill">${escapeHtml(`${visibleDays}/${historyDays} dias`)}</span>
  `;
}

function renderHomeSecurityFeed(entries, visibleDays = 2) {
  const root = document.getElementById("home-security-feed");
  if (!entries?.length) {
    root.innerHTML = `
      <article class="briefing-item is-empty">
        <p class="briefing-kicker">Fuente no disponible</p>
        <h3>No se pudieron cargar noticias desde blogs y sitios de seguridad.</h3>
        <p>El endpoint local mantendra esta seccion en modo degradado hasta recuperar conectividad.</p>
      </article>
    `;
    return;
  }

  const selection = selectHomeBriefingEntries(entries, visibleDays, 3);
  const prefix = selection.fallback ? `
    <article class="briefing-item is-empty">
      <p class="briefing-kicker">Sin cambios recientes</p>
      <h3>No hubo titulares nuevos en los ultimos ${escapeHtml(visibleDays)} dias.</h3>
      <p>Se muestran las noticias mas cercanas a la fecha dentro del historial disponible.</p>
    </article>
  ` : "";

  root.innerHTML = `${prefix}${renderSecurityBriefingItems(selection.entries)}`;
}

function renderHomeVulnerabilityFeed(entries, visibleDays = 2) {
  const root = document.getElementById("home-vulnerability-feed");
  if (!entries?.length) {
    root.innerHTML = `
      <article class="briefing-item is-empty">
        <p class="briefing-kicker">Catalogo KEV</p>
        <h3>No se encontraron vulnerabilidades recientes.</h3>
        <p>Cuando la fuente este disponible, aqui se mostraran CVE recientes con accion recomendada.</p>
      </article>
    `;
    return;
  }

  const selection = selectHomeBriefingEntries(entries, visibleDays, 3);
  const prefix = selection.fallback ? `
    <article class="briefing-item is-empty">
      <p class="briefing-kicker">Sin cambios recientes</p>
      <h3>No hubo vulnerabilidades nuevas en los ultimos ${escapeHtml(visibleDays)} dias.</h3>
      <p>Se muestran las entradas mas cercanas a la fecha dentro del historial disponible.</p>
    </article>
  ` : "";

  root.innerHTML = `${prefix}${renderVulnerabilityBriefingItems(selection.entries)}`;
}

function renderSharedMarketTicker(entries) {
  const root = document.getElementById("global-market-ticker");
  if (!entries?.length) {
    root.classList.remove("is-animated");
    root.innerHTML = `
      <article class="market-chip is-empty">
        <p>Mercado</p>
        <strong>No disponible</strong>
        <span>Sin datos remotos</span>
      </article>
    `;
    return;
  }

  const repeatedEntries = entries.length > 1 ? entries.concat(entries) : entries;
  root.classList.toggle("is-animated", entries.length > 1);
  root.innerHTML = repeatedEntries.map((entry) => `
    <article class="market-chip trend-${escapeHtml(entry.trend || "flat")}">
      <p>${escapeHtml(entry.label || entry.symbol || "Ticker")}</p>
      <strong>${escapeHtml(entry.value || "0")}</strong>
      <span>${escapeHtml(signedNumber(entry.change_percent, 2))}%</span>
    </article>
  `).join("");
}

function renderHomeBriefing(payload) {
  const security = payload?.security || {};
  const visibleDays = security.visible_window_days || 2;
  renderHomeBriefingMeta(payload || {});
  renderHomeSecurityFeed(security.headlines || [], visibleDays);
  renderHomeVulnerabilityFeed(security.vulnerabilities || [], visibleDays);
  renderSharedMarketTicker(payload?.market?.tickers || []);
  if (!document.getElementById("briefing-modal").classList.contains("hidden-panel")) {
    renderBriefingModal();
  }
}

function openBriefingModal(kind) {
  state.briefingModalKind = kind === "vulnerabilities" ? "vulnerabilities" : "headlines";
  const modal = document.getElementById("briefing-modal");
  const title = document.getElementById("briefing-modal-title");
  const subtitle = document.getElementById("briefing-modal-subtitle");
  const historyDays = state.homeBriefingPayload?.security?.history_window_days || 7;
  title.textContent = state.briefingModalKind === "vulnerabilities" ? "Vulnerabilidades de 7 dias" : "Noticias de 7 dias";
  subtitle.textContent = state.briefingModalKind === "vulnerabilities"
    ? `Se muestran las vulnerabilidades detectadas durante los ultimos ${historyDays} dias.`
    : `Se muestran las noticias y actualizaciones detectadas durante los ultimos ${historyDays} dias.`;
  modal.classList.remove("hidden-panel");
  modal.setAttribute("aria-hidden", "false");
  renderBriefingModal();
}

function closeBriefingModal() {
  const modal = document.getElementById("briefing-modal");
  modal.classList.add("hidden-panel");
  modal.setAttribute("aria-hidden", "true");
}

function renderBriefingModal() {
  const root = document.getElementById("briefing-modal-list");
  const security = state.homeBriefingPayload?.security || {};
  const historyDays = security.history_window_days || 7;
  if (state.briefingModalKind === "vulnerabilities") {
    const entries = security.vulnerabilities_7d || filterBriefingEntriesByDays(security.vulnerabilities || [], historyDays);
    root.innerHTML = entries.length
      ? renderVulnerabilityBriefingItems(entries)
      : `
        <article class="briefing-item is-empty">
          <p class="briefing-kicker">Historial de ${escapeHtml(historyDays)} dias</p>
          <h3>No hay vulnerabilidades para mostrar en este rango.</h3>
          <p>Cuando se detecten nuevas entradas KEV dentro de la ventana configurada, apareceran aqui.</p>
        </article>
      `;
    return;
  }

  const entries = security.headlines_7d || filterBriefingEntriesByDays(security.headlines || [], historyDays);
  root.innerHTML = entries.length
    ? renderSecurityBriefingItems(entries)
    : `
      <article class="briefing-item is-empty">
        <p class="briefing-kicker">Historial de ${escapeHtml(historyDays)} dias</p>
        <h3>No hay noticias para mostrar en este rango.</h3>
        <p>Cuando se detecten nuevos titulares dentro de la ventana configurada, apareceran aqui.</p>
      </article>
    `;
}

function homeBriefingFallback() {
  return {
    security: {
      headlines: [],
      headlines_7d: [],
      headline_sources: [],
      vulnerabilities: [],
      vulnerabilities_7d: [],
      catalog_version: "n/d",
      catalog_count: 0,
      history_window_days: 7,
      visible_window_days: 2,
    },
    market: {
      tickers: [],
    },
    sources: {
      advisory_feed: { status: "degraded" },
      kev_feed: { status: "degraded" },
      market_feed: { status: "degraded" },
    },
  };
}

function renderMetrics(statusPayload) {
  const jobs = statusPayload.jobs || [];
  const runningJobs = jobs.filter((item) => item.status === "running").length;
  const cards = [
    { label: "Jobs activos", value: runningJobs, note: "Ejecuciones en segundo plano desde el panel." },
    { label: "Inventarios", value: statusPayload.inventory_count || 0, note: "Snapshots detectados bajo output/." },
    { label: "Update reports", value: statusPayload.update_count || 0, note: "Reportes detectados bajo update-reports/." },
  ];

  document.getElementById("metrics-grid").innerHTML = cards.map((card) => `
    <article class="card metric-card">
      <p>${escapeHtml(card.label)}</p>
      <h3>${escapeHtml(card.value)}</h3>
      <p>${escapeHtml(card.note)}</p>
    </article>
  `).join("");
}

function renderTrends(inventoryReports, updateReports) {
  const inventorySeries = inventoryReports.slice(0, 8).reverse();
  const updateSeries = updateReports.slice(0, 8).reverse();

  const inventoryQuickCount = inventoryReports.filter((report) => report.manifest.quick_mode === "1").length;
  const inventoryWarningValues = inventorySeries.map((report) => toNumber(report.warnings_count));
  const inventoryCard = trendCard({
    title: "Tendencia de inventarios",
    subtitle: "Warnings detectados por snapshot reciente.",
    values: inventoryWarningValues,
    color: "#78d2b6",
    statLabel: "Ultimo snapshot",
    statValue: inventoryReports[0]?.id || "sin datos",
    startLabel: shortTimestamp(inventorySeries[0]?.created_at),
    endLabel: shortTimestamp(inventorySeries.at(-1)?.created_at),
    legend: [
      `<span>quick ${escapeHtml(inventoryQuickCount)}</span>`,
      `<span>full ${escapeHtml(Math.max(inventoryReports.length - inventoryQuickCount, 0))}</span>`,
      `<span>warnings ${escapeHtml(inventoryWarningValues.at(-1) ?? 0)}</span>`,
    ],
  });

  const updatePlannedValues = updateSeries.map((report) => toNumber(report.summary.planned_updated || report.summary.updated));
  const updateCard = trendCard({
    title: "Tendencia de paquetes",
    subtitle: "Cambios planeados o aplicados por ejecucion de update.",
    values: updatePlannedValues,
    color: "#f2b46d",
    statLabel: "Ultimo lote",
    statValue: updateReports[0]?.summary?.mode || "sin datos",
    startLabel: shortTimestamp(updateSeries[0]?.created_at),
    endLabel: shortTimestamp(updateSeries.at(-1)?.created_at),
    legend: [
      `<span>trusted ${escapeHtml(updateReports.filter((report) => report.trust.status === "trusted").length)}</span>`,
      `<span>review ${escapeHtml(updateReports.filter((report) => report.trust.status === "review").length)}</span>`,
      `<span>latest ${escapeHtml(updatePlannedValues.at(-1) ?? 0)}</span>`,
    ],
    emptyMessage: "Todavia no hay reportes en update-reports/ para dibujar la tendencia.",
  });

  const trustSeverityValues = updateSeries.map((report) => {
    switch (report.trust.status) {
      case "failed":
        return 3;
      case "review":
        return 2;
      case "limited":
        return 1;
      default:
        return 0;
    }
  });
  const trustCard = trendCard({
    title: "Riesgo de trust",
    subtitle: "Severidad historica del estado de fuentes y firmas.",
    values: trustSeverityValues,
    color: "#f06a72",
    statLabel: "Estado actual",
    statValue: updateReports[0]?.trust?.status || "sin datos",
    startLabel: shortTimestamp(updateSeries[0]?.created_at),
    endLabel: shortTimestamp(updateSeries.at(-1)?.created_at),
    legend: [
      `<span>failed ${escapeHtml(updateReports.filter((report) => report.trust.status === "failed").length)}</span>`,
      `<span>review ${escapeHtml(updateReports.filter((report) => report.trust.status === "review").length)}</span>`,
      `<span>trusted ${escapeHtml(updateReports.filter((report) => report.trust.status === "trusted").length)}</span>`,
    ],
    emptyMessage: "El historial de trust aparecera cuando existan reportes de actualizacion.",
  });

  document.getElementById("trend-grid").innerHTML = [inventoryCard, updateCard, trustCard].join("");
}

function renderServerMeta(statusPayload) {
  const host = new URL(window.location.href).host;
  const primaryIp = statusPayload.system?.primary_ip || "sin ip";
  document.getElementById("server-meta").innerHTML = `
    <span class="pill">${escapeHtml(host)}</span>
    <span class="pill">${escapeHtml(primaryIp)}</span>
    <span class="pill">${escapeHtml(statusPayload.server_time || "")}</span>
  `;
}

function normalizeJobKind(kind) {
  return kind === "update" ? "update" : "inventory";
}

function inferLaunchOptions(kind, command = []) {
  const args = Array.isArray(command) ? command : [];
  if (normalizeJobKind(kind) === "inventory") {
    return {
      quick: args.includes("--quick"),
    };
  }

  return {
    mode: args.includes("--apply") ? "apply" : "check",
    no_refresh: args.includes("--no-refresh"),
    auto_yes: args.includes("--auto-yes"),
    allow_untrusted_sources: args.includes("--allow-untrusted-sources"),
  };
}

function buildExecutionDescriptor(kind, options = {}, command = [], phase = "submitting") {
  const normalizedKind = normalizeJobKind(kind);
  const commandText = Array.isArray(command) && command.length ? command.join(" ") : "";

  if (normalizedKind === "update") {
    const mode = options.mode === "apply" ? "apply" : "check";
    return {
      title: phase === "submitting" ? "Inicializando flujo de paquetes" : "Esperando salida del flujo de paquetes",
      note: phase === "submitting"
        ? "Enviando la solicitud al backend local y preparando la terminal segura del job."
        : "La terminal aparecera en cuanto el script emita las primeras lineas de validacion o actualizacion.",
      steps: [
        mode === "apply" ? "Aplicacion de cambios autorizada para el gestor detectado." : "Ejecucion en modo reporte sin aplicar cambios al sistema.",
        options.no_refresh ? "Se reutilizara metadata local del gestor de paquetes." : "Se refrescara metadata desde fuentes confiables antes del analisis.",
        options.auto_yes ? "Modo no interactivo habilitado para respuestas automáticas seguras." : "Se mantendra el flujo con confirmaciones interactivas cuando aplique.",
        options.allow_untrusted_sources ? "Fuentes en revision habilitadas bajo la politica actual del panel." : "Solo se consideran fuentes confiables y permitidas.",
        commandText ? `Comando: ${commandText}` : "Esperando asignacion del comando del job.",
      ],
    };
  }

  return {
    title: phase === "submitting" ? "Inicializando inventario" : "Esperando salida del inventario",
    note: phase === "submitting"
      ? "Enviando la solicitud al backend local y preparando la terminal del recolector."
      : "La terminal aparecera en cuanto el recolector publique las primeras lineas del snapshot.",
    steps: [
      options.quick ? "Modo rapido habilitado para un snapshot mas compacto del host." : "Modo completo habilitado para un snapshot detallado del host.",
      "Preparando deteccion de paquetes, init, red, puertos y servicios relevantes.",
      commandText ? `Comando: ${commandText}` : "Esperando asignacion del comando del job.",
    ],
  };
}

function buildExecutionStateMarkup(descriptor) {
  return `
    <span class="execution-spinner" aria-hidden="true"></span>
    <div class="execution-copy">
      <strong class="execution-title">${escapeHtml(descriptor.title)}</strong>
      <p class="execution-note">${escapeHtml(descriptor.note)}</p>
      <div class="execution-steps">
        ${descriptor.steps.map((step, index) => `<span class="execution-step">${escapeHtml(index + 1)}. ${escapeHtml(step)}</span>`).join("")}
      </div>
    </div>
  `;
}

function renderJobLaunchState(kind) {
  const normalizedKind = normalizeJobKind(kind);
  const panel = document.getElementById(`${normalizedKind}-execution-state`);
  const button = document.getElementById(normalizedKind === "update" ? "run-update" : "run-inventory");
  const launchState = state.jobLaunchPending[normalizedKind];
  const busy = Boolean(launchState);

  if (button) {
    button.disabled = busy;
    button.classList.toggle("is-busy", busy);
    button.setAttribute("aria-busy", busy ? "true" : "false");
  }

  if (!panel) {
    return;
  }

  if (!launchState) {
    panel.className = "execution-state hidden-panel";
    panel.innerHTML = "";
    return;
  }

  panel.className = "execution-state";
  panel.innerHTML = buildExecutionStateMarkup(launchState);
}

function renderExecutionStates() {
  renderJobLaunchState("inventory");
  renderJobLaunchState("update");
}

function syncPendingJobLaunches(jobs) {
  let changed = false;
  ["inventory", "update"].forEach((kind) => {
    const launchState = state.jobLaunchPending[kind];
    if (!launchState?.jobId) {
      return;
    }
    const matchedJob = jobs.find((job) => job.job_id === launchState.jobId);
    if (!matchedJob) {
      return;
    }
    if ((matchedJob.log || "").trim() || matchedJob.status !== "running") {
      state.jobLaunchPending[kind] = null;
      changed = true;
    }
  });

  if (changed) {
    renderExecutionStates();
  }
}

function renderJobs(jobs) {
  const container = document.getElementById("jobs-list");
  const template = document.getElementById("job-template");
  container.innerHTML = "";

  if (!jobs.length) {
    container.innerHTML = '<div class="empty-state">Todavia no hay jobs lanzados desde el panel.</div>';
    return;
  }

  jobs.forEach((job) => {
    const node = template.content.firstElementChild.cloneNode(true);
    node.querySelector("h3").textContent = `${job.name} · ${job.job_id.slice(0, 8)}`;
    node.querySelector(".job-meta").textContent = `${job.started_at}${job.report_dir ? ` · ${job.report_dir}` : ""}`;
    const statusNode = node.querySelector(".job-status");
    const progressNode = node.querySelector(".job-progress");
    const logNode = node.querySelector(".job-log");
    const waitingForOutput = job.status === "running" && !(job.log || "").trim();
    statusNode.textContent = job.status;
    statusNode.classList.add(statusClass(job.status));
    if (waitingForOutput) {
      const descriptor = buildExecutionDescriptor(job.name, inferLaunchOptions(job.name, job.command || []), job.command || [], "awaiting-output");
      progressNode.className = "job-progress execution-state";
      progressNode.innerHTML = buildExecutionStateMarkup(descriptor);
      logNode.classList.add("hidden-panel");
      logNode.textContent = "";
    } else {
      progressNode.className = "job-progress hidden-panel";
      progressNode.innerHTML = "";
      logNode.classList.remove("hidden-panel");
      logNode.textContent = job.log || "Sin salida capturada para este job.";
    }
    container.appendChild(node);
  });
}

function renderServicesMeta(payload) {
  const system = payload.system || {};
  document.getElementById("services-meta").innerHTML = `
    <span class="pill">${escapeHtml(system.init_system || "unknown")}</span>
    <span class="pill">${escapeHtml(system.firewall_backend || "none")}</span>
    <span class="pill">${escapeHtml(payload.updated_at || "")}</span>
  `;
}

function renderServicesSummary(payload) {
  const services = payload.services || [];
  const running = services.filter((service) => service.status === "running").length;
  const unstable = services.filter((service) => ["failed", "degraded", "stopped"].includes(service.status)).length;
  const actionable = services.filter((service) => (service.actions || []).length > 0).length;
  const cards = [
    { label: "Servicios activos", value: running, note: "Objetivos supervisados en estado running." },
    { label: "Servicios con atencion", value: unstable, note: "Stopped, degraded o failed." },
    { label: "Acciones disponibles", value: actionable, note: "Targets con start, stop o restart." },
  ];

  document.getElementById("services-summary").innerHTML = cards.map((card) => `
    <article class="card metric-card">
      <p>${escapeHtml(card.label)}</p>
      <h3>${escapeHtml(card.value)}</h3>
      <p>${escapeHtml(card.note)}</p>
    </article>
  `).join("");
}

function rememberServiceActionResult(result) {
  const entry = {
    ...result,
    recorded_at: new Date().toISOString(),
  };
  state.serviceActionHistory = [entry, ...state.serviceActionHistory]
    .slice(0, 6);
  saveServiceActionHistory(state.serviceActionHistory);
}

function renderServiceActionHistory() {
  if (!state.serviceActionHistory.length) {
    return "";
  }

  return `
    <section class="service-history">
      <div class="card-head service-history-head">
        <div>
          <h3>Acciones recientes</h3>
          <p>Resumen corto de las ultimas operaciones lanzadas desde el panel.</p>
        </div>
        <span class="badge">${escapeHtml(state.serviceActionHistory.length)}</span>
      </div>
      <div class="service-history-list">
        ${state.serviceActionHistory.map((entry) => {
          const commandText = Array.isArray(entry.command) && entry.command.length ? entry.command.join(" ") : "Sin comando registrado";
          const outputPreview = [entry.stdout, entry.stderr]
            .filter(Boolean)
            .join("\n")
            .trim()
            .split("\n")
            .find(Boolean) || "Sin salida adicional.";
          return `
            <article class="service-history-item">
              <div class="service-history-meta">
                <strong>${escapeHtml(entry.service_id || "service")} · ${escapeHtml(entry.action || "accion")}</strong>
                <span class="status-chip ${statusClass(entry.status || "unknown")}">${escapeHtml(entry.status || "unknown")}</span>
              </div>
              <span class="service-history-time">${escapeHtml(entry.recorded_at || "")}</span>
              <p>${escapeHtml(commandText)}</p>
              <span class="service-history-output">${escapeHtml(outputPreview)}</span>
            </article>
          `;
        }).join("")}
      </div>
    </section>
  `;
}

function renderServiceActionFeedback() {
  const node = document.getElementById("service-action-feedback");
  const pending = state.serviceActionPending;
  const result = state.serviceActionResult;
  const historyMarkup = renderServiceActionHistory();
  if (pending) {
    const service = (state.servicesPayload?.services || []).find((item) => item.id === pending.serviceId);
    node.className = "empty-state service-feedback-pending";
    node.innerHTML = `${buildExecutionStateMarkup(buildServiceExecutionDescriptor(service || { id: pending.serviceId, title: pending.serviceId, backend: "service" }, pending.action))}${historyMarkup}`;
    return;
  }
  if (!result && !state.serviceActionHistory.length) {
    node.className = "empty-state hidden-panel";
    node.textContent = "";
    return;
  }

  if (!result) {
    node.className = "empty-state";
    node.innerHTML = historyMarkup;
    return;
  }

  const output = [result.stdout, result.stderr].filter(Boolean).join("\n").trim() || "Sin salida adicional.";
  node.className = "empty-state";
  node.innerHTML = `
    <strong>${escapeHtml(result.service_id || "service")} · ${escapeHtml(result.action || "accion")} · ${escapeHtml(result.status || "unknown")}</strong>
    <p>${escapeHtml(Array.isArray(result.command) ? result.command.join(" ") : "")}</p>
    <pre class="job-log">${escapeHtml(output)}</pre>
    ${historyMarkup}
  `;
}

function renderServiceLogViewer() {
  const node = document.getElementById("service-log-viewer");
  const result = state.serviceLogResult;
  const pendingServiceId = state.serviceLogPending;

  if (pendingServiceId && !result) {
    node.className = "comparison-panel";
    node.innerHTML = `
      <section>
        <h3>${escapeHtml(pendingServiceId)} · cargando logs</h3>
        <div class="diff-meta">
          <span>estado: consultando</span>
        </div>
        <pre class="file-preview">Solicitando eventos recientes del servicio...</pre>
      </section>
    `;
    return;
  }

  if (!result) {
    node.className = "comparison-panel empty-state";
    node.textContent = 'Selecciona un servicio y usa "Ver logs" para revisar eventos recientes.';
    return;
  }

  node.className = "comparison-panel";
  node.innerHTML = `
    <section>
      <h3>${escapeHtml(result.service_id || "service")} · logs recientes</h3>
      <div class="diff-meta">
        <span>${escapeHtml(result.status || "unknown")}</span>
        <span>${escapeHtml(result.source || "unknown")}</span>
      </div>
      <pre class="file-preview">${escapeHtml(result.content || "Sin logs disponibles.")}</pre>
    </section>
  `;
}

function capabilityLabel(capabilityKey) {
  const labels = {
    sftp: "SFTP",
    docker_cli: "Docker CLI",
    docker_socket: "Docker socket",
  };
  return labels[capabilityKey] || capabilityKey.replaceAll("_", " ");
}

function capabilityMetaLabel(metaKey) {
  const labels = {
    path: "ruta",
    owner: "owner",
    group: "group",
    mode: "mode",
    panel_user: "usuario panel",
    panel_group_member: "grupo socket",
    panel_read: "lectura",
    panel_write: "escritura",
    server_version: "version servidor",
    containers_running: "contenedores activos",
    containers_paused: "contenedores pausados",
    containers_stopped: "contenedores detenidos",
    driver: "driver",
  };
  return labels[metaKey] || metaKey.replaceAll("_", " ");
}

function capabilityMetaMarkup(capability) {
  const entries = Object.entries(capability?.meta || {}).filter(([, value]) => value !== "" && value !== null && value !== undefined);
  if (!entries.length) {
    return "";
  }

  return `
    <div class="capability-meta">
      ${entries.map(([metaKey, value]) => `<span class="badge">${escapeHtml(capabilityMetaLabel(metaKey))}: ${escapeHtml(String(value))}</span>`).join("")}
    </div>
  `;
}

function serviceCapabilityMarkup(service) {
  const capabilities = Object.entries(service.capabilities || {});
  if (!capabilities.length) {
    return "";
  }

  return `
    ${capabilities.map(([capabilityKey, capability]) => `
      <div class="capability-block">
        <strong>${escapeHtml(capabilityLabel(capabilityKey))} · ${escapeHtml(capability?.status || "unknown")}</strong>
        <span>${escapeHtml(capability?.detail || "Sin detalle.")}</span>
        ${capabilityMetaMarkup(capability)}
      </div>
    `).join("")}
  `;
}

function serviceMembersMarkup(service) {
  const members = service.members || [];
  if (!members.length) {
    return '<div class="empty-state">No se detecto un servicio asociado en este host.</div>';
  }
  return `
    <div class="member-list">
      ${members.map((member) => `<span class="badge ${statusClass(member.status)}">${escapeHtml(member.source_name)} · ${escapeHtml(member.status)}</span>`).join("")}
    </div>
  `;
}

function serviceMetaMarkup(service) {
  const entries = [];
  if (service.backend) {
    entries.push(`backend:${service.backend}`);
  }
  if ((service.ports || []).length) {
    entries.push(`esperados:${service.ports.join(", ")}`);
  }
  if ((service.listening_ports || []).length) {
    entries.push(`activos:${service.listening_ports.join(", ")}`);
  } else if ((service.ports || []).length) {
    entries.push("activos:ninguno");
  }
  if (service.source_name) {
    entries.push(`origen:${service.source_name}`);
  }

  if (!entries.length) {
    return "";
  }

  return `
    <div class="report-tags">
      ${entries.map((entry) => `<span class="badge">${escapeHtml(entry)}</span>`).join("")}
    </div>
  `;
}

function serviceNoticeMarkup(service) {
  const dockerSocket = service.capabilities?.docker_socket;
  if (service.id === "docker" && dockerSocket?.status === "available" && service.status !== "running") {
    return '<div class="service-warning">docker.sock esta disponible, pero el daemon no aparece en estado running.</div>';
  }
  if (service.id === "docker" && dockerSocket?.status !== "available" && service.status === "running") {
    return '<div class="service-warning">El daemon Docker aparece activo, pero no se detecto docker.sock en las rutas esperadas.</div>';
  }
  return "";
}

function buildServiceExecutionDescriptor(service, action) {
  const title = service?.title || service?.id || "Servicio";
  const members = (service?.members || []).map((member) => member.source_name).filter(Boolean);
  const activePorts = (service?.listening_ports || []).length ? service.listening_ports.join(", ") : "ninguno";
  const targets = members.length ? members.join(", ") : (service?.source_name || service?.backend || "objetivo no detectado");
  const impact = action === "restart"
    ? "El servicio puede interrumpirse brevemente mientras se reinicia."
    : action === "stop"
      ? "La disponibilidad del servicio puede caer hasta que vuelva a iniciarse."
      : "El backend intentara llevar el servicio a estado operativo.";

  return {
    title: `${action} ${title}`,
    note: `El panel esta esperando la respuesta del backend local para ${action} este servicio.`,
    steps: [
      `Objetivo: ${targets}`,
      `Backend detectado: ${service?.backend || "service"}`,
      `Puertos activos actuales: ${activePorts}`,
      impact,
    ],
  };
}

function servicePendingMarkup(service) {
  const pending = state.serviceActionPending;
  if (!pending || pending.serviceId !== service.id) {
    return "";
  }
  return `<div class="service-execution-state execution-state">${buildExecutionStateMarkup(buildServiceExecutionDescriptor(service, pending.action))}</div>`;
}

function serviceActionButtons(service) {
  const pending = state.serviceActionPending;
  const logPending = state.serviceLogPending === service.id;
  const logSelected = state.selectedServiceLogId === service.id;
  return (service.actions || []).map((action) => {
    const isPending = pending?.serviceId === service.id && pending?.action === action;
    const isServicePending = pending?.serviceId === service.id;
    return `
      <button
        class="secondary-button ${isPending ? "is-busy" : ""}"
        type="button"
        data-service-id="${escapeHtml(service.id)}"
        data-service-action="${escapeHtml(action)}"
        ${isServicePending ? "disabled" : ""}
      >${escapeHtml(isPending ? `${action}...` : action)}</button>
    `;
  }).join("") + `
    <button
      class="secondary-button service-log-button ${logSelected ? "is-selected" : ""} ${pending?.serviceId === service.id ? "is-busy" : ""}"
      type="button"
      data-service-log="${escapeHtml(service.id)}"
      ${logPending || pending?.serviceId === service.id ? "disabled" : ""}
    >${escapeHtml(logPending ? "cargando logs..." : logSelected ? "Logs visibles" : "Ver logs")}</button>
  `;
}

function activePreviewSelection(detail) {
  if (!state.selectedPreview) {
    return null;
  }
  if (state.selectedPreview.kind !== detail.kind || state.selectedPreview.reportId !== detail.id) {
    return null;
  }
  return state.selectedPreview;
}

function renderServicesGrid(payload) {
  const root = document.getElementById("services-grid");
  const services = payload.services || [];
  if (!services.length) {
    root.innerHTML = '<div class="empty-state">No se encontraron servicios supervisados para este host.</div>';
    return;
  }

  root.innerHTML = services.map((service) => {
    const tiles = buildSummaryTiles([
      { label: "Estado", value: service.status || "unknown" },
      { label: "Habilitado", value: service.enabled || "unknown" },
      { label: "Origen", value: service.source_name || service.backend || "no detectado" },
      { label: "Backend", value: service.backend || "service" },
      { label: "Puertos activos", value: (service.listening_ports || []).length ? service.listening_ports.join(", ") : "ninguno" },
    ]);
    return `
      <article class="service-card">
        <div class="card-head">
          <div>
            <h3>${escapeHtml(service.title)}</h3>
            <p>${escapeHtml(service.kind === "firewall" ? "Backend operativo del firewall" : "Servicio supervisado")}</p>
          </div>
          <span class="status-chip ${statusClass(service.status)}">${escapeHtml(service.status || "unknown")}</span>
        </div>
        ${serviceMetaMarkup(service)}
        ${tiles}
        ${serviceNoticeMarkup(service)}
        <p class="service-detail">${escapeHtml(service.detail || "Sin detalle.")}</p>
        ${serviceCapabilityMarkup(service)}
        ${serviceMembersMarkup(service)}
        ${servicePendingMarkup(service)}
        <div class="service-actions">
          ${serviceActionButtons(service) || '<span class="badge">Sin acciones disponibles</span>'}
        </div>
      </article>
    `;
  }).join("");
}

function buildComparisonBox(title, items) {
  if (!items.length) {
    return `
      <article class="comparison-box">
        <h4>${escapeHtml(title)}</h4>
        <div class="comparison-list"><span>Sin diferencias relevantes.</span></div>
      </article>
    `;
  }

  return `
    <article class="comparison-box">
      <h4>${escapeHtml(title)}</h4>
      <div class="comparison-list">
        ${items.map((item) => `<span>${escapeHtml(item)}</span>`).join("")}
      </div>
    </article>
  `;
}

function diffList(currentValues, previousValues, labelAdded, labelRemoved) {
  const current = new Set(currentValues || []);
  const previous = new Set(previousValues || []);
  const changes = [];

  current.forEach((value) => {
    if (!previous.has(value)) {
      changes.push(`${labelAdded}: ${value}`);
    }
  });
  previous.forEach((value) => {
    if (!current.has(value)) {
      changes.push(`${labelRemoved}: ${value}`);
    }
  });
  return changes;
}

function buildInventoryComparison(currentDetail, compareDetail) {
  const changedManifest = [];
  const manifestKeys = new Set([
    ...Object.keys(currentDetail.manifest || {}),
    ...Object.keys(compareDetail.manifest || {}),
  ]);
  manifestKeys.forEach((key) => {
    const currentValue = currentDetail.manifest?.[key] || "";
    const previousValue = compareDetail.manifest?.[key] || "";
    if (currentValue !== previousValue) {
      changedManifest.push(`${key}: ${previousValue || "-"} -> ${currentValue || "-"}`);
    }
  });

  const collectorDiffs = [];
  const collectorKeys = new Set([
    ...Object.keys(currentDetail.collector_status || {}),
    ...Object.keys(compareDetail.collector_status || {}),
  ]);
  collectorKeys.forEach((key) => {
    const currentValue = currentDetail.collector_status?.[key] || "";
    const previousValue = compareDetail.collector_status?.[key] || "";
    if (currentValue !== previousValue) {
      collectorDiffs.push(`${key}: ${previousValue || "-"} -> ${currentValue || "-"}`);
    }
  });

  return {
    headline: `${currentDetail.id} frente a ${compareDetail.id}`,
    boxes: [
      buildComparisonBox("Manifest", changedManifest),
      buildComparisonBox("Coletores", collectorDiffs),
      buildComparisonBox("Warnings", [`${compareDetail.warnings_count || 0} -> ${currentDetail.warnings_count || 0}`]),
    ],
  };
}

function buildUpdateComparison(currentDetail, compareDetail) {
  const summaryDiffs = [];
  ["planned_installed", "planned_updated", "planned_removed", "installed", "updated", "removed"].forEach((key) => {
    const currentValue = currentDetail.summary?.[key] || "0";
    const previousValue = compareDetail.summary?.[key] || "0";
    if (currentValue !== previousValue) {
      summaryDiffs.push(`${key}: ${previousValue} -> ${currentValue}`);
    }
  });

  const trustDiffs = [];
  if ((currentDetail.trust?.status || "") !== (compareDetail.trust?.status || "")) {
    trustDiffs.push(`status: ${compareDetail.trust?.status || "-"} -> ${currentDetail.trust?.status || "-"}`);
  }
  trustDiffs.push(...diffList(currentDetail.trust?.allowed_sources || [], compareDetail.trust?.allowed_sources || [], "nuevo allowed", "removed allowed"));
  trustDiffs.push(...diffList(currentDetail.trust?.review_sources || [], compareDetail.trust?.review_sources || [], "nuevo review", "resolved review"));

  const securitySections = Object.keys(currentDetail.security?.sections || {});
  const previousSections = Object.keys(compareDetail.security?.sections || {});
  const securityDiffs = diffList(securitySections, previousSections, "nueva seccion", "seccion ausente");

  return {
    headline: `${currentDetail.id} frente a ${compareDetail.id}`,
    boxes: [
      buildComparisonBox("Summary", summaryDiffs),
      buildComparisonBox("Trust", trustDiffs),
      buildComparisonBox("Security", securityDiffs),
    ],
  };
}

function renderComparisonPanel(currentDetail, compareDetail) {
  const panel = document.getElementById("comparison-panel");
  if (!currentDetail) {
    panel.className = "comparison-panel empty-state";
    panel.textContent = "Selecciona un reporte para comparar.";
    return;
  }

  if (!compareDetail) {
    panel.className = "comparison-panel empty-state";
    panel.textContent = "Selecciona una ejecucion base del mismo tipo para ver diferencias.";
    return;
  }

  const comparison = currentDetail.kind === "update"
    ? buildUpdateComparison(currentDetail, compareDetail)
    : buildInventoryComparison(currentDetail, compareDetail);

  panel.className = "comparison-panel";
  panel.innerHTML = `
    <section>
      <h3>${escapeHtml(comparison.headline)}</h3>
      <div class="comparison-grid">
        ${comparison.boxes.join("")}
      </div>
    </section>
  `;
}

function populateCompareSelect(kind, selectedReportId) {
  const select = document.getElementById("compare-report-select");
  const reports = getReportsByKind(kind);
  const compareId = state.compareSelection[kind] || defaultCompareId(kind, selectedReportId);
  state.compareSelection[kind] = compareId;

  select.innerHTML = `<option value="">Sin comparacion</option>${reports
    .filter((report) => report.id !== selectedReportId)
    .map((report) => `<option value="${escapeHtml(report.id)}" ${report.id === compareId ? "selected" : ""}>${escapeHtml(report.id)}</option>`)
    .join("")}`;
}

function populateCompareFileSelect(kind, currentDetail, compareDetail) {
  const select = document.getElementById("compare-file-select");
  const sharedPaths = sharedPreviewableFiles(currentDetail, compareDetail);

  if (!sharedPaths.length) {
    state.compareFileSelection[kind] = "";
    select.innerHTML = '<option value="">Archivo para diff...</option>';
    return;
  }

  if (!state.compareFileSelection[kind] || !sharedPaths.includes(state.compareFileSelection[kind])) {
    state.compareFileSelection[kind] = defaultCompareFilePath(currentDetail, compareDetail);
  }

  select.innerHTML = `<option value="">Archivo para diff...</option>${sharedPaths
    .map((path) => `<option value="${escapeHtml(path)}" ${path === state.compareFileSelection[kind] ? "selected" : ""}>${escapeHtml(path)}</option>`)
    .join("")}`;
}

function buildExecutiveSummary(detail, comparisonDetail) {
  const lines = [
    `Reporte: ${detail.id}`,
    `Tipo: ${detail.kind}`,
    `Ruta: ${detail.path}`,
  ];

  if (detail.kind === "update") {
    lines.push(`Modo: ${detail.summary?.mode || detail.manifest?.mode || "unknown"}`);
    lines.push(`Trust: ${detail.trust?.status || "unknown"}`);
    lines.push(`Planned updated: ${detail.summary?.planned_updated || "0"}`);
  } else {
    lines.push(`Quick mode: ${detail.manifest?.quick_mode === "1" ? "si" : "no"}`);
    lines.push(`Warnings: ${detail.warnings_count || 0}`);
    lines.push(`Backend: ${detail.manifest?.package_backend || "unknown"}`);
  }

  if (comparisonDetail) {
    lines.push("");
    lines.push(`Comparado con: ${comparisonDetail.id}`);
    if (detail.kind === "update") {
      lines.push(`Trust actual/anterior: ${detail.trust?.status || "-"} / ${comparisonDetail.trust?.status || "-"}`);
      lines.push(`Planned updated actual/anterior: ${detail.summary?.planned_updated || "0"} / ${comparisonDetail.summary?.planned_updated || "0"}`);
    } else {
      lines.push(`Warnings actual/anterior: ${detail.warnings_count || 0} / ${comparisonDetail.warnings_count || 0}`);
      lines.push(`Quick actual/anterior: ${detail.manifest?.quick_mode === "1" ? "si" : "no"} / ${comparisonDetail.manifest?.quick_mode === "1" ? "si" : "no"}`);
    }
  }

  return `${lines.join("\n")}\n`;
}

function buildTextDiff(previousContent, currentContent) {
  const previousLines = (previousContent || "").split("\n");
  const currentLines = (currentContent || "").split("\n");
  const maxLength = Math.max(previousLines.length, currentLines.length);
  const output = [];
  let changedLines = 0;

  for (let index = 0; index < maxLength; index += 1) {
    const previousLine = previousLines[index] ?? "";
    const currentLine = currentLines[index] ?? "";
    if (previousLine === currentLine) {
      if (previousLine !== "") {
        output.push(`  ${previousLine}`);
      }
      continue;
    }
    changedLines += 1;
    if (previousLine !== "") {
      output.push(`- ${previousLine}`);
    }
    if (currentLine !== "") {
      output.push(`+ ${currentLine}`);
    }
  }

  return {
    changedLines,
    text: output.length ? output.join("\n") : "Sin diferencias de contenido detectables en el preview.",
  };
}

function formatDiffHtml(diffText) {
  return diffText
    .split("\n")
    .map((line) => {
      const escaped = escapeHtml(line);
      if (line.startsWith("+ ")) {
        return `<span class="diff-added">${escaped}</span>`;
      }
      if (line.startsWith("- ")) {
        return `<span class="diff-removed">${escaped}</span>`;
      }
      return escaped;
    })
    .join("\n");
}

async function renderFileDiffPanel() {
  const panel = document.getElementById("file-diff-panel");
  const currentDetail = state.selectedDetail;
  const compareDetail = state.comparisonDetail;

  if (!currentDetail || !compareDetail) {
    panel.className = "comparison-panel empty-state";
    panel.textContent = "Selecciona una comparacion y un archivo compartido para ver diferencias de contenido.";
    return;
  }

  const selectedPath = state.compareFileSelection[currentDetail.kind];
  if (!selectedPath) {
    panel.className = "comparison-panel empty-state";
    panel.textContent = "Selecciona un archivo compartido para generar el diff.";
    return;
  }

  const [currentFile, previousFile] = await Promise.all([
    fetchJson(`/api/reports/${currentDetail.kind}/${encodeURIComponent(currentDetail.id)}/file?path=${encodeURIComponent(selectedPath)}`),
    fetchJson(`/api/reports/${compareDetail.kind}/${encodeURIComponent(compareDetail.id)}/file?path=${encodeURIComponent(selectedPath)}`),
  ]);
  const diff = buildTextDiff(previousFile.content || "", currentFile.content || "");

  panel.className = "comparison-panel";
  panel.innerHTML = `
    <section>
      <h3>${escapeHtml(selectedPath)}</h3>
      <div class="diff-meta">
        <span>base: ${escapeHtml(compareDetail.id)}</span>
        <span>actual: ${escapeHtml(currentDetail.id)}</span>
        <span>lineas distintas: ${escapeHtml(diff.changedLines)}</span>
      </div>
      <pre class="file-preview diff-preview">${formatDiffHtml(diff.text)}</pre>
    </section>
  `;
}

function exportReportsCsv(kind) {
  const reports = kind === "update" ? filterUpdateReports(state.updateReports) : filterInventoryReports(state.inventoryReports);
  let rows;

  if (kind === "update") {
    rows = [
      ["id", "created_at", "mode", "trust_status", "planned_updated", "updated", "path"],
      ...reports.map((report) => [
        report.id,
        report.created_at,
        report.summary?.mode || report.manifest?.mode || "",
        report.trust?.status || "",
        report.summary?.planned_updated || "0",
        report.summary?.updated || "0",
        report.path,
      ]),
    ];
  } else {
    rows = [
      ["id", "created_at", "hostname", "os_name", "quick_mode", "warnings", "package_backend", "path"],
      ...reports.map((report) => [
        report.id,
        report.created_at,
        report.manifest?.hostname || "",
        report.manifest?.os_name || "",
        report.manifest?.quick_mode || "0",
        report.warnings_count || 0,
        report.manifest?.package_backend || "",
        report.path,
      ]),
    ];
  }

  const content = rows.map((row) => row.map(csvEscape).join(",")).join("\n");
  downloadText(`${kind}-reports.csv`, `${content}\n`, "text/csv;charset=utf-8");
}

function inventoryTags(report) {
  const tags = [];
  if (report.manifest.quick_mode === "1") {
    tags.push("quick");
  }
  if (report.warnings_count > 0) {
    tags.push(`${report.warnings_count} warnings`);
  }
  if (report.manifest.package_backend) {
    tags.push(report.manifest.package_backend);
  }
  return tags;
}

function updateTags(report) {
  const tags = [];
  if (report.summary.mode) {
    tags.push(report.summary.mode);
  }
  if (report.trust.status) {
    tags.push(`trust:${report.trust.status}`);
  }
  if (Number(report.summary.planned_updated || 0) > 0) {
    tags.push(`updates:${report.summary.planned_updated}`);
  }
  return tags;
}

function filterInventoryReports(reports) {
  const searchValue = document.getElementById("inventory-search")?.value.trim().toLowerCase() || "";
  const filterValue = document.getElementById("inventory-filter")?.value || "all";

  return reports.filter((report) => {
    const haystack = searchableText([
      report.id,
      report.path,
      report.manifest.os_name,
      report.manifest.package_backend,
      report.manifest.hostname,
    ]);

    if (searchValue && !haystack.includes(searchValue)) {
      return false;
    }

    if (filterValue === "quick") {
      return report.manifest.quick_mode === "1";
    }
    if (filterValue === "full") {
      return report.manifest.quick_mode !== "1";
    }
    if (filterValue === "warning") {
      return Number(report.warnings_count || 0) > 0;
    }
    return true;
  });
}

function filterUpdateReports(reports) {
  const searchValue = document.getElementById("update-search")?.value.trim().toLowerCase() || "";
  const filterValue = document.getElementById("update-filter")?.value || "all";

  return reports.filter((report) => {
    const haystack = searchableText([
      report.id,
      report.path,
      report.summary.mode,
      report.trust.status,
      ...(report.trust.review_sources || []),
      ...(report.trust.allowed_sources || []),
      ...(report.trust.official_sources || []),
    ]);

    if (searchValue && !haystack.includes(searchValue)) {
      return false;
    }

    if (filterValue === "trusted") {
      return report.trust.status === "trusted";
    }
    if (filterValue === "review") {
      return report.trust.status === "review";
    }
    if (filterValue === "check" || filterValue === "apply") {
      return (report.summary.mode || report.manifest.mode) === filterValue;
    }
    if (filterValue === "changes") {
      return Number(report.summary.planned_updated || 0) > 0 || Number(report.summary.updated || 0) > 0;
    }
    return true;
  });
}

function renderReportList(containerId, reports, kind, options = {}) {
  const { limit = null, footerId = "" } = options;
  const container = document.getElementById(containerId);
  const footer = footerId ? document.getElementById(footerId) : null;
  const filteredReports = kind === "inventory" ? filterInventoryReports(reports) : filterUpdateReports(reports);
  const visibleReports = typeof limit === "number" ? filteredReports.slice(0, limit) : filteredReports;
  if (!reports.length) {
    container.innerHTML = '<div class="empty-state">No hay reportes detectados todavia.</div>';
    if (footer) {
      footer.innerHTML = "";
    }
    return;
  }

  if (!filteredReports.length) {
    container.innerHTML = '<div class="empty-state">No hay reportes que coincidan con el filtro actual.</div>';
    if (footer) {
      footer.innerHTML = "";
    }
    return;
  }

  container.innerHTML = visibleReports.map((report) => {
    const tags = kind === "inventory" ? inventoryTags(report) : updateTags(report);
    const subtitle = kind === "inventory"
      ? `${report.manifest.os_name || "Host desconocido"}`
      : `${report.summary.mode || report.manifest.mode || "modo desconocido"}`;
    const selected = state.selectedReport?.kind === kind && state.selectedReport?.reportId === report.id ? "selected" : "";
    return `
      <article class="report-card ${selected}" data-kind="${kind}" data-report-id="${report.id}">
        <div class="card-head">
          <div>
            <h3>${escapeHtml(report.id)}</h3>
            <p>${escapeHtml(subtitle)}</p>
          </div>
          <span class="status-chip ${statusClass(kind === "update" ? report.trust.status : report.warnings_count > 0 ? "warning" : "trusted")}">
            ${escapeHtml(report.created_at)}
          </span>
        </div>
        <div class="report-meta">
          <span>${escapeHtml(report.path)}</span>
        </div>
        <div class="report-tags">
          ${tags.map((tag) => `<span class="badge">${escapeHtml(tag)}</span>`).join("")}
        </div>
      </article>
    `;
  }).join("");

  container.querySelectorAll(".report-card").forEach((node) => {
    node.addEventListener("click", async () => {
      const isSelected = state.selectedReport?.kind === node.dataset.kind && state.selectedReport?.reportId === node.dataset.reportId;
      if (isSelected) {
        closeSelectedReport();
        if (containerId === "report-modal-list") {
          closeReportModal();
        }
        return;
      }
      await loadReportDetail(node.dataset.kind, node.dataset.reportId);
      if (containerId === "report-modal-list") {
        closeReportModal();
      }
    });
  });

  if (footer) {
    if (filteredReports.length > visibleReports.length) {
      footer.innerHTML = `
        <button class="report-more-link" type="button" data-report-more="${escapeHtml(kind)}">
          Visualizar mas (${escapeHtml(filteredReports.length - visibleReports.length)} adicionales)
        </button>
      `;
      const trigger = footer.querySelector("[data-report-more]");
      trigger?.addEventListener("click", () => {
        openReportModal(kind);
      });
    } else {
      footer.innerHTML = "";
    }
  }
}

function renderObjectList(title, entries) {
  if (!entries.length) {
    return `<section><h3>${escapeHtml(title)}</h3><div class="empty-state">Sin datos.</div></section>`;
  }
  return `
    <section>
      <h3>${escapeHtml(title)}</h3>
      <div class="report-tags">
        ${entries.map((entry) => `<span class="badge">${escapeHtml(entry)}</span>`).join("")}
      </div>
    </section>
  `;
}

function renderDetail(detail) {
  const root = document.getElementById("report-detail");
  const actions = document.getElementById("detail-actions");
  const toolbar = document.getElementById("file-toolbar");
  const preview = document.getElementById("file-preview");
  const isUpdate = detail.kind === "update";
  const compareDetail = state.comparisonDetail;
  const previewableFiles = (detail.files || []).filter((file) => file.previewable);
  const currentPreview = activePreviewSelection(detail);

  if (isUpdate) {
    const summaryTiles = buildSummaryTiles([
      { label: "Trust", value: detail.trust.status || "unknown" },
      { label: "Modo", value: detail.summary.mode || detail.manifest.mode || "unknown" },
      { label: "Updates planeados", value: detail.summary.planned_updated || "0" },
      { label: "Security backend", value: detail.security.backend || "unknown" },
    ]);
    root.innerHTML = `
      <section>
        <h3>${escapeHtml(detail.id)}</h3>
        <p>${escapeHtml(detail.path)}</p>
      </section>
      ${summaryTiles}
      ${renderObjectList("Trust oficial", detail.trust.official_sources || [])}
      ${renderObjectList("Trust allowlist", detail.trust.allowed_sources || [])}
      ${renderObjectList("Trust en revision", detail.trust.review_sources || [])}
    `;
  } else {
    const collectors = Object.entries(detail.collector_status || {}).map(([key, value]) => `${key}:${value}`);
    const summaryTiles = buildSummaryTiles([
      { label: "Quick mode", value: detail.manifest.quick_mode === "1" ? "si" : "no" },
      { label: "Package backend", value: detail.manifest.package_backend || "unknown" },
      { label: "Init system", value: detail.manifest.init_system || "unknown" },
      { label: "Warnings", value: String(detail.warnings_count || 0) },
    ]);
    root.innerHTML = `
      <section>
        <h3>${escapeHtml(detail.id)}</h3>
        <p>${escapeHtml(detail.path)}</p>
      </section>
      ${summaryTiles}
      ${renderObjectList("Coletores", collectors)}
    `;
  }

  actions.innerHTML = [
    `<a class="file-link detail-link" href="/api/reports/${detail.kind}/${encodeURIComponent(detail.id)}/download?path=${encodeURIComponent("manifest.txt")}">Descargar manifest</a>`,
    isUpdate ? `<a class="file-link detail-link" href="/api/reports/${detail.kind}/${encodeURIComponent(detail.id)}/download?path=${encodeURIComponent("report.json")}">Descargar report.json</a>` : "",
    '<button class="secondary-button detail-link" id="close-report-viewer" type="button">Cerrar reporte</button>',
  ].filter(Boolean).join("");
  actions.querySelector("#close-report-viewer")?.addEventListener("click", () => {
    closeSelectedReport();
  });
  renderComparisonPanel(detail, compareDetail);
  toolbar.innerHTML = "";
  preview.textContent = currentPreview?.content || "Selecciona un archivo del reporte para previsualizarlo.";

  previewableFiles.forEach((file) => {
    const wrapper = document.createElement("div");
    wrapper.className = "file-action";
    if (currentPreview?.path === file.path) {
      wrapper.classList.add("is-selected");
    }
    const meta = document.createElement("div");
    meta.className = "file-action-meta";
    const title = document.createElement("strong");
    title.textContent = file.path;
    const note = document.createElement("span");
    note.textContent = currentPreview?.path === file.path ? "Vista activa" : "Preview disponible";
    meta.appendChild(title);
    meta.appendChild(note);
    const button = document.createElement("button");
    button.className = "file-button";
    if (currentPreview?.path === file.path) {
      button.classList.add("is-selected");
    }
    button.textContent = currentPreview?.path === file.path ? "Abierto" : "Abrir";
    button.addEventListener("click", async () => {
      state.selectedPreview = {
        kind: detail.kind,
        reportId: detail.id,
        path: file.path,
        content: "Cargando archivo...",
      };
      renderDetail(detail);
      try {
        const payload = await fetchJson(`/api/reports/${detail.kind}/${encodeURIComponent(detail.id)}/file?path=${encodeURIComponent(file.path)}`);
        if (state.selectedPreview?.kind === detail.kind && state.selectedPreview?.reportId === detail.id && state.selectedPreview?.path === file.path) {
          state.selectedPreview = {
            kind: detail.kind,
            reportId: detail.id,
            path: file.path,
            content: payload.content || "Archivo vacio.",
          };
          renderDetail(detail);
        }
      } catch (error) {
        if (state.selectedPreview?.kind === detail.kind && state.selectedPreview?.reportId === detail.id && state.selectedPreview?.path === file.path) {
          state.selectedPreview = {
            kind: detail.kind,
            reportId: detail.id,
            path: file.path,
            content: `No se pudo cargar el archivo: ${error.message}`,
          };
          renderDetail(detail);
        }
      }
    });
    const link = document.createElement("a");
    link.className = "file-link";
    link.href = `/api/reports/${detail.kind}/${encodeURIComponent(detail.id)}/download?path=${encodeURIComponent(file.path)}`;
    link.textContent = "Descargar";
    const actionRow = document.createElement("div");
    actionRow.className = "file-action-buttons";
    actionRow.appendChild(button);
    actionRow.appendChild(link);
    wrapper.appendChild(meta);
    wrapper.appendChild(actionRow);
    toolbar.appendChild(wrapper);
  });
}

function resetDetailView(message) {
  state.selectedPreview = null;
  document.getElementById("report-detail").textContent = message;
  document.getElementById("detail-actions").innerHTML = "";
  document.getElementById("compare-report-select").innerHTML = '<option value="">Comparar con...</option>';
  document.getElementById("compare-file-select").innerHTML = '<option value="">Archivo para diff...</option>';
  document.getElementById("file-toolbar").innerHTML = "";
  document.getElementById("file-preview").textContent = "Aun no hay archivo seleccionado.";
  document.getElementById("comparison-panel").className = "comparison-panel empty-state";
  document.getElementById("comparison-panel").textContent = "Selecciona un reporte para comparar.";
  document.getElementById("file-diff-panel").className = "comparison-panel empty-state";
  document.getElementById("file-diff-panel").textContent = "Selecciona una comparacion y un archivo compartido para ver diferencias de contenido.";
}

async function fetchReportDetail(kind, reportId) {
  return fetchJson(`/api/reports/${kind}/${encodeURIComponent(reportId)}`);
}

async function loadReportDetail(kind, reportId) {
  if (state.selectedPreview && (state.selectedPreview.kind !== kind || state.selectedPreview.reportId !== reportId)) {
    state.selectedPreview = null;
  }
  const detail = await fetchReportDetail(kind, reportId);
  if (!state.compareSelection[kind] || state.compareSelection[kind] === reportId) {
    state.compareSelection[kind] = defaultCompareId(kind, reportId);
  }
  const compareId = state.compareSelection[kind];
  const comparisonDetail = compareId ? await fetchReportDetail(kind, compareId) : null;
  setReportMenuKind(kind);
  state.reportViewerDismissed = false;
  state.selectedReport = { kind, reportId };
  savePreferredReportId(kind, reportId);
  state.selectedDetail = detail;
  state.comparisonDetail = comparisonDetail;
  populateCompareSelect(kind, reportId);
  populateCompareFileSelect(kind, detail, comparisonDetail);
  renderDetail(detail);
  await renderFileDiffPanel();
}

async function refreshStatusData() {
  const statusPayload = await fetchJson("/api/status");
  state.statusPayload = statusPayload;
  renderHomeSystemSummary(statusPayload.system || {});
  renderServerMeta(statusPayload);
  return statusPayload;
}

async function refreshHomeBriefing() {
  let briefingPayload = state.homeBriefingPayload || homeBriefingFallback();

  try {
    briefingPayload = await fetchJson("/api/home-briefing");
  } catch (error) {
    console.error(error);
    briefingPayload = homeBriefingFallback();
  }

  state.homeBriefingPayload = briefingPayload;
  renderHomeBriefing(briefingPayload || {});
  return briefingPayload;
}

async function refreshHome() {
  const statusPayload = await fetchJson("/api/status");
  state.statusPayload = statusPayload;
  renderHomeSystemSummary(statusPayload.system || {});
  const briefingPayload = await refreshHomeBriefing();
  return { statusPayload, briefingPayload };
}

async function refreshDashboard() {
  const [statusPayload, inventoryReports, updateReports] = await Promise.all([
    fetchJson("/api/status"),
    fetchJson("/api/reports?kind=inventory"),
    fetchJson("/api/reports?kind=update"),
  ]);

  state.statusPayload = statusPayload;
  state.inventoryReports = inventoryReports;
  state.updateReports = updateReports;
  renderReportMenuCounts();
  renderReportSelectorSummary();

  renderHomeSystemSummary(statusPayload.system || {});
  renderServerMeta(statusPayload);
  renderMetrics(statusPayload);
  renderTrends(inventoryReports, updateReports);
  renderJobs(statusPayload.jobs || []);
  syncPendingJobLaunches(statusPayload.jobs || []);
  renderReportList("inventory-reports", inventoryReports, "inventory", { limit: 4, footerId: "inventory-reports-more" });
  renderReportList("update-reports", updateReports, "update", { limit: 4, footerId: "update-reports-more" });
  setReportMenuKind(state.selectedReport?.kind || state.reportMenuKind);
  if (!document.getElementById("report-modal").classList.contains("hidden-panel")) {
    renderReportModal();
  }

  if (state.currentView !== "inventory") {
    return;
  }

  const preferredKind = state.selectedReport?.kind || state.reportMenuKind;
  const preferredPool = preferredKind === "update" ? updateReports : inventoryReports;
  const preferredReportId = loadPreferredReportId(preferredKind);
  const preferredFromStorage = preferredPool.find((report) => report.id === preferredReportId) || null;
  const preferred = preferredFromStorage || preferredPool[0] || updateReports[0] || inventoryReports[0];
  if (!preferred) {
    state.selectedReport = null;
    state.selectedDetail = null;
    state.comparisonDetail = null;
    resetDetailView("No hay reportes disponibles todavia.");
    return;
  }

  try {
    if (state.reportViewerDismissed) {
      resetDetailView("Selecciona una ejecucion para inspeccionar su salida.");
      return;
    }
    if (!state.selectedReport) {
      await loadReportDetail(preferred.kind, preferred.id);
      return;
    }
    await loadReportDetail(state.selectedReport.kind, state.selectedReport.reportId);
  } catch {
    state.selectedReport = null;
    await loadReportDetail(preferred.kind, preferred.id);
  }
}

async function refreshServices() {
  const payload = await fetchJson("/api/services");
  state.servicesPayload = payload;
  if (!state.statusPayload) {
    state.statusPayload = { system: payload.system };
  } else {
    state.statusPayload.system = payload.system;
  }
  renderHomeSystemSummary(payload.system || {});
  renderServicesMeta(payload);
  renderServicesSummary(payload);
  renderServicesGrid(payload);
  renderServiceActionFeedback();
  renderServiceLogViewer();
}

async function submitInventoryJob() {
  const quick = document.getElementById("inventory-quick").checked;
  state.jobLaunchPending.inventory = buildExecutionDescriptor("inventory", { quick }, [], "submitting");
  renderExecutionStates();
  try {
    const job = await fetchJson("/api/jobs/inventory", {
      method: "POST",
      body: JSON.stringify({ quick }),
    });
    state.jobLaunchPending.inventory = {
      ...buildExecutionDescriptor("inventory", { quick }, job.command || [], "awaiting-output"),
      jobId: job.job_id,
    };
    renderExecutionStates();
    await refreshDashboard();
  } catch (error) {
    state.jobLaunchPending.inventory = null;
    renderExecutionStates();
    throw error;
  }
}

async function submitUpdateJob() {
  const mode = document.querySelector('input[name="update-mode"]:checked').value;
  const noRefresh = document.getElementById("update-no-refresh").checked;
  const autoYes = document.getElementById("update-auto-yes").checked;
  const allowUntrusted = document.getElementById("update-allow-untrusted").checked;

  if (mode === "apply") {
    showApplyConfirmation({ mode, no_refresh: noRefresh, auto_yes: autoYes, allow_untrusted_sources: allowUntrusted });
    return;
  }

  await launchUpdateJob({ mode, no_refresh: noRefresh, auto_yes: autoYes, allow_untrusted_sources: allowUntrusted });
}

async function launchUpdateJob(payload) {
  hideApplyConfirmation();
  state.jobLaunchPending.update = buildExecutionDescriptor("update", payload, [], "submitting");
  renderExecutionStates();
  try {
    const job = await fetchJson("/api/jobs/update", {
      method: "POST",
      body: JSON.stringify(payload),
    });
    state.jobLaunchPending.update = {
      ...buildExecutionDescriptor("update", payload, job.command || [], "awaiting-output"),
      jobId: job.job_id,
    };
    renderExecutionStates();
    await refreshDashboard();
  } catch (error) {
    state.jobLaunchPending.update = null;
    renderExecutionStates();
    throw error;
  }
}

async function submitServiceAction(serviceId, action) {
  hideServiceConfirmation();
  state.serviceActionPending = { serviceId, action };
  renderServicesGrid(state.servicesPayload || { services: [] });
  try {
    const payload = await fetchJson("/api/services/action", {
      method: "POST",
      body: JSON.stringify({ service_id: serviceId, action }),
    });
    state.serviceActionResult = payload.result;
    rememberServiceActionResult(payload.result);
    state.servicesPayload = payload.services;
    state.statusPayload = {
      ...(state.statusPayload || {}),
      system: payload.services?.system || state.statusPayload?.system || {},
    };
    renderHomeSystemSummary(state.statusPayload.system || {});
    renderServicesMeta(payload.services || { system: state.statusPayload?.system || {}, updated_at: new Date().toISOString() });
    renderServicesSummary(payload.services || { services: [] });
    renderServicesGrid(payload.services || { services: [] });
    renderServiceActionFeedback();
  } catch (error) {
    state.serviceActionResult = {
      service_id: serviceId,
      action,
      status: "failed",
      stdout: "",
      stderr: error.message,
      command: [],
    };
    rememberServiceActionResult(state.serviceActionResult);
  } finally {
    state.serviceActionPending = null;
    renderServicesGrid(state.servicesPayload || { services: [] });
    renderServiceActionFeedback();
  }
}

async function loadServiceLogs(serviceId) {
  state.selectedServiceLogId = serviceId;
  state.serviceLogPending = serviceId;
  renderServicesGrid(state.servicesPayload || { services: [] });
  renderServiceLogViewer();
  try {
    state.serviceLogResult = await fetchJson(`/api/services/${encodeURIComponent(serviceId)}/logs?lines=40`);
  } finally {
    state.serviceLogPending = null;
    renderServicesGrid(state.servicesPayload || { services: [] });
    renderServiceLogViewer();
  }
}

function showApplyConfirmation(payload) {
  state.pendingApplyRequest = payload;
  const panel = document.getElementById("apply-confirmation");
  const text = document.getElementById("apply-confirmation-text");
  const input = document.getElementById("apply-confirmation-input");
  text.textContent = [
    "Estas por ejecutar update_packages.sh --apply.",
    `no-refresh=${payload.no_refresh ? "si" : "no"}`,
    `auto-yes=${payload.auto_yes ? "si" : "no"}`,
    `allow-untrusted-sources=${payload.allow_untrusted_sources ? "si" : "no"}`,
    "Escribe APPLY para confirmar.",
  ].join(" ");
  input.value = "";
  panel.classList.remove("hidden-panel");
  input.focus();
}

function hideApplyConfirmation() {
  state.pendingApplyRequest = null;
  document.getElementById("apply-confirmation").classList.add("hidden-panel");
}

function showServiceConfirmation(serviceId, action) {
  const panel = document.getElementById("service-confirmation");
  const text = document.getElementById("service-confirmation-text");
  const input = document.getElementById("service-confirmation-input");
  const service = (state.servicesPayload?.services || []).find((item) => item.id === serviceId);
  const expected = action.toUpperCase();
  let warning = "";

  if (serviceId === "firewall" && action === "stop") {
    warning = "Esto puede desactivar el filtrado del host.";
  } else if (serviceId === "ssh" && action === "stop") {
    warning = "Esto puede cortar el acceso remoto por SSH y SFTP.";
  } else if (serviceId === "ssh" && action === "restart") {
    warning = "Esto puede interrumpir sesiones SSH y SFTP activas.";
  } else if (serviceId === "docker" && action === "stop") {
    warning = "Esto puede afectar el daemon y la operacion de contenedores.";
  } else if (serviceId === "samba" && (action === "stop" || action === "restart")) {
    warning = "Esto puede interrumpir temporalmente el acceso a recursos compartidos.";
  } else if (action === "restart") {
    warning = "Esto puede causar una interrupcion breve del servicio.";
  }

  state.pendingServiceConfirmation = {
    serviceId,
    action,
    expected,
    title: service?.title || serviceId,
  };

  text.innerHTML = [
    `Estas por ejecutar <span class="service-confirmation-verb">${escapeHtml(action)}</span> sobre <strong>${escapeHtml(service?.title || serviceId)}</strong>.`,
    warning ? `<span>${escapeHtml(warning)}</span>` : "",
    `Escribe <strong>${escapeHtml(expected)}</strong> para continuar.`,
  ].filter(Boolean).join(" ");
  input.value = "";
  panel.classList.remove("hidden-panel");
  input.focus();
}

function hideServiceConfirmation() {
  state.pendingServiceConfirmation = null;
  document.getElementById("service-confirmation").classList.add("hidden-panel");
}

function clearPollTimers() {
  if (pollTimers.home) {
    window.clearInterval(pollTimers.home);
    pollTimers.home = null;
  }
  if (pollTimers.dashboard) {
    window.clearInterval(pollTimers.dashboard);
    pollTimers.dashboard = null;
  }
  if (pollTimers.services) {
    window.clearInterval(pollTimers.services);
    pollTimers.services = null;
  }
  if (pollTimers.briefing) {
    window.clearInterval(pollTimers.briefing);
    pollTimers.briefing = null;
  }
}

function syncPolling() {
  clearPollTimers();
  if (state.currentView !== "home") {
    pollTimers.briefing = window.setInterval(() => {
      refreshHomeBriefing().catch((error) => {
        console.error(error);
      });
    }, 60000);
  }
  if (state.currentView === "home") {
    pollTimers.home = window.setInterval(() => {
      refreshHome().catch((error) => {
        console.error(error);
      });
    }, 60000);
    return;
  }
  if (state.currentView === "inventory") {
    pollTimers.dashboard = window.setInterval(() => {
      refreshDashboard().catch((error) => {
        console.error(error);
      });
    }, 3000);
    return;
  }
  if (state.currentView === "services") {
    pollTimers.services = window.setInterval(() => {
      refreshServices().catch((error) => {
        console.error(error);
      });
    }, 5000);
  }
}

async function setActiveView(viewName) {
  state.currentView = normalizeView(viewName);
  savePreferredView(state.currentView);

  document.querySelectorAll(".view").forEach((node) => {
    node.classList.toggle("view-active", node.dataset.view === state.currentView);
    node.classList.toggle("hidden-panel", node.dataset.view !== state.currentView);
  });

  document.querySelectorAll("[data-target-view]").forEach((node) => {
    if (node.classList.contains("secondary-button")) {
      node.classList.toggle("active-switch", node.dataset.targetView === state.currentView);
    }
  });

  syncPolling();

  if (state.currentView === "inventory") {
    await refreshDashboard();
    refreshHomeBriefing().catch((error) => {
      console.error(error);
    });
    return;
  }
  if (state.currentView === "services") {
    await refreshServices();
    refreshHomeBriefing().catch((error) => {
      console.error(error);
    });
    return;
  }
  await refreshHome();
}

function randomBetween(min, max) {
  return min + Math.random() * (max - min);
}

function resizeParticles() {
  const canvas = particleState.canvas;
  if (!canvas || !particleState.context) {
    return;
  }
  const ratio = window.devicePixelRatio || 1;
  particleState.width = window.innerWidth;
  particleState.height = window.innerHeight;
  canvas.width = Math.floor(particleState.width * ratio);
  canvas.height = Math.floor(particleState.height * ratio);
  canvas.style.width = `${particleState.width}px`;
  canvas.style.height = `${particleState.height}px`;
  particleState.context.setTransform(ratio, 0, 0, ratio, 0, 0);
}

function seedParticles() {
  const count = Math.max(28, Math.min(56, Math.floor(window.innerWidth / 32)));
  particleState.particles = Array.from({ length: count }, () => ({
    x: randomBetween(0, particleState.width),
    y: randomBetween(0, particleState.height),
    dx: randomBetween(-0.2, 0.2),
    dy: randomBetween(-0.2, 0.2),
    size: randomBetween(1.1, 2.8),
    alpha: randomBetween(0.18, 0.58),
    hue: Math.random() > 0.38 ? "green" : "cyan",
    ring: randomBetween(1.8, 4.8),
  }));
}

function drawParticles() {
  const { context, width, height, particles } = particleState;
  if (!context) {
    return;
  }
  context.clearRect(0, 0, width, height);

  particles.forEach((particle) => {
    particle.x += particle.dx;
    particle.y += particle.dy;
    if (particle.x < -20) particle.x = width + 20;
    if (particle.x > width + 20) particle.x = -20;
    if (particle.y < -20) particle.y = height + 20;
    if (particle.y > height + 20) particle.y = -20;

    const color = particle.hue === "green"
      ? { fill: "86, 240, 154", ring: "212, 255, 103" }
      : { fill: "69, 215, 200", ring: "86, 240, 154" };

    context.beginPath();
    context.fillStyle = `rgba(${color.fill}, ${particle.alpha * 0.18})`;
    context.arc(particle.x, particle.y, particle.size + particle.ring, 0, Math.PI * 2);
    context.fill();

    context.beginPath();
    context.strokeStyle = `rgba(${color.ring}, ${particle.alpha * 0.28})`;
    context.lineWidth = 1;
    context.arc(particle.x, particle.y, particle.size + particle.ring * 0.35, 0, Math.PI * 2);
    context.stroke();

    context.beginPath();
    context.fillStyle = `rgba(${color.fill}, ${Math.min(particle.alpha + 0.26, 0.92)})`;
    context.arc(particle.x, particle.y, particle.size, 0, Math.PI * 2);
    context.fill();
  });

  for (let index = 0; index < particles.length; index += 1) {
    for (let inner = index + 1; inner < particles.length; inner += 1) {
      const first = particles[index];
      const second = particles[inner];
      const dx = first.x - second.x;
      const dy = first.y - second.y;
      const distance = Math.sqrt(dx * dx + dy * dy);
      if (distance > 138) {
        continue;
      }
      const tint = first.hue === second.hue
        ? (first.hue === "green" ? "86, 240, 154" : "69, 215, 200")
        : "212, 255, 103";
      context.beginPath();
      context.strokeStyle = `rgba(${tint}, ${0.2 - distance / 900})`;
      context.lineWidth = distance < 72 ? 1.4 : 0.8;
      context.moveTo(first.x, first.y);
      context.lineTo(second.x, second.y);
      context.stroke();
    }
  }

  particleState.frame = window.requestAnimationFrame(drawParticles);
}

function initParticles() {
  particleState.canvas = document.getElementById("particles-canvas");
  if (!particleState.canvas) {
    return;
  }
  particleState.context = particleState.canvas.getContext("2d");
  if (!particleState.context) {
    return;
  }
  resizeParticles();
  seedParticles();
  drawParticles();
  window.addEventListener("resize", () => {
    resizeParticles();
    seedParticles();
  });
}

function wireActions() {
  document.querySelectorAll("[data-target-view]").forEach((node) => {
    node.addEventListener("click", () => {
      setActiveView(node.dataset.targetView).catch((error) => {
        console.error(error);
      });
    });
  });

  document.getElementById("run-inventory").addEventListener("click", () => {
    submitInventoryJob().catch((error) => {
      window.alert(`No se pudo lanzar el inventario: ${error.message}`);
    });
  });

  document.getElementById("run-update").addEventListener("click", () => {
    submitUpdateJob().catch((error) => {
      window.alert(`No se pudo lanzar el flujo de paquetes: ${error.message}`);
    });
  });

  document.getElementById("confirm-apply").addEventListener("click", () => {
    if (!state.pendingApplyRequest) {
      return;
    }
    const input = document.getElementById("apply-confirmation-input");
    if (input.value !== "APPLY") {
      window.alert("Debes escribir APPLY para continuar.");
      return;
    }
    launchUpdateJob(state.pendingApplyRequest).catch((error) => {
      window.alert(`No se pudo lanzar el flujo de paquetes: ${error.message}`);
    });
  });

  document.getElementById("cancel-apply").addEventListener("click", () => {
    hideApplyConfirmation();
  });

  document.getElementById("confirm-service-action").addEventListener("click", () => {
    if (!state.pendingServiceConfirmation) {
      return;
    }
    const input = document.getElementById("service-confirmation-input");
    if (input.value !== state.pendingServiceConfirmation.expected) {
      window.alert(`Debes escribir ${state.pendingServiceConfirmation.expected} para continuar.`);
      return;
    }
    submitServiceAction(
      state.pendingServiceConfirmation.serviceId,
      state.pendingServiceConfirmation.action,
    ).catch((error) => {
      window.alert(`No se pudo ejecutar la accion del servicio: ${error.message}`);
    });
  });

  document.getElementById("cancel-service-action").addEventListener("click", () => {
    hideServiceConfirmation();
  });

  document.getElementById("export-inventory-csv").addEventListener("click", () => {
    exportReportsCsv("inventory");
  });

  document.getElementById("export-update-csv").addEventListener("click", () => {
    exportReportsCsv("update");
  });

  document.querySelectorAll("[data-report-menu]").forEach((node) => {
    node.addEventListener("click", async () => {
      const kind = node.dataset.reportMenu === "update" ? "update" : "inventory";
      setReportMenuKind(kind);
      if (state.selectedReport?.kind === kind) {
        return;
      }
      const reports = getReportsByKind(kind);
      const preferredReportId = loadPreferredReportId(kind);
      const preferredReport = reports.find((report) => report.id === preferredReportId) || reports[0];
      if (!reports.length) {
        state.selectedReport = null;
        state.selectedDetail = null;
        state.comparisonDetail = null;
        resetDetailView(kind === "update" ? "No hay reportes de actualizacion disponibles todavia." : "No hay inventarios disponibles todavia.");
        return;
      }
      await loadReportDetail(kind, preferredReport.id);
    });
  });

  document.getElementById("close-report-modal").addEventListener("click", () => {
    closeReportModal();
  });

  document.getElementById("open-headlines-modal").addEventListener("click", () => {
    openBriefingModal("headlines");
  });

  document.getElementById("open-vulnerabilities-modal").addEventListener("click", () => {
    openBriefingModal("vulnerabilities");
  });

  document.getElementById("close-briefing-modal").addEventListener("click", () => {
    closeBriefingModal();
  });

  document.getElementById("report-modal").addEventListener("click", (event) => {
    if (event.target.id === "report-modal") {
      closeReportModal();
    }
  });

  document.getElementById("briefing-modal").addEventListener("click", (event) => {
    if (event.target.id === "briefing-modal") {
      closeBriefingModal();
    }
  });

  document.getElementById("clear-compare").addEventListener("click", () => {
    if (!state.selectedReport) {
      return;
    }
    state.compareSelection[state.selectedReport.kind] = "";
    state.compareFileSelection[state.selectedReport.kind] = "";
    state.comparisonDetail = null;
    populateCompareSelect(state.selectedReport.kind, state.selectedReport.reportId);
    populateCompareFileSelect(state.selectedReport.kind, state.selectedDetail, null);
    renderComparisonPanel(state.selectedDetail, null);
    renderFileDiffPanel().catch((error) => {
      console.error(error);
    });
  });

  document.getElementById("compare-report-select").addEventListener("change", async (event) => {
    if (!state.selectedReport) {
      return;
    }
    const compareId = event.target.value;
    state.compareSelection[state.selectedReport.kind] = compareId;
    state.comparisonDetail = compareId ? await fetchReportDetail(state.selectedReport.kind, compareId) : null;
    populateCompareFileSelect(state.selectedReport.kind, state.selectedDetail, state.comparisonDetail);
    renderComparisonPanel(state.selectedDetail, state.comparisonDetail);
    await renderFileDiffPanel();
  });

  document.getElementById("compare-file-select").addEventListener("change", async (event) => {
    if (!state.selectedReport) {
      return;
    }
    state.compareFileSelection[state.selectedReport.kind] = event.target.value;
    await renderFileDiffPanel();
  });

  document.getElementById("export-summary").addEventListener("click", () => {
    if (!state.selectedDetail) {
      window.alert("Selecciona un reporte antes de exportar el resumen.");
      return;
    }
    const summary = buildExecutiveSummary(state.selectedDetail, state.comparisonDetail);
    downloadText(`${state.selectedDetail.id}-summary.txt`, summary);
  });

  ["inventory-search", "inventory-filter", "update-search", "update-filter"].forEach((id) => {
    document.getElementById(id).addEventListener("input", () => {
      renderReportList("inventory-reports", state.inventoryReports, "inventory", { limit: 4, footerId: "inventory-reports-more" });
      renderReportList("update-reports", state.updateReports, "update", { limit: 4, footerId: "update-reports-more" });
      if (!document.getElementById("report-modal").classList.contains("hidden-panel")) {
        renderReportModal();
      }
    });
    document.getElementById(id).addEventListener("change", () => {
      renderReportList("inventory-reports", state.inventoryReports, "inventory", { limit: 4, footerId: "inventory-reports-more" });
      renderReportList("update-reports", state.updateReports, "update", { limit: 4, footerId: "update-reports-more" });
      if (!document.getElementById("report-modal").classList.contains("hidden-panel")) {
        renderReportModal();
      }
    });
  });

  document.getElementById("refresh-services").addEventListener("click", () => {
    refreshServices().catch((error) => {
      window.alert(`No se pudo refrescar el monitoreo de servicios: ${error.message}`);
    });
  });

  document.getElementById("services-grid").addEventListener("click", (event) => {
    const logButton = event.target.closest("button[data-service-log]");
    if (logButton) {
      loadServiceLogs(logButton.dataset.serviceLog).catch((error) => {
        state.selectedServiceLogId = logButton.dataset.serviceLog;
        state.serviceLogResult = {
          service_id: logButton.dataset.serviceLog,
          status: "failed",
          source: "panel",
          content: error.message,
        };
        state.serviceLogPending = null;
        renderServicesGrid(state.servicesPayload || { services: [] });
        renderServiceLogViewer();
      });
      return;
    }

    const button = event.target.closest("button[data-service-id][data-service-action]");
    if (!button) {
      return;
    }
    const { serviceId, serviceAction } = button.dataset;
    if (serviceAction === "stop" || serviceAction === "restart") {
      showServiceConfirmation(serviceId, serviceAction);
      return;
    }
    submitServiceAction(serviceId, serviceAction).catch((error) => {
      window.alert(`No se pudo ejecutar la accion del servicio: ${error.message}`);
    });
  });
}

async function init() {
  wireActions();
  initParticles();
  state.serviceActionHistory = loadServiceActionHistory();
  renderExecutionStates();
  setReportMenuKind(loadPreferredReportMenu(), { persist: false });
  await setActiveView(loadPreferredView());
}

window.addEventListener("DOMContentLoaded", () => {
  init().catch((error) => {
    console.error(error);
    document.getElementById("home-system-summary").innerHTML = `<article class="summary-tile"><p>Error</p><strong>${escapeHtml(error.message)}</strong></article>`;
  });
});
