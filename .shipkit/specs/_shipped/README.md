# Shipped specs

A spec moves here once every requirement in it has been released. The release and pull
request are recorded on its `> Status:` line.

Why a subdirectory rather than a status flag: the shipkit session hook scans
`.shipkit/specs/*/spec.md` and warns whenever HEAD is 15 or more commits past a spec's
"accepted at commit" stamp. For a finished spec that warning is noise, and the hook does
not read status lines. Moving the directory one level down takes it out of the scan while
keeping the history next to the live specs.

Live specs stay directly under `.shipkit/specs/`.

## Paths you can't open

Some shipped specs cite files under `tasks/` or `review-evidence/`. Both folders hold the
maintainer's private working notes and review material and are gitignored, so those files
aren't in the repository. Each spec still states its requirements, decisions and evidence on
its own; the cited files were where the work started, not part of the record.
