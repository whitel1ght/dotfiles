import { StringEnum } from "@earendil-works/pi-ai";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { readNote, SCOPES, searchWiki } from "./src/qmd.ts";

const text = (value: string) => ({ type: "text" as const, text: value });

// Two plain tools over qmd for the local-model profile (pigm), which runs
// without context files and so does not know the qmd commands. See README.md.
export default function (pi: ExtensionAPI) {
  pi.registerTool({
    name: "wiki_search",
    label: "Wiki search",
    description:
      "Search the user's personal wiki (notes, diary, project logs, reviews) and their saved web articles by meaning. " +
      "Use it whenever the user asks about something they wrote, saved, read, decided or did before. " +
      "Returns up to 5 results with a qmd:// path and a snippet.",
    parameters: Type.Object({
      query: Type.String({ description: "What to look for, in plain words" }),
      scope: Type.Optional(
        StringEnum(SCOPES, { description: "all (default), notes, diary, projects, or articles (saved web articles only)" }),
      ),
    }),
    async execute(_id, params, signal) {
      return { content: [text(await searchWiki(params.query, params.scope ?? "all", { signal }))], details: undefined };
    },
  });

  pi.registerTool({
    name: "wiki_read",
    label: "Wiki read",
    description: "Read a note or saved article found by wiki_search, by its qmd:// path. Returns up to 200 lines.",
    parameters: Type.Object({
      path: Type.String({ description: "The qmd:// path from a wiki_search result" }),
      from: Type.Optional(Type.Number({ description: "First line to read (default 1)" })),
    }),
    async execute(_id, params, signal) {
      return { content: [text(await readNote(params.path, { from: params.from, signal }))], details: undefined };
    },
  });
}
