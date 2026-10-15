---
name: devartslab-saystop-distribution
description: How saystop reaches users, where each install endpoint lives (source, git tag, GitHub release binary, Homebrew tap, curl installer, local make), and the release checklist for making a source change take effect on every endpoint. Use when shipping, releasing, or refactoring saystop.
---

[//]: # "author: Amir Olyaei | DevArts Lab | last_updated: 2026-10-15"

# Saystop Distribution

How saystop reaches users, where each endpoint lives, and the full checklist for
making a source change take effect on every install path.

## What it is

`saystop` is a single-file Swift CLI (`Sources/saystop/main.swift`) that wraps
`/usr/bin/say` and shows a floating, non-activating NSPanel with a
**Stop speaking** button for as long as speech plays. MIT licensed, macOS 12.0+,
universal binary (arm64 + x86_64), zero dependencies beyond macOS itself.

It ships with two optional add-ons built into the same binary:

- `--install-shim`: writes a `say` shell shim into the first writable PATH dir
  preceding `/usr/bin`, so every `say` call gets the stop button.
- `extras/Stop Speaking.workflow`: a Quick Action kill switch (`killall say`).

## Where it is available (endpoints)

| Endpoint       | Location                                        | Delivers                                                                 |
| -------------- | ----------------------------------------------- | ------------------------------------------------------------------------ |
| Source         | `github.com/DevArtsLab/saystop`, branch `main`  | Cloners, `make` users                                                    |
| Git tag        | `refs/tags/vX.Y.Z` on the same repo             | Tarball that Homebrew downloads                                          |
| GitHub Release | `releases/latest`                               | Prebuilt `saystop` binary + `saystop.sha256` (what `install.sh` fetches) |
| Homebrew tap   | `DevArtsLab/homebrew-tap`, `Formula/saystop.rb` | `brew install DevArtsLab/tap/saystop`, compiles tarball via `swiftc`     |
| Curl installer | `install.sh` in repo, fetched raw from `main`   | Downloads latest release binary, verifies sha256, strips quarantine      |
| Local build    | `Makefile`                                      | `make` -> `build/saystop`, `make install` -> copies to a bin dir         |

## Refactor checklist: making a change reach every endpoint

Pushing to `main` only updates the source. Installers keep serving the old
build until you complete every step below.

1. Commit and push the change to `main`.
2. Rebuild and package: `make release` produces `build/saystop` and
   `build/saystop.sha256`.
3. Tag a new version: `git tag vX.Y.Z && git push origin vX.Y.Z`.
   Never move or re-tag a published version; always cut a new one.
4. Create the GitHub release:
   `gh release create vX.Y.Z build/saystop build/saystop.sha256`.
   The release binary is unsigned; `install.sh` clears quarantine after
   verifying the checksum, so the `.sha256` asset must always be uploaded.
5. Bump the formula in `DevArtsLab/homebrew-tap`:
   - `url` -> `https://github.com/DevArtsLab/saystop/archive/refs/tags/vX.Y.Z.tar.gz`
   - `sha256` -> output of `curl -sL <that url> | shasum -a 256`
   - Push the tap. A wrong sha256 breaks every `brew install`.
6. `install.sh` needs no edit; it resolves `releases/latest` dynamically.

## Gotchas

- `brew install` compiles from source (`uses_from_macos "swift" => :build`);
  it needs Xcode CLT on the user's machine. The curl installer is the
  dev-tools-free path.
- A brew-installed binary lives read-only (`-r-xr-xr-x`) in the Cellar;
  `make install` over it fails silently (the Makefile echoes "installed"
  even when `cp` fails). For local iteration either run `./build/saystop`
  directly, or `brew uninstall saystop` first.
- After a local `make`, the binary on PATH is unchanged until you reinstall;
  stale binaries are the number one cause of "my edit didn't take".
- `brew upgrade` only picks up a new version when the formula's `url`/`sha256`
  change, i.e. after step 5.
