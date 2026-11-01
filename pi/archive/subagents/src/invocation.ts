import { existsSync } from "node:fs";
import { basename } from "node:path";

// Set in every subagent's environment; the extension stays out of a child, so
// a subagent can never spawn subagents of its own.
export const CHILD_ENV = "PI_SUBAGENT";

const CHILD_PREAMBLE = `You are a subagent: another agent delegated one task to you and is waiting for the result.
Work only on that task. Nobody can answer questions, so make reasonable assumptions and state them.
Your last message is returned to the delegating agent verbatim, and it has not seen your work:
make it self-contained, lead with the answer, and cite files as path:line.`;

export interface ChildSpec {
  model: string;
  task: string;
  tools: readonly string[];
  // A local, tool-less run skips skills, context files and extensions so a
  // small model is not handed tens of thousands of tokens it cannot use.
  lean: boolean;
  profilePrompt?: string;
}

// The pi command a child runs, as argv: the same runtime and script as this pi
// when they can be found, `pi` from PATH otherwise.
export function piCommand(argv = process.argv, execPath = process.execPath): string[] {
  const script = argv[1];
  if (script && !script.startsWith("/$bunfs/") && existsSync(script)) return [execPath, script];
  if (!/^(node|bun)(\.exe)?$/i.test(basename(execPath))) return [execPath];
  return ["pi"];
}

export function childArgs(spec: ChildSpec): string[] {
  const args = ["--mode", "json", "-p", "--no-session", "--model", spec.model];
  if (spec.tools.length) args.push("--tools", spec.tools.join(","));
  else args.push("--no-tools");
  if (spec.lean) args.push("--no-skills", "--no-context-files", "--no-prompt-templates", "--no-extensions");
  const prompt = spec.profilePrompt ? `${CHILD_PREAMBLE}\n\n${spec.profilePrompt}` : CHILD_PREAMBLE;
  args.push("--append-system-prompt", prompt);
  // A task starting with "-" or "@" would be read as a flag or a file reference.
  args.push(`Task:\n${spec.task}`);
  return args;
}

export function shellQuote(arg: string): string {
  return `'${arg.replace(/'/g, `'\\''`)}'`;
}

// One shell line for the terminal manager, which runs commands under bash -c.
// exec makes the pid the child pi itself, so stopping it needs no shell in between.
export function shellLine(command: string[], args: string[]): string {
  return `${CHILD_ENV}=1 exec ${[...command, ...args].map(shellQuote).join(" ")}`;
}
