# Workspace Layout

This repository lives inside a `vela-workshop/` directory alongside clones of key go-vela repos:

| Directory | Repository | Description |
|---|---|---|
| `vela-skills/` | [ryanmr/vela-skills](https://github.com/ryanmr/vela-skills) | This repo -- skills, plans, notes, and research findings |
| `docs/` | [go-vela/docs](https://github.com/go-vela/docs) | Official Vela documentation site |
| `vela-tutorials/` | [go-vela/vela-tutorials](https://github.com/go-vela/vela-tutorials) | Tutorials and example pipelines |
| `ui/` | [go-vela/ui](https://github.com/go-vela/ui) | Vela web UI (Elm) |
| `server/` | [go-vela/server](https://github.com/go-vela/server) | Vela server (Go) -- API, compiler, database |
| `worker/` | [go-vela/worker](https://github.com/go-vela/worker) | Vela worker (Go) -- build executor |

## Setup

Clone all repos into a shared `vela-workshop/` directory:

```sh
mkdir vela-workshop && cd vela-workshop
git clone https://github.com/ryanmr/vela-skills.git
git clone https://github.com/go-vela/docs.git
git clone https://github.com/go-vela/vela-tutorials.git
git clone https://github.com/go-vela/ui.git
git clone https://github.com/go-vela/server.git
git clone https://github.com/go-vela/worker.git
```

The sibling repos (`docs/`, `server/`, `worker/`, `ui/`, `vela-tutorials/`) are read-only references for researching Vela behavior. All notes and development work belong in `vela-skills/`.

Plans and development notes are stored in the `.dev/` directory.
