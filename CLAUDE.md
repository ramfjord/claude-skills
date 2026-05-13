# Skills workspace

Personal Claude Code skills, packaged as the `ramfjord` plugin. Installed, skills appear as `ramfjord:coding-lisp`, `ramfjord:swank-image`.

## Layout

- `.claude-plugin/plugin.json` — plugin manifest
- `.claude-plugin/marketplace.json` — marketplace catalog (this repo is its own marketplace)
- `skills/<name>/SKILL.md` — one directory per skill (no `ramfjord-` prefix on dir or `name:` field; the plugin namespace handles disambiguation)
- `plans/` — in-flight plans for ongoing work
- `fixtures/elp/` — gitignored clone of https://github.com/ramfjord/elp, used as a target repo when exercising the lisp skills. Re-clone if missing.

## Conventions

- **Cross-references between skills** use the installed form (`ramfjord:swank-image`, not `swank-image` or `ramfjord-swank-image`). That matches what the model sees at runtime.
- **Script paths inside skills** use `${CLAUDE_PLUGIN_ROOT}/skills/<name>/<script>.sh` so they resolve when installed via the marketplace, not just when run from this checkout.
- **Commits**: short imperative subject ("Add X", "Retire Y", "Update Z for ..."), logical units (one skill change per commit when practical). No Claude co-author trailer — see `git log` for the established style.
