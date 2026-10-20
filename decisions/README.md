# decisions

The /run-day decision queue as a deck of cards (tmux prefix y). Reads and answers only
through `bin/decide`; never touches the decision files itself.

- Build and install: `./install.sh` (rebuilds when `src/`, `Cargo.toml` or `Cargo.lock` change),
  or `cargo build` and run `target/debug/decisions`.
- Tests: `cargo test` (state, drawing, effects, decide calls) and `tests/e2e.sh` (the real
  binary in a pseudo-terminal against the real `decide`, sandboxed).
- Modules: `queue` runs `decide`; `app` is all behaviour as a pure `update(state, event, now)`;
  `ui` draws; `fx` runs the tachyonfx effects; `keys` maps terminal keys; `main` wires the
  terminal, watcher, signals and threads.
- Try it on a sandbox queue, so nothing real is answered:

  ```bash
  S=$(mktemp -d); export RUN_DAY_STATE_DIR=$S INBOX_DIR=$S/inbox DECIDE=$PWD/../bin/decide
  echo "Some **context**" | $DECIDE add --key ECFX-1 --question "Ship it?" --option Yes --option No --recommend 1
  cargo run
  ```
