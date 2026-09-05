import assert from "node:assert/strict";
import { test } from "node:test";
import {
  APP_OPEN_ERROR,
  getDockSwitcherURL,
  requestDockSwitcher,
} from "../src/utils.ts";

test("only the four supported app actions produce URLs", () => {
  for (const action of ["enable", "disable", "mapping", "settings"]) {
    assert.equal(getDockSwitcherURL(action), `dockswitcher://${action}`);
  }
});

test("rejects unknown actions and URL additions before opening anything", async () => {
  for (const action of [
    "",
    "install",
    "quit",
    "__proto__",
    "constructor",
    "enable?force=true",
    "enable/path",
    "enable#fragment",
    "https://example.com",
  ]) {
    let opened = false;
    await assert.rejects(
      requestDockSwitcher(action, async () => {
        opened = true;
      }),
      /Unsupported Dock Switcher action/,
    );
    assert.equal(opened, false);
  }
});

test("forwards one exact URL and waits for the opener to finish", async () => {
  const calls = [];
  let finishOpening;
  let settled = false;
  const request = requestDockSwitcher("enable", async (url) => {
    calls.push(url);
    await new Promise((resolve) => {
      finishOpening = resolve;
    });
  }).then(() => {
    settled = true;
  });
  await Promise.resolve();
  assert.equal(settled, false);
  assert.deepEqual(calls, ["dockswitcher://enable"]);
  finishOpening();
  await request;
  assert.equal(settled, true);
});

test("disable requests do not quit the app or invoke additional actions", async () => {
  const calls = [];
  await requestDockSwitcher("disable", async (url) => {
    calls.push(url);
  });
  assert.deepEqual(calls, ["dockswitcher://disable"]);
});

test("opening failures provide installation guidance without raw system output", async () => {
  for (const failure of [
    new Error("No application handles this URL"),
    undefined,
  ]) {
    await assert.rejects(
      requestDockSwitcher("mapping", async () => {
        throw failure;
      }),
      { message: APP_OPEN_ERROR },
    );
  }
});
