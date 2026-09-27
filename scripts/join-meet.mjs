#!/usr/bin/env node
/**
 * join-meet.mjs — open Chrome to a Meet link, click through join prompts,
 * prefer Meet mic=meet-mouth-mic and speakers=meet-ears.
 *
 * Usage:
 *   node scripts/join-meet.mjs <meet-url>
 *   MEET_URL=... MEET_BRIDGE_EMAIL=... node scripts/join-meet.mjs
 *
 * Does NOT ship Chrome profiles. Uses ~/.config/meet-bridge/chrome-profile
 * (or config.json chromeUserDataDir). If Google sign-in wall appears, exits
 * with a clear blocker message rather than inventing success.
 */
import { chromium } from "playwright";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");
const CONFIG_DIR = process.env.MEET_BRIDGE_CONFIG_DIR || path.join(os.homedir(), ".config", "meet-bridge");

const MOUTH_MIC = "meet-mouth-mic";
const EARS_SINK = "meet-ears";
const EARS_MIC = "meet-ears-mic"; // Grok Settings only — NOT Meet mic

function loadConfig() {
  const candidates = [
    path.join(CONFIG_DIR, "config.json"),
    path.join(ROOT, "config.json"),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) {
      try {
        return { ...JSON.parse(fs.readFileSync(p, "utf8")), _path: p };
      } catch {
        /* ignore */
      }
    }
  }
  return {};
}

function resolveEmail(cfg) {
  if (process.env.MEET_BRIDGE_EMAIL) return process.env.MEET_BRIDGE_EMAIL.trim();
  const emailFile = path.join(CONFIG_DIR, "email");
  if (fs.existsSync(emailFile)) return fs.readFileSync(emailFile, "utf8").trim();
  if (cfg.email) return String(cfg.email).trim();
  return "";
}

function resolveMeetUrl() {
  const arg = process.argv.slice(2).find((a) => !a.startsWith("-"));
  if (arg) return arg;
  if (process.env.MEET_URL) return process.env.MEET_URL.trim();
  const cfg = loadConfig();
  if (cfg.meetUrl) return String(cfg.meetUrl).trim();
  return "";
}

function findChrome() {
  const candidates = [
    process.env.CHROME_PATH,
    "/usr/bin/google-chrome-stable",
    "/usr/bin/google-chrome",
    "/usr/bin/chromium",
    "/usr/bin/chromium-browser",
    "/snap/bin/chromium",
  ].filter(Boolean);
  for (const c of candidates) {
    if (fs.existsSync(c)) return c;
  }
  return null;
}

function log(msg) {
  console.log(`[join-meet] ${msg}`);
}

function warn(msg) {
  console.error(`[join-meet] WARN: ${msg}`);
}

function meterPeak(source, secs = 2) {
  // Best-effort duplex check via repo lib helpers if available
  const selftestHelper = path.join(ROOT, "lib.sh");
  if (!fs.existsSync(selftestHelper)) return null;
  const script = `
    source "${selftestHelper}"
    meter_source "${source}" ${secs}
  `;
  const r = spawnSync("bash", ["-c", script], { encoding: "utf8", timeout: 15000 });
  if (r.status !== 0) return null;
  const line = (r.stdout || "").trim().split("\n").pop();
  const n = Number(line);
  return Number.isFinite(n) ? n : null;
}

async function dismissBanners(page) {
  const dismissTexts = [
    "Got it",
    "Dismiss",
    "Not now",
    "No thanks",
    "Continue",
    "I understand",
    "Accept all",
  ];
  for (const t of dismissTexts) {
    try {
      const btn = page.getByRole("button", { name: new RegExp(`^${t}$`, "i") });
      if (await btn.count()) {
        await btn.first().click({ timeout: 1500 }).catch(() => {});
        await page.waitForTimeout(400);
      }
    } catch {
      /* ignore */
    }
  }
}

async function trySetDevices(page) {
  // Meet device picker UX changes often. Best-effort clicks + logging.
  log(`target Meet mic=${MOUTH_MIC} speakers=${EARS_SINK} (Grok mic stays ${EARS_MIC})`);

  // Open settings / more options if present
  const settingsSelectors = [
    'button[aria-label*="More options" i]',
    'button[aria-label*="Settings" i]',
    'button[aria-label*="Audio" i]',
  ];
  for (const sel of settingsSelectors) {
    try {
      const el = page.locator(sel).first();
      if (await el.count()) {
        await el.click({ timeout: 2000 }).catch(() => {});
        await page.waitForTimeout(500);
      }
    } catch {
      /* ignore */
    }
  }

  // Try select options that match device names
  for (const label of [MOUTH_MIC, EARS_SINK]) {
    try {
      const opt = page.getByText(label, { exact: false }).first();
      if (await opt.count()) {
        await opt.click({ timeout: 2000 }).catch(() => {});
        log(`clicked device option matching "${label}"`);
        await page.waitForTimeout(300);
      }
    } catch {
      /* ignore */
    }
  }

  // Fallback: ask user/bot to confirm in UI
  log("device selection is best-effort; verify in Meet UI before claiming duplex success");
}

async function tryJoin(page) {
  await dismissBanners(page);

  // Camera/mic permission prompts are browser-level; launched with fake/use real flags below.
  const joinPatterns = [
    /^Join now$/i,
    /^Ask to join$/i,
    /^Join$/i,
    /^Switch here$/i,
    /^Continue$/i,
  ];
  for (const re of joinPatterns) {
    try {
      const btn = page.getByRole("button", { name: re });
      if (await btn.count()) {
        await btn.first().click({ timeout: 3000 });
        log(`clicked join control matching ${re}`);
        await page.waitForTimeout(1500);
        return true;
      }
    } catch {
      /* ignore */
    }
  }
  // Text fallbacks
  for (const t of ["Join now", "Ask to join", "Join"]) {
    try {
      const el = page.getByText(t, { exact: true }).first();
      if (await el.count()) {
        await el.click({ timeout: 3000 });
        log(`clicked text "${t}"`);
        await page.waitForTimeout(1500);
        return true;
      }
    } catch {
      /* ignore */
    }
  }
  return false;
}

