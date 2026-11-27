# CLAUDE.md

mqtt-lens is an Elixir/Phoenix project. The specs are in `specs/`. Start at `specs/index.md`.

## Commands

`make check` and `make integration` arrive in milestone M2. Until then, the verify
command is in each task.

```
make check        must end with "0 failures" and no warnings. Never skip or delete a failing test.
make integration  needs Docker. Must end with "0 failures".
make lint         zero warnings (format, credo --strict, sobelow).
Fix the code, not the test.
```

## Rules

- Track all work with beads (`bd`). Run `bd prime` for the workflow.
- Write the tests first. Commit them before the code.
- Fix the code, not the test. Never skip, weaken or delete a failing test.
- Use no employer data: no employer names, hosts, IPs or tickets.
- Role agents never merge a PR. The main session and the orchestrator merge only when the owner says so for that PR or batch. Always use `gh pr merge <n> --rebase`. Never use `--admin`, `--auto`, `--squash` or `--merge`.
- Never make a release or a tag. The owner does these by hand.
- One task = one branch `task/<id>` = one PR.
- Never push to `main`. Never bypass a hook (no `--no-verify`).
- Change only the files in the Files list of the task.
- Write docs and specs in ASD-STE100 (Simplified Technical English).

## Override of the global rule

For this project only, this replaces the global rule "the main session keeps review and
verification". In this project the orchestrator never reviews or verifies. The verifier
and reviewer agents do. See `specs/process/roles.md`.

## Things Claude gets wrong

(Empty. Add an entry each time the owner corrects a repeated mistake.)
