// Shows this session's open decisions questions in the pi session as well as in the deck, and
// lets the user answer in either place: an answer typed here goes to the card through the CLI,
// which ends the agent's ask_user wait (the server reads the card every 200 ms); an answer given
// in the deck or Telegram closes what the session shows as soon as the card changes.
//
// pi's question cards carry no session, so the cards are found from the session's own calls:
// wait_for_answer names its id, ask_user its question (matched to the open card asking it).
import { execFile } from "node:child_process";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

export const ASK = "mcp__decisions__ask_user";
export const WAIT = "mcp__decisions__wait_for_answer";
export const WITHDRAW = "mcp__decisions__withdraw";
// a question asked but not on the deck after this long was never filed (refused, or no server)
const FIND_MS = 30_000;

export type Option = { n: number; text: string; recommended: boolean };
export type Question = { id: string; question: string; options: Option[]; questionBack: boolean };

/** The open question cards in `decide list --json` (answer cards left out); anything else is none. */
export function parseQuestions(stdout: string): Question[] {
  let raw: unknown;
  try {
    raw = JSON.parse(stdout);
  } catch {
    return [];
  }
  if (!Array.isArray(raw)) return [];
  const str = (v: unknown) => (typeof v === "string" ? v : "");
  return raw
    .filter((c): c is Record<string, unknown> => typeof c === "object" && c !== null)
    .filter((c) => c.kind !== "answer" && (str(c.status) === "" || c.status === "open") && str(c.id) !== "")
    .map((c) => ({
      id: str(c.id),
      question: str(c.question),
      questionBack: c.question_back === true,
      options: (Array.isArray(c.options) ? c.options : [])
        .filter((o): o is Record<string, unknown> => typeof o === "object" && o !== null)
        .map((o) => ({ n: Number(o.n), text: str(o.text), recommended: o.recommended === true }))
        .filter((o) => Number.isInteger(o.n) && o.n > 0),
    }));
}

/** What a closed card says happened, from `decide show`: the answer's first line, or the status. */
export function outcomeOf(show: string): string {
  const status = /^status:\s*(\S+)/m.exec(show)?.[1] ?? "";
  if (status === "withdrawn") return "withdrawn";
  const answer = /^## Answer\n+([^\n]+)/m.exec(show)?.[1]?.trim();
  if (answer) return answer;
  return status || "closed";
}

/** The `decide` arguments that answer a card: a bare option number picks it, anything else is the user's own words. */
export function answerArgs(q: Question, text: string): string[] {
  const t = text.trim();
  if (/^\d+$/.test(t) && q.options.some((o) => o.n === Number(t))) return ["answer", q.id, t];
  return ["tell", q.id, t];
}

export type Route = { id: string; args: string[]; passThrough?: string };

/**
 * What a message the user typed does while this session has an open question: it answers the
 * newest one. When the agent is blocked waiting on the card, the wait returns the answer and the
 * message goes no further; otherwise the agent gets it too, marked as the answer to that card.
 * A command (`/…`), an empty message or no open question leaves the message alone.
 */
export function routeInput(open: readonly Question[], text: string, waiting: boolean): Route | undefined {
  const t = text.trim();
  const q = open[open.length - 1];
  if (!q || t === "" || t.startsWith("/")) return undefined;
  const args = answerArgs(q, t);
  if (waiting) return { id: q.id, args };
  return { id: q.id, args, passThrough: `(my answer to decisions card ${q.id}, "${q.question}"; it is filed on the card) ${t}` };
}

/** The line above the editor while questions are open. */
export function widgetLine(open: readonly Question[]): string {
  const q = open[open.length - 1];
  if (!q) return "";
  const more = open.length > 1 ? ` (+${open.length - 1} more open)` : "";
  return `✋ ${q.id} is open${more}: type your answer (an option number or your own words), or answer in the deck`;
}

const cutLine = (s: string, n: number) => {
  const one = s.replace(/\s+/g, " ").trim();
  return [...one].length > n ? `${[...one].slice(0, n - 1).join("")}…` : one;
};

/** A transcript line cut to the terminal width (two columns spare for the wide ✋). */
export function fitLine(s: string, width: number): string {
  return cutLine(s, Math.max(10, width - 2));
}

/** The line the session shows when a card closes. */
export function closedLine(id: string, outcome: string, here: boolean): string {
  if (outcome === "withdrawn") return `↩ ${id} withdrawn by the agent`;
  return `✓ ${id} answered ${here ? "here" : "in the deck"}: ${outcome}`;
}

/** The question with its numbered options, as lines; ★ marks the recommended one. */
export function questionLines(q: { id?: string; question: string; options: readonly Option[] }, width = 100): string[] {
  const head = `✋ ${q.id ? `${q.id} · ` : ""}${q.question}`;
  return [
    cutLine(head, width),
    ...q.options.map((o) => `   ${cutLine(`${o.n}) ${o.text}${o.recommended ? " ★" : ""}`, width - 3)}`),
  ];
}

