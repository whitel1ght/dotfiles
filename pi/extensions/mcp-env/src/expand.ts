// Pi expands ${VAR} in an MCP server's headers, env and oauth.clientSecret, but
// passes url and oauth.clientId through as written. So a server whose url or
// client id lives in ~/.zshrc.local reaches the provider as a literal
// "${OUTLOOK_MCP_TENANT_ID}". This expands every string up front instead.

export type Env = Record<string, string | undefined>;

export interface Expanded {
  readonly config: unknown;
  // Variables the config names that the environment does not set.
  readonly missing: readonly string[];
}

const VAR = /\$\{([A-Za-z_][A-Za-z0-9_]*)\}/g;

export function expandConfig(value: unknown, env: Env): Expanded {
  const missing = new Set<string>();
  const walk = (v: unknown): unknown => {
    if (typeof v === "string") {
      // A "!command" value is pi's to run; leave it whole.
      if (v.startsWith("!")) return v;
      return v.replace(VAR, (_, name: string) => {
        const resolved = env[name];
        if (!resolved) missing.add(name);
        return resolved ?? "";
      });
    }
    if (Array.isArray(v)) return v.map(walk);
    if (v && typeof v === "object") return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, walk(x)]));
    return v;
  };
  return { config: walk(value), missing: [...missing] };
}

export interface Server {
  readonly name: string;
  readonly config: unknown;
}

export interface Skipped {
  readonly name: string;
  readonly missing: readonly string[];
}

export function expandServers(file: unknown, env: Env): { servers: Server[]; skipped: Skipped[] } {
  if (!file || typeof file !== "object" || !("mcpServers" in file)) throw new Error("expected { \"mcpServers\": { ... } }");
  const entries = (file as { mcpServers: unknown }).mcpServers;
  if (!entries || typeof entries !== "object" || Array.isArray(entries)) throw new Error("mcpServers must be an object");
  const servers: Server[] = [];
  const skipped: Skipped[] = [];
  for (const [name, raw] of Object.entries(entries)) {
    const { config, missing } = expandConfig(raw, env);
    if (missing.length) skipped.push({ name, missing });
    else servers.push({ name, config });
  }
  return { servers, skipped };
}
