"use strict";

/**
 * Page-console handoff logs for Sticky. DevTools filter: [StickyMimo]
 * Cookie values and POST bodies are never logged.
 */

const LOG_TAG = "[StickyMimo]";
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

function arm() {
  chrome.runtime.sendMessage({ type: "sticky-mimo-sync" }, (result) => {
    if (chrome.runtime.lastError) {
      logFail("sticky_unreachable");
      return;
    }
    if (!result || result.skipped) return;
    if (result.ok) {
      logOk(result.status, result.usedPercent);
      return;
    }
    logFail(result.reason || "sticky_unreachable");
  });
}

arm();
setInterval(arm, 60 * 1000);

const origFetch = window.fetch;
if (typeof origFetch === "function") {
  window.fetch = async function () {
    const response = await origFetch.apply(this, arguments);
    try {
      const url = String(
        arguments[0] && arguments[0].url ? arguments[0].url : arguments[0]
      );
      if (
        url.includes("/api/v1/tokenPlan/usage") ||
        url.includes("/api/v1/tokenPlan/current")
      ) {
        setTimeout(arm, 300);
      }
    } catch (_) {}
    return response;
  };
}
