# Verified UI facts (shared reference)

Facts about the pinned frontend stack that several review rounds were spent re-discovering.
Loaded by `vuetify-expert` and `accessibility-expert`; cite the row, then **re-verify against
`node_modules` when the pinned version changes** — every row names how it was checked.

Versions these were verified against: **Vuetify 3.12.1**, Vue 3.5.x, ecfx-dashboard as of
2026-09-11. If `package.json` pins something newer, re-run the check before relying on the row.

| # | Fact | How verified | Why it matters |
|---|---|---|---|
| 1 | `v-alert` hardcodes `role="alert"` on its root; it is not prop-driven. `role="presentation"` passed as a fallthrough attribute overrides it. | `lib/components/VAlert/VAlert.js` (root vnode props); asserted in a mounted test | `role="alert"` is `aria-live="assertive"`. Any text you also announce through a polite region is read twice, the second time interrupting. Set `role="presentation"` on the alert, or drop the region. |
| 2 | `VMessages` (the field validation/hint text) carries **no** `role` and **no** `aria-live`. | `lib/components/VMessages/VMessages.js` | Validation text linked by `aria-describedby` is read on focus **arrival**, not on change. A paste into an already-focused field with a rule failure is silent for AT unless you announce it yourself. |
| 3 | The bare `append-icon` / `prepend-icon` props render `<i aria-hidden="true">` with no `tabindex`, `role` or name. Zero focusable nodes. | mounted `VTextField`, queried `.v-input__append` | An icon that is the only route to an action is a WCAG 2.1.1 barrier. Use a real `<v-btn icon>` in `#append-inner` with a `t()`-sourced `aria-label`. |
| 4 | `VBtn :loading="true"` does **not** set `disabled`; it sets `tabindex="-1"` and `aria-busy="true"`. | `lib/components/VBtn/VBtn.js` | The button leaves the tab order while loading; focus already on it survives, but a user cannot Tab back to it. Restore focus explicitly when the request settles. |
| 5 | Vuetify ships **no** `pointer-events` rule for readonly inputs. The project's own `src/styles/dashboard/_inputs.scss` sets `.v-input--readonly { pointer-events: none }`, and `readonly` on a `v-text-field` puts that class on the **root wrapper**, which contains `#append-inner`. | grep of `node_modules/vuetify/lib/**/*.css` (no hit); grep of `src/styles` (hit); reproduced with Playwright (`getComputedStyle(btn).pointerEvents === 'none'`, keyboard Enter still worked) | A readonly text field with an interactive affix becomes mouse-inert while remaining keyboard-operable — the worst kind of intermittent bug. Never combine `:readonly` with an interactive affix in this repo; use `aria-readonly` plus input guards. |
| 6 | A `readonly` `<input>` fires no `input` event and blocks paste at the default action; `keydown` still fires. | browser behaviour (Chromium 151); jsdom does **not** model this | Guards that rely on `@input` or `@paste` on a readonly field cannot be unit-tested for the property they guard; say "manual-verify" at the code. |
| 7 | Vue's `:key` change is an unmount/mount, and Vue attaches text children before insertion. | `isSameVNodeType` compares type and key; observed DOM | A `role="status"` region re-keyed to force re-announcement enters the tree already populated — the case NVDA/Chrome and VoiceOver/Safari commonly do not announce. Re-announce by content (clear, then set on `nextTick`), never by remount. |
| 8 | Hidden-tab timers are throttled to roughly one tick per minute in Chromium and Firefox. | browser behaviour; reproduced by leaving the tab | Any countdown that counts `setInterval` ticks lies after the user switches to their authenticator app. Anchor to wall-clock (`Date.now()` at response arrival) and re-read on `visibilitychange`. |
| 9 | `unplugin-vue-router` routes in this repo are the file paths (`/Dashboard/CredentialsSafe`), but navigation targets in `drawer.ts` are the human URLs (`/provider-credentials`). | `src/typed-router.d.ts` vs `src/utils/drawer.ts` | A direct navigation to the typed-router path renders blank and redirects; use the drawer's path when driving the app. |
| 10 | Playwright `page.screenshot({ fullPage: true })` on the Vuetify `v-app` layout returns a blank image; viewport screenshots work. | observed | Do not conclude a page is blank from a full-page capture. |

## Live-region and focus invariants (distilled from the same rounds)

1. **One live region per field, always mounted**, outside every `v-if`. Text changes are announced;
   nodes created with text are not.
2. **Re-announce by content, not by remount.** Clear to `''`, then set on `nextTick` (a ~150 ms gap
   for real AT). A boolean latch announces once per session; a counter in a `:key` announces never.
3. **Never carry the same text in two channels.** If a `v-alert` shows it, the polite region does
   not (or the alert is `role="presentation"`).
4. **Composed, not replaced.** When two sources (a field hint and a panel) share the region, a
   transition announces both; a higher-priority latch must release once the other source has
   something substantive to say.
5. **Restore focus only when the focused node went away.** Check `previouslyFocused.isConnected`
   after the request settles, then move to the nearest stable landmark. Moving focus while the node
   survives is WCAG 3.2.5.
6. **Announce the thing the user must act on.** A code the user has to transcribe belongs in the
   announcement (spaced digits), once the value no longer changes underneath them.
7. **A visible countdown hidden from AT needs a static substitute** ("This code changes every 30
   seconds"), read once.
