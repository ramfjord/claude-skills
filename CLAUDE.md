# Skills workspace

Personal Claude Code skills for my dev workflow. Each top-level directory is one skill.

## Conventions

- **Naming**: every skill directory and the `name:` in its `SKILL.md` frontmatter is prefixed `ramfjord-`. The prefix namespaces these so they can sit alongside skills authored by others without collision. Keep it on every new skill.
- **Layout**: a skill is a directory containing `SKILL.md` (with frontmatter: `name`, `description`, optionally `model`) plus any supporting scripts/assets it references by relative path.
- **Commits**: short imperative subject ("Add X", "Retire Y", "Update Z for ..."), logical units (one skill change per commit when practical). No Claude co-author trailer — see `git log` for the established style.

## Testing lisp skills

`fixtures/elp/` is a clone of https://github.com/ramfjord/elp, gitignored. It's the target repo for exercising `ramfjord-coding-lisp` and `ramfjord-swank-worktree-image`. If it's missing, re-clone it there rather than picking a different repo, so the skills' assumptions (small CL project, known structure) hold.