/** The options of an ask_user call's arguments, numbered as the deck will number them. */
export function callOptions(args: unknown): Option[] {
  const a = (args ?? {}) as { options?: unknown; recommended?: unknown };
  const list = Array.isArray(a.options) ? a.options.filter((o): o is string => typeof o === "string") : [];
  return list.map((text, i) => ({ n: i + 1, text, recommended: a.recommended === i + 1 }));
}

/** The queue `decide` uses (bin/decide): DECISIONS_DIR, else the run-day state folder's. */
export function queueDir(env: NodeJS.ProcessEnv = process.env): string {
  return env.DECISIONS_DIR || join(env.RUN_DAY_STATE_DIR || join(homedir(), ".local/state/run-day"), "decisions");
}

/** A card's file, open or filed under done/<day>/ (`decide show` only finds open ones); "" when gone. */
export function readCard(id: string, dir = queueDir()): string {
  const name = `${id}.md`;
  try {
    if (existsSync(join(dir, name))) return readFileSync(join(dir, name), "utf8");
    for (const day of readdirSync(join(dir, "done")).sort().reverse()) {
      const p = join(dir, "done", day, name);
      if (existsSync(p)) return readFileSync(p, "utf8");
    }
  } catch {
    // no done/ folder yet
  }
  return "";
}

/** Runs `decide ARGS`; resolves to its error text, "" on success. */
export function decide(args: readonly string[]): Promise<string> {
  const bin = existsSync(join(homedir(), ".local/bin/decide")) ? join(homedir(), ".local/bin/decide") : "decide";
  return new Promise((resolve) => {
    execFile(bin, [...args], { timeout: 10_000 }, (err, _stdout, stderr) =>
      resolve(err ? String(stderr).trim() || err.message : ""),
    );
  });
}

export type MirrorDeps = {
  list: () => Promise<string>;
  show: (id: string) => Promise<string>;
  now: () => number;
  /** a card this session asked is on the deck: show the question once */
  opened: (q: Question) => void;
  /** the open questions changed: draw them (none clears) */
  render: (open: readonly Question[]) => void;
  /** a card left the deck: `here` when the user answered it in this session */
  closed: (q: Question, outcome: string, here: boolean) => void;
};

export class QuestionMirror {
  private asked = new Map<string, number>(); // question text → when ask_user was called, card not yet found
  private ids = new Set<string>(); // cards this session waits on, found or named
  private open = new Map<string, Question>();
  private here = new Set<string>();
  private shown = "[]";
  private checking = false;
  private again = false;
  private deps: MirrorDeps;

  constructor(deps: MirrorDeps) {
    this.deps = deps;
  }

  /** Something to watch for: ticks only matter while this is true. */
  get active(): boolean {
    return this.asked.size > 0 || this.ids.size > 0;
  }

  get questions(): Question[] {
    return [...this.open.values()];
  }

  onToolCall(toolName: string, input: unknown) {
    const a = (input ?? {}) as { question?: unknown; id?: unknown };
    if (toolName === ASK && typeof a.question === "string" && a.question.trim()) {
      this.asked.set(a.question.trim(), this.deps.now());
    } else if (toolName === WAIT && typeof a.id === "string" && a.id.trim()) {
      this.ids.add(a.id.trim());
    }
  }

  /**
   * The user is answering this card in the session: said before the answer is written, since the
   * queue watch can report the card closed while `decide` still runs; `false` takes it back.
   */
  answeredHere(id: string, yes = true) {
    if (yes) this.here.add(id);
    else this.here.delete(id);
  }

  async tick() {
    if (this.checking) {
      this.again = true;
      return;
    }
    this.checking = true;
    try {
      do {
        this.again = false;
        await this.check();
      } while (this.again);
    } finally {
      this.checking = false;
    }
  }

  private async check() {
    if (!this.active) return;
    const stdout = await this.deps.list();
    if (stdout === "") return; // a failed list says nothing about the cards
    const cards = parseQuestions(stdout);
    const byId = new Map(cards.map((c) => [c.id, c]));

    for (const [text, at] of this.asked) {
      const card = cards.find((c) => c.question.trim() === text);
      if (card) {
        this.ids.add(card.id);
        this.asked.delete(text);
      } else if (this.deps.now() - at > FIND_MS) {
        this.asked.delete(text);
      }
    }

    for (const id of [...this.ids]) {
      const card = byId.get(id);
      if (card) {
        const first = !this.open.has(id);
        this.open.set(id, card);
        if (first) this.deps.opened(card);
        continue;
      }
      this.ids.delete(id);
      const was = this.open.get(id);
      this.open.delete(id);
      if (!was) continue; // named by wait_for_answer but never seen open: nothing was shown
      let outcome = "closed";
      try {
        outcome = outcomeOf(await this.deps.show(id));
      } catch {
        // the card closed either way
      }
      this.deps.closed(was, outcome, this.here.delete(id));
    }

    const key = JSON.stringify(this.questions);
    if (key !== this.shown) {
      this.shown = key;
      this.deps.render(this.questions);
    }
  }
}
