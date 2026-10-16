// ==UserScript==
// @name         Sticky Mimo Usage
// @namespace    local.sticky.note
// @version      1.0.0
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
*/

(function () {
  "use strict";

  const STICKY_URL = "http://127.0.0.1:17321/mimo-usage";
  const USAGE_URL = "https://platform.xiaomimimo.com/api/v1/tokenPlan/usage";
  const CURRENT_URL = "https://platform.xiaomimimo.com/api/v1/tokenPlan/current";

  let lastSentAt = 0;

  function postToSticky(payload) {
    return new Promise((resolve, reject) => {
      GM_xmlhttpRequest({
        method: "POST",
        url: STICKY_URL,
        headers: { "Content-Type": "application/json" },
        data: JSON.stringify(payload),
        onload: (res) => {
          if (res.status >= 200 && res.status < 300) resolve(res);
          else reject(new Error("sticky_status_" + res.status));
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
            reject(error);
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

  async function syncOnce() {
    const now = Date.now();
    if (now - lastSentAt < 5000) return;
    lastSentAt = now;

    const [usage, current, cookie] = await Promise.all([
      fetchJson(USAGE_URL),
      fetchJson(CURRENT_URL),
      readCookies(),
    ]);

    // Cookie is sent to Sticky only. Do not log it.
    await postToSticky({ cookie, usage, current });
  }

  function arm() {
    syncOnce().catch(() => {
      // Sticky may be closed; keep quiet.
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
