// Whether a task fits a local model's context window. Ollama does not reject an
// oversized prompt: it drops the start, system prompt first, and the model
// answers from whatever is left. So it is refused before it is sent.

// Pi's own prompt in a lean, tool-less run, with headroom (measured at ~950).
export const LEAN_PROMPT_TOKENS = 1500;
// Prose runs ~4 bytes per token and code ~3.5; 3 errs toward refusing.
const BYTES_PER_TOKEN = 3;

export function estimateTokens(text: string): number {
  return Math.ceil(Buffer.byteLength(text) / BYTES_PER_TOKEN);
}

export interface Window {
  contextWindow: number;
  maxTokens: number;
}

// Why `task` will not fit `model`, or undefined when it will.
export function oversizedTask(model: string, task: string, window: Window): string | undefined {
  const room = window.contextWindow - window.maxTokens - LEAN_PROMPT_TOKENS;
  const need = estimateTokens(task);
  if (need <= room) return undefined;
  return (
    `the task is about ${need} tokens, and ${model} has room for about ${Math.max(0, room)} ` +
    `(a ${window.contextWindow}-token window, less ${window.maxTokens} for its answer and ${LEAN_PROMPT_TOKENS} for pi's prompt). ` +
    `Use a cloud model from the list, or shorten the task.`
  );
}
