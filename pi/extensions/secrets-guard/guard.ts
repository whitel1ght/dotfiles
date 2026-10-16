// Path-like inputs of pi's file tools (read, edit, write, grep, find, ls).
// Content fields are not paths: writing a note that mentions ~/.secrets is fine.
const PATH_KEY = /path|dir|cwd/i;
const OFF_LIMITS = [/(^|\/)\.secrets(\/|$)/, /(^|\/)\.config\/ecfx\/jira\.env$/];

export function blockReason(toolName: string, input: Record<string, unknown>): string | undefined {
  if (toolName === "bash") return undefined;
  for (const [key, value] of Object.entries(input ?? {})) {
    if (!PATH_KEY.test(key) || typeof value !== "string") continue;
    if (OFF_LIMITS.some((re) => re.test(value))) {
      return "~/.secrets is off limits to agents. Scripts read a value with $(secret NAME).";
    }
  }
  return undefined;
}
