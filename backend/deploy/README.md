# Deploying Paper

## Why the old copy used to disappear

The previous workflow copied files straight over the running application and ran
`pm2 restart all`. Three things were wrong with that, and together they are why a
push took the running copy away:

- the copy overwrote files underneath a live process, so for the length of the
  transfer the app ran against a half-replaced tree;
- `restart` tears the process down and brings it back on the new code — if that
  code cannot boot, nothing is left running and there is no way back;
- `all` did it to every process on the box, not just this application.

There was also no health check and no staging, so a push went straight to
whoever was using it.

## What happens now

```
push to main ─► tests ─► staging (port 18081, its own database)
                              │
                     you try it, and if it is right:
                              │
        Run workflow ──► promote: production (port 18080)
```

A push **never** reaches production. Production is `workflow_dispatch` with
`promote: production` — a decision, not a side effect of committing.

Each deploy, either environment:

1. lands in `releases/<timestamp>/` — never over the running code;
2. `current` symlink swaps atomically;
3. `pm2 reload` replaces workers one at a time, so connections are not dropped;
4. `/health` must answer `status: ok` within 60s;
5. if it does not, the symlink goes back and the previous release is reloaded;
6. the workflow then checks `/health` reports **the commit it just shipped**,
   which is what turns "the script said fine" into "the running code is ours".

## Layout on the box

```
~/paper/<app>/
  releases/20260826-101500/   one deploy
  current  -> releases/…      what pm2 runs
  previous -> releases/…      what a rollback returns to
  shared/.env                 config — outlives releases
  shared/data/paper.db        the database — outlives releases
```

Config and data live in `shared/` on purpose: **a rollback rolls back code, never
the database.** Rolling back a schema is a restore-from-backup problem, not a
symlink problem.

## Going back after a bad release

`release.sh` rolls back on its own when a release fails its health check. For the
other case — it came up healthy and is wrong anyway — every release is still on
disk, so going back is a symlink swap:

```bash
./deploy/rollback.sh paper-backend 18080
```

A rollback can itself be rolled back; the release you leave becomes the one you
would return to.

## Two apps on one box

`paper-backend` (18080) and `paper-staging` (18081) are separate pm2 apps with
separate databases. Nothing staging does can touch client data. Point nginx at
18080 for the client and, if you want to reach staging from outside, a separate
hostname at 18081 — behind auth, since it is not for clients.

## Before this is safe for real clients

Still true from `DEPLOYMENT_READINESS.md`, and not addressed here:

- `/sandbox-*`, `/config`, `/activation`, `/build` skip auth entirely;
- nginx terminates on port 80 — no TLS;
- there is no automated backup of `shared/data/`, and step 5 above assumes the
  database is fine. **Take a backup before promoting anything that migrates.**
