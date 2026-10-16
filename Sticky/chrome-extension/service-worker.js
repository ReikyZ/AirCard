"use strict";

const STICKY_URL = "http://127.0.0.1:17321/mimo-usage";
const COOKIE_URL = "https://platform.xiaomimimo.com/";
const USAGE_URL = "https://platform.xiaomimimo.com/api/v1/tokenPlan/usage";
const CURRENT_URL = "https://platform.xiaomimimo.com/api/v1/tokenPlan/current";

let lastSentAt = 0;

function usedPercentFromUsage(usage) {
  try {
    const payload = usage && typeof usage === "object" ? usage.data || usage : null;
    const usageObj = payload && payload.usage ? payload.usage : payload;
    const items = usageObj && Array.isArray(usageObj.items) ? usageObj.items : [];
    const plan =
      items.find((item) => item && item.name === "plan_total_token") ||
      items.find(
        (item) => item && item.name !== "compensation_total_token" && Number(item.limit) > 0
      );
    if (!plan) return null;
    const used = Number(plan.used);
    const limit = Number(plan.limit);
    if (!Number.isFinite(used) || !Number.isFinite(limit) || limit <= 0) return null;
    return Math.round((used / limit) * 100);
  } catch (_) {
    return null;
  }
}

async function readCookieLine() {
  const cookies = await chrome.cookies.getAll({ url: COOKIE_URL });
  const line = (cookies || [])
    .map((c) => String(c.name) + "=" + String(c.value))
    .filter((part) => part.includes("="))
    .join("; ");
  if (!line) {
    const err = new Error("cookie_empty");
    throw err;
  }
  return line;
}

async function fetchJson(url) {
  // Host permission lets the worker include HttpOnly cookies; do not set Cookie manually.
  const res = await fetch(url, {
    method: "GET",
    headers: { Accept: "application/json" },
    credentials: "include",
  });
  if (!res.ok) {
    throw new Error("api_" + res.status);
  }
  return res.json();
}

async function postToSticky(payload) {
  let res;
  try {
    res = await fetch(STICKY_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
  } catch (_) {
    throw new Error("sticky_unreachable");
  }
  if (res.status >= 200 && res.status < 300) {
    return res;
  }
  let reason = "sticky_status_" + res.status;
  try {
    const parsed = await res.json();
    if (parsed && parsed.error === "ingest_failed") {
      reason = "ingest_failed";
    }
  } catch (_) {}
  throw new Error(reason);
}

async function syncOnce() {
  const now = Date.now();
  if (now - lastSentAt < 5000) {
    return { skipped: true };
  }
  lastSentAt = now;

  const cookie = await readCookieLine();
  const [usage, current] = await Promise.all([
    fetchJson(USAGE_URL, cookie),
    fetchJson(CURRENT_URL, cookie),
  ]);
  // Cookie and body are sent to Sticky only. Never log them.
  const res = await postToSticky({ cookie, usage, current });
  return {
    ok: true,
    status: res.status,
    usedPercent: usedPercentFromUsage(usage),
  };
}

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (!message || message.type !== "sticky-mimo-sync") {
    return;
  }
  syncOnce()
    .then((result) => sendResponse(result))
    .catch((error) => {
      const reason =
        error && error.message ? String(error.message) : "sticky_unreachable";
      sendResponse({ ok: false, reason });
    });
  return true;
});
