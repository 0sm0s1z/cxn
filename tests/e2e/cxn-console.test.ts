import { afterEach, expect, test } from "bun:test";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { FX_BIN } from "../evals/eval-helpers";
import { TmuxSession, tmuxAvailable } from "./tmux-helpers";

let session: TmuxSession | undefined;
let directory: string | undefined;
afterEach(async () => {
  await session?.kill();
  session = undefined;
  if (directory) rmSync(directory, { recursive: true, force: true });
  directory = undefined;
});

test.skipIf(!tmuxAvailable())("cxn console handles batched typing, redraw, paste, scrolling, resize and clean exit", async () => {
  directory = mkdtempSync(join(tmpdir(), "cxn-console-"));
  const stderrPath = join(directory, "stderr");
  session = await TmuxSession.create({
    cmd: `${JSON.stringify(FX_BIN)} cxn`,
    width: 60,
    height: 16,
    stderrPath,
    isolated: true,
  });
  await session.waitForText("local demo, not connected");
  session.sendLiteralImmediate("ihello world");
  await session.waitForText("[INSERT] hello world");
  await session.sendKeys("BSpace BSpace BSpace BSpace BSpace");
  const shortened = await session.capturePane();
  expect(shortened).toContain("[INSERT] hello ▌");
  expect(shortened).not.toContain("world");
  await session.sendKeys("Enter");
  await session.waitForText("[you] hello");
  expect(await session.capturePane()).not.toContain("[INSERT]");

  // A bracketed multiline paste must not accidentally submit its contents.
  session.sendLiteralImmediate("i\x1b[200~café\n界\x1b[201~");
  await session.waitForText("[INSERT] café 界");
  await session.sendKeys("Enter");
  await session.waitForText("[you] café 界");

  for (let i = 0; i < 8; i++) {
    session.sendLiteralImmediate(`imessage-${i}\r`);
    await session.waitForText(`[you] message-${i}`);
  }
  await session.resizeWindow(40, 10);
  await session.waitForText("message-7");
  const narrow = await session.capturePaneGrid();
  expect(narrow).toHaveLength(10);
  expect(narrow.filter((line) => line.includes("Composer"))).toHaveLength(1);
  expect(narrow.filter((line) => line.includes("NORMAL |"))).toHaveLength(1);
  await session.resizeWindow(100, 30);
  await session.waitForText("local demo, not connected");
  await session.sendKeys("q");
  expect(await session.waitForSessionEnd()).toBe(true);
  expect(session.paneStatus().status).toBe(0);
  expect(readFileSync(stderrPath, "utf8")).toBe("");
}, 30_000);

test.skipIf(!tmuxAvailable())("large and multiline pastes keep the draft tail visible and the console responsive", async () => {
  directory = mkdtempSync(join(tmpdir(), "cxn-console-large-"));
  const stderrPath = join(directory, "stderr");
  session = await TmuxSession.create({
    cmd: `${JSON.stringify(FX_BIN)} cxn`,
    width: 60,
    height: 16,
    stderrPath,
    isolated: true,
  });
  await session.waitForText("local demo, not connected");
  await session.sendKeys("i");
  await session.pasteText(`${"x".repeat(60_000)}TAIL_SENTINEL`);
  await session.waitForText("TAIL_SENTINEL▌", 3_000);
  await session.pasteText(`${"\n".repeat(100)}MULTILINE_TAIL`);
  await session.waitForText("MULTILINE_TAIL▌", 3_000);
  await session.sendKeys("C-c");
  expect(await session.waitForSessionEnd()).toBe(true);
  expect(session.paneStatus().status).toBe(0);
  expect(readFileSync(stderrPath, "utf8")).toBe("");
}, 15_000);
