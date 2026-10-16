---
name: devartslab-saystop-distribution
description: saystop install endpoints and the release checklist. Use when shipping, releasing, or refactoring saystop.
---

[//]: # "author: Amir Olyaei | DevArts Lab | last_updated: 2026-10-15"

# Saystop Distribution

## What it is

Single-file Swift CLI (`Sources/saystop/main.swift`) with a floating
**Stop/Pause** panel for speech output. Speaks via `AVSpeechSynthesizer`
in-process for text/`-v`/`-r`/`-f`; other invocations run as a `/usr/bin/say`
child with a Stop-only panel. MIT, macOS 12+, universal binary, no deps.
Extras: `--install-shim` (a `say` shim that adds the panel to every call),
`--mute`/`--unmute` (a `~/.config/saystop/muted` flag file silencing all
speech, honored by the shim and CLI, posting a notification unless `--quiet`),
`extras/Stop Speaking.workflow` (Quick Action kill switch), and
`extras/Toggle Speech.workflow` (Quick Action mute toggle with notification).

## Endpoints

| Endpoint  | Location                                        | Delivers                                                   |
| --------- | ----------------------------------------------- | ---------------------------------------------------------- |
| Source    | `github.com/DevArtsLab/saystop`, `main`         | clone + `make`                                             |
| Tag       | `refs/tags/vX.Y.Z`                              | tarball for Homebrew                                       |
| Release   | `releases/latest`                               | `saystop` binary + `.sha256` (fetched by `install.sh`)     |
| Tap       | `DevArtsLab/homebrew-tap`, `Formula/saystop.rb` | `brew install DevArtsLab/tap/saystop`                      |
| Installer | `install.sh`                                    | downloads release binary, checks sha256, strips quarantine |

## Dev loop (no commit needed)

```sh
make && ./build/saystop "test"
```

- PATH `saystop` and the `say` shim still run the installed binary. The shim
  execs a hardcoded absolute path; to test it, run `./build/saystop
--install-shim` or overwrite the installed binary (see Gotchas).
- Unsure which build a binary is? `stat -f %Sm` both files, or
  `strings <bin> | grep <text>`.

## Ship checklist

Push to `main` only updates the source. To reach installers:

1. `make release` -> `build/saystop` + `build/saystop.sha256`
2. `git tag vX.Y.Z && git push origin vX.Y.Z` (never re-tag a release)
3. `gh release create vX.Y.Z build/saystop build/saystop.sha256`
4. In `homebrew-tap`, bump formula `url` to the new tag tarball and `sha256`
   to `curl -sL <url> | shasum -a 256`; push the tap.
5. `install.sh` needs no edit (resolves `releases/latest`).

## Gotchas

- `brew install` compiles via `swiftc`; users need Xcode CLT. The curl
  installer does not.
- Cellar binaries are read-only; `make install` fails silently over them
  (prints "installed" anyway). Fix: `chmod u+w` the Cellar binary, copy,
  restore `555`, or `brew uninstall` first.
- `brew upgrade` only sees a new version after step 4.
