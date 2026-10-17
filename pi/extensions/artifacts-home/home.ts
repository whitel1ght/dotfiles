// pi-artifacts writes to <cwd>/.pi/artifacts with no setting to change it. This makes that path
// a link into ~/artifacts/pi/<project>, so every pi artifact lands beside the Claude ones and is
// backed up with them (local.artifacts-sync).
import { existsSync, lstatSync, mkdirSync, readdirSync, readlinkSync, renameSync, rmdirSync, symlinkSync } from "node:fs";
import { homedir } from "node:os";
import { join, relative, resolve, sep } from "node:path";

export function slugFor(cwd: string, home = homedir()): string {
  const rel = relative(home, cwd);
  const parts = (rel.startsWith("..") ? resolve(cwd) : rel).split(sep).filter(Boolean);
  return parts.join("-") || "home";
}

export type Result = { action: "linked" | "ok" | "skipped"; link: string; target: string; moved: string[]; reason?: string };

export function ensureLink(cwd: string, store = join(homedir(), "artifacts"), home = homedir()): Result {
  const link = join(cwd, ".pi", "artifacts");
  const target = join(store, "pi", slugFor(cwd, home));
  const done = (action: Result["action"], moved: string[] = [], reason?: string): Result => ({ action, link, target, moved, reason });

  const inStore = relative(resolve(store), resolve(cwd));
  if (!inStore.startsWith("..")) return done("skipped", [], "the working directory is inside the artifacts store");

  let stat;
  try {
    stat = lstatSync(link);
  } catch {
    stat = null;
  }
  if (stat?.isSymbolicLink()) {
    return readlinkSync(link) === target ? done("ok") : done("skipped", [], `${link} already links elsewhere`);
  }

  mkdirSync(target, { recursive: true });
  const moved: string[] = [];
  if (stat?.isDirectory()) {
    const names = readdirSync(link);
    const clash = names.find((n) => existsSync(join(target, n)));
    if (clash) return done("skipped", [], `${clash} is already in ${target}; move it by hand`);
    for (const n of names) {
      renameSync(join(link, n), join(target, n));
      moved.push(n);
    }
    rmdirSync(link);
  } else if (stat) {
    return done("skipped", [], `${link} is a file`);
  }
  mkdirSync(join(cwd, ".pi"), { recursive: true });
  symlinkSync(target, link);
  return done("linked", moved);
}
