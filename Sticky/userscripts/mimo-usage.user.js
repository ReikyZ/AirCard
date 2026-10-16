// ==UserScript==
// @name         Sticky Mimo Usage
// @namespace    local.sticky.note
// @version      1.1.0
// @description  Push Mimo token-plan usage and cookies to Sticky on localhost.
// @author       Sticky
// @match        https://platform.xiaomimimo.com/console/plan-manage*
// @grant        GM_xmlhttpRequest
// @grant        GM_cookie
// @connect      127.0.0.1
// @run-at       document-idle
// ==/UserScript==

/*
  Tampermonkey cookie permission:
  This script uses GM_cookie so it can read HttpOnly cookies for
  platform.xiaomimimo.com. In Tampermonkey, open the script editor →
  Settings (or the script's access prompts) and allow cookie access
  for this userscript / domain when asked. Without that grant,
  HttpOnly session cookies are not visible to the script.

  Sticky listens on http://127.0.0.1:17321/mimo-usage (Sticky.app must be running).

  DevTools filter: [StickyMimo]
*/

(function () {
  "use strict";

  const STICKY_URL = "http://127.0.0.1:17321/mimo-usage";
  const USAGE_URL = "https://platform.xiaomimimo.com/api/v1/tokenPlan/usage";
  const CURRENT_URL = "https://platform.xiaomimimo.com/api/v1/tokenPlan/current";
  const LOG_TAG = "[StickyMimo]";

  let lastSentAt = 0;
  let lastLogKey = "";

  function logOk(status, usedPercent) {
    const key =
      "ok:" +
      String(status) +
      (typeof usedPercent === "number" && Number.isFinite(usedPercent)
        ? ":" + String(usedPercent)
        : "");
    if (key === lastLogKey) return;
    lastLogKey = key;
    if (typeof usedPercent === "number" && Number.isFinite(usedPercent)) {
      console.info(LOG_TAG, "ok", status, usedPercent);
    } else {
      console.info(LOG_TAG, "ok", status);
    }
  }

  function logFail(reason) {
    const short = String(reason || "fail");
    const key = "fail:" + short;
    if (key === lastLogKey) return;
    lastLogKey = key;
    console.warn(LOG_TAG, "fail", short);
  }

  function usedPercentFromUsage(usage) {
    try {
      const payload = usage && typeof usage === "object" ? usage.data || usage : null;
      const usageObj = payload && payload.usage ? payload.usage : payload;
      const items = usageObj && Array.isArray(usageObj.items) ? usageObj.items : [];
      const plan =
        items.find((item) => item && item.name === "plan_total_token") ||
        items.find((item) => item && item.name !== "compensation_total_token" && Number(item.limit) > 0);
      if (!plan) return null;
      const used = Number(plan.used);
      const limit = Number(plan.limit);
      if (!Number.isFinite(used) || !Number.isFinite(limit) || limit <= 0) return null;
      return Math.round((used / limit) * 100);
    } catch (_) {
      return null;
    }
  }

  function postToSticky(payload) {
    return new Promise((resolve, reject) => {
      GM_xmlhttpRequest({
        method: "POST",
        url: STICKY_URL,
        headers: { "Content-Type": "application/json" },
        data: JSON.stringify(payload),
        onload: (res) => {
          if (res.status >= 200 && res.status < 300) {
            resolve(res);
            return;
          }
          let reason = "sticky_status_" + res.status;
          try {
            const parsed = JSON.parse(String(res.responseText || ""));
            if (parsed && parsed.error === "ingest_failed") {
              reason = "ingest_failed";
            }
          } catch (_) {}
          reject(new Error(reason));
        },
        onerror: () => reject(new Error("sticky_unreachable")),
      });
    });
  }

  function readCookies() {
    return new Promise((resolve, reject) => {
      if (typeof GM_cookie === "undefined" || typeof GM_cookie.list !== "function") {
        reject(new Error("gm_cookie_unavailable"));
        return;
      }
      GM_cookie.list(
        { url: "https://platform.xiaomimimo.com/" },
        (cookies, error) => {
          if (error) {
            reject(new Error("gm_cookie_unavailable"));
            return;
          }
          const list = Array.isArray(cookies) ? cookies : [];
          const line = list
            .map((c) => String(c.name) + "=" + String(c.value))
            .filter((part) => part.includes("="))
            .join("; ");
          if (!line) {
            reject(new Error("cookie_empty"));
            return;
          }
          resolve(line);
        }
      );
    });
  }

  async function fetchJson(url) {
    const res = await fetch(url, {
      method: "GET",
      credentials: "include",
      headers: { Accept: "application/json" },
    });
    if (!res.ok) throw new Error("api_" + res.status);
    return res.json();
  }

  function failReason(error) {
    const known = [
      "cookie_empty",
      "gm_cookie_unavailable",
      "sticky_unreachable",
      "ingest_failed",
    ];
    const message = error && error.message ? String(error.message) : "";
    if (known.indexOf(message) !== -1) return message;
    if (/^api_\d+$/.test(message)) return message;
    if (/^sticky_status_\d+$/.test(message)) return message;
    if (/^api_/.test(message)) return message;
    if (/^sticky_status_/.test(message)) return message;
    return "sticky_unreachable";
  }

  async function syncOnce() {
    const now = Date.now();
    if (now - lastSentAt < 5000) return;
    lastSentAt = now;

    try {
      const [usage, current, cookie] = await Promise.all([
        fetchJson(USAGE_URL),
        fetchJson(CURRENT_URL),
        readCookies(),
      ]);

      // Cookie is sent to Sticky only. Do not log it or the POST body.
      const res = await postToSticky({ cookie, usage, current });
      logOk(res.status, usedPercentFromUsage(usage));
    } catch (error) {
      logFail(failReason(error));
    }
  }

  function arm() {
    syncOnce().catch(() => {
      // Keep quiet toward the page UI; console already has [StickyMimo] lines.
    });
  }

  arm();
  setInterval(arm, 60 * 1000);

  const origFetch = window.fetch;
  if (typeof origFetch === "function") {
    window.fetch = async function () {
      const response = await origFetch.apply(this, arguments);
      try {
        const url = String(arguments[0] && arguments[0].url ? arguments[0].url : arguments[0]);
        if (url.includes("/api/v1/tokenPlan/usage") || url.includes("/api/v1/tokenPlan/current")) {
          setTimeout(arm, 300);
        }
      } catch (_) {}
      return response;
    };
  }
})();
