export const BG_START = {
  description:
    "Start a shell command as a background terminal and return immediately with its id. " +
    "Use it for anything long-running or open-ended: dev servers, watchers, builds, test suites. " +
    "The process has no stdin, so it can never prompt. You are woken automatically when it finishes, " +
    "so do not poll; keep working, or end your turn if nothing else is left to do.",
  snippet: "bg_start: run a long-running command in the background",
  guidelines: [
    "Use bg_start instead of bash for servers, watchers and long builds, so they do not block the turn.",
    "After bg_start, check on the process with bg_output only when you need its output; you are told when it exits.",
  ],
};

export const BG_LIST = {
  description: "List background terminals with their status, pid, runtime and working directory.",
};

export const BG_OUTPUT = {
  description:
    "Read the recent output of a background terminal (stdout and stderr), without waiting. " +
    "Output is always truncated to the last lines; the full logs are on disk and the result names the files, " +
    "so use the read tool on them when you need more.",
};

export const BG_STOP = {
  description:
    "Stop a background terminal: SIGTERM to its whole process group, escalating to SIGKILL after a few seconds " +
    "(or immediately with force).",
};