async function detectSignInWall(page) {
  const url = page.url();
  if (/accounts\.google\.com/i.test(url)) return "redirected to accounts.google.com";
  const body = ((await page.locator("body").innerText().catch(() => "")) || "").slice(0, 4000);
  if (/Sign in/i.test(body) && /Google/i.test(body)) return "Sign in wall visible in page text";
  if (/Use your Google Account/i.test(body)) return "Google account chooser / sign-in";
  if (/Couldn't sign you in|verify it.?s you/i.test(body)) return "Google verification challenge";
  return null;
}

async function detectInCall(page) {
  const body = ((await page.locator("body").innerText().catch(() => "")) || "").slice(0, 8000);
  const leave = page.getByRole("button", { name: /Leave call|Leave meeting|Hang up/i });
  if (await leave.count()) return true;
  if (/You.+in the meeting|Meeting details|People/i.test(body) && /Leave/i.test(body)) return true;
  return false;
}

async function main() {
  const cfg = loadConfig();
  const email = resolveEmail(cfg);
  const meetUrl = resolveMeetUrl();
  const userDataDir =
    process.env.MEET_BRIDGE_CHROME_DIR ||
    cfg.chromeUserDataDir ||
    path.join(CONFIG_DIR, "chrome-profile");

  if (!meetUrl) {
    console.error("usage: node scripts/join-meet.mjs <https://meet.google.com/...>");
    console.error("   or: MEET_URL=... node scripts/join-meet.mjs");
    process.exit(2);
  }
  if (!/^https:\/\/meet\.google\.com\//i.test(meetUrl)) {
    warn(`URL does not look like a Meet link: ${meetUrl}`);
  }

  fs.mkdirSync(userDataDir, { recursive: true });
  log(`email=${email || "(none stored — sign-in may be required)"}`);
  log(`chrome user-data-dir=${userDataDir}`);
  log(`meetUrl=${meetUrl}`);

  const chromePath = findChrome();
  const launchOpts = {
    headless: process.env.MEET_HEADLESS === "1",
    args: [
      "--use-fake-ui-for-media-stream", // auto-allow mic/cam prompts
      "--autoplay-policy=no-user-gesture-required",
      "--disable-features=TranslateUI",
      `--alsa-output-device=${EARS_SINK}`, // hint only; Meet still picks in-UI
    ],
    ignoreDefaultArgs: ["--enable-automation"],
    viewport: { width: 1280, height: 800 },
  };
  if (chromePath) {
    launchOpts.executablePath = chromePath;
    log(`using browser: ${chromePath}`);
  } else {
    log("system Chrome not found; using Playwright Chromium");
  }

  const context = await chromium.launchPersistentContext(userDataDir, launchOpts);
  const page = context.pages()[0] || (await context.newPage());

  // Grant permissions in Playwright layer too
  await context.grantPermissions(["microphone", "camera"], { origin: "https://meet.google.com" });

  log("navigating...");
  await page.goto(meetUrl, { waitUntil: "domcontentloaded", timeout: 60000 });
  await page.waitForTimeout(2500);

  let blocker = await detectSignInWall(page);
  if (blocker) {
    log(`BLOCKER: ${blocker}`);
    log("ACTION: launch once interactively to sign in:");
    log(`  google-chrome --user-data-dir="${userDataDir}"`);
    log(`  then re-run: node scripts/join-meet.mjs "${meetUrl}"`);
    if (email) log(`  sign in as ${email}`);
    await context.close().catch(() => {});
    process.exit(3);
  }

  await dismissBanners(page);
  await trySetDevices(page);
  const joinedClick = await tryJoin(page);
  await page.waitForTimeout(3000);
  blocker = await detectSignInWall(page);
  if (blocker) {
    log(`BLOCKER after join attempt: ${blocker}`);
    await context.close().catch(() => {});
    process.exit(3);
  }

  const inCall = await detectInCall(page);
  if (!inCall) {
    log("STATUS: not clearly in-call yet (pre-join lobby, waiting room, or UI changed)");
    log(`joinClick=${joinedClick}`);
    // Keep browser open briefly for operator unless MEET_CLOSE=1
    if (process.env.MEET_CLOSE === "1") {
      await context.close().catch(() => {});
    } else {
      log("leaving browser open (set MEET_CLOSE=1 to close). Ctrl+C to stop.");
      await new Promise(() => {});
    }
    process.exit(4);
  }

  log("STATUS: appears in-call");
  // Duplex smoke against virtual devices (Meet up)
  const mouth = meterPeak(MOUTH_MIC, 2);
  const ears = meterPeak(EARS_MIC, 2);
  if (mouth != null) log(`meter ${MOUTH_MIC} peak=${mouth}`);
  if (ears != null) log(`meter ${EARS_MIC} peak=${ears}`);
  log("VERIFY manually: remote participant hears Grok; Grok hears room via meet-ears-mic");
  log("SUCCESS: joined Meet (do not claim remote duplex without remote-hear confirmation)");

  if (process.env.MEET_CLOSE === "1") {
    await context.close().catch(() => {});
  } else {
    log("leaving browser open (set MEET_CLOSE=1 to close). Ctrl+C to stop.");
    await new Promise(() => {});
  }
}

main().catch((err) => {
  console.error("[join-meet] FATAL:", err);
  process.exit(1);
});
