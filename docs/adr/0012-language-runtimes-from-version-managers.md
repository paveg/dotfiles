# ADR 0012: Language runtimes from version managers

- Status: Accepted
- Date: 2026-11-28

## Context

design.md said "No other language runtimes", but the kept skills and agents need `node` and `python` (`docs/claude-stocktake.md`), and the owner works in Go, Rust, Node (pnpm, Deno), MoonBit, Ruby, Lean, and Swift. The owner decided on PAV-46 that runtimes stay narrow: Nix installs version managers, and the versions live elsewhere.

The locked nixpkgs has all four managers (measured, `nix eval` on `darwinConfigurations.personal-mac.pkgs`): `mise` 2026.10.17 (MIT), `uv` 0.13.9 (Apache-2.0 and MIT), `rustup` 1.29.3 and `elan` 4.3.0 (both Apache-2.0 OR MIT).

mise's registry maps `go`, `node`, `deno`, and `ruby` to its core backends, and `pnpm` to `aqua:pnpm/pnpm` first, then `npm:pnpm` (measured, `mise registry <tool>` with the locked mise). None of the five needs the asdf backend, which ADR 0006 disables.

## Decision

- `nix/packages.nix` adds `uv`, `rustup`, and `elan` next to `mise`, and no language runtime. A runtime comes from the manager for its language:

  | Language | Source | Version pinned by |
  |---|---|---|
  | Go, Node, pnpm, Deno, Ruby | mise | `home/.config/mise/config.toml`, and a project's `mise.toml` |
  | Python | uv (`uv run`) | the project (`requires-python`, `.python-version`) |
  | Rust | rustup | `rust-toolchain.toml`, else rustup's default toolchain |
  | Lean | elan | `lean-toolchain` |
  | Swift | Xcode, on macOS only | Xcode |
  | MoonBit | its official installer | the installer |

- The global mise config sets these defaults, each an exact version: `go = "1.27.4"`, `node = "24.22.3"`, `pnpm = "12.23.0"`, `deno = "2.9.8"`, `ruby = "4.0.10"`. On 2026-11-28 these were `mise latest` for each tool, except Node, which is `mise latest node@lts` (the newest release, 26.13.1, is not LTS by mise's list). A project's `mise.toml` overrides each one.
- No `python3` is on PATH from Nix. Python runs through `uv run`, which picks or downloads an interpreter per project. `uv python install` without `--default` puts only a minor-versioned executable in uv's bin directory: measured, `uv python install 3.13` created `python3.13` and nothing else.
- Swift comes from Xcode, because nixpkgs' `swift` cannot build Apple apps (PAV-64; not checked here). `wsl` gets no Swift.
- MoonBit comes from `curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash` on every host. It is in neither nixpkgs nor mise's registry (measured: no top-level nixpkgs attribute name contains `moonbit` or `MoonBit`, and `mise registry moonbit` says "tool not found in registry"). `nix/licenses.nix` records it under `outsideNix` for each host, as PAV-61 requires for an install from outside Nix.
- This amends ADR 0006 for Lean: `elan` is now a global package, not only part of the `lean` template's devShell. The toolchain version still belongs to the project's `lean-toolchain`.

### MoonBit licence

The installer downloads two archives from `cli.moonbitlang.com`: `binaries/<version>/moonbit-<target>.tar.gz` (the compiler and tools) and `cores/core-<version>.tar.gz` (the standard library). It installs them under `${MOON_HOME:-$HOME/.moon}`. The download page (https://www.moonbitlang.com/download/) and the installer state no licence.

- The compiler's source, https://github.com/moonbitlang/moonbit-compiler, is under the "MoonBit Public Source License", "Version 1, 11 December 2024", in `LICENSE.TXT`. The official copy is https://www.moonbitlang.com/licenses/moonbit-public-source-license-v1.
- Section 3: "This License explicitly affirms your unlimited permission to run the unmodified Program, subject to section 13." Section 13 is "No Surrender of Others' Freedom".
- Section 14, "Commercially or Competitively Offering the Program as a Service", applies when you make the Program available to third parties as a service. You then have to publish the Service Source Code.
- "MoonBit Compiler Exceptions to the MoonBit Public Source License": when the compiler embeds portions of itself in your output, you may convey them under the MIT License.
- The build tool, https://github.com/moonbitlang/moon, and the standard library, https://github.com/moonbitlang/core, are Apache-2.0.

So by the licence text, running the unmodified toolchain to build your own software is allowed, and that includes software for the work machine. Whether the company accepts this licence on `work-mac` is the owner's decision. The licence is not free in nixpkgs' sense: the compiler's README calls it a relaxed SSPL, and nixpkgs marks `sspl` as `free = false`. `nix/licenses.nix` records MoonBit as a list of two licences. The first is this one, with `free = false` and `redistributable = true`. The second is `asl20`.

Two points are **Unverified**:

- That the prebuilt binaries carry the licence of the source repository. Nothing on the download page or in the installer says so.
- The exact licence wording. These quotes came through a fetch tool's summary of `LICENSE.TXT` and of the official page, not from a local copy.

## Consequences

- One manager per language, each pinned by a file the language's own projects already use.
- The mise defaults go stale until someone edits them. Nothing bumps them: `.github/dependabot.yml` covers only `github-actions`.
- Measured on `aarch64-darwin` with the locked mise in an empty data directory: `mise install` installed all five defaults. Ruby came from a precompiled `jdx/ruby` tarball whose GitHub artifact attestations mise verified, so no compiler toolchain was needed. mise's docs say precompiled Ruby exists for glibc Linux too. `wsl` is not measured.
- Before a toolchain is installed, `mise ls` shows each default as `(missing)`, and `rustup show` says "no toolchain installed and no default toolchain set" (both measured on the built `personal-mac` profile). The profile's `cargo`, `rustc`, `lean`, and `lake` are the managers' proxies, which need a toolchain first.
- On macOS, `command -v python3` with the profile first on PATH answers `/usr/bin/python3`, Apple's own (measured on the built `personal-mac` profile, which has no `python*` executable).
- The global `elan` uses elan's default `~/.elan`. The `lean` template's devShell sets `ELAN_HOME` to `${XDG_DATA_HOME:-$HOME/.local/share}/elan`, so a project in the template and one outside it keep separate toolchain directories.
- The MoonBit installer adds its PATH line to `~/.zshrc` only when that file is writable. This design keeps the zsh files under `$ZDOTDIR`, and `$ZDOTDIR/.zshenv` does not put `~/.moon/bin` on PATH yet.
- The managers download toolchains from outside Nix (Go, Node, pnpm, Deno, Ruby, Rust, Lean, CPython). `tests/licenses.sh` does not list them. Xcode is also an install from outside Nix that `nix/licenses.nix` does not record.

## Alternatives considered

- **Runtimes as nixpkgs packages**: one version per host, which every project would share. Rejected, because projects pin their own versions.
- **mise for every language**: mise can also install Python, Rust, and Lean. Rejected, because uv, rustup, and elan read the pin files that Python, Rust, and Lean projects already commit.
- **Version aliases (`latest`, `lts`) or a major version (`node = "24"`) as the global defaults**: no edits to stay current, but each host resolves them when it installs, so two hosts can differ and nothing in a diff shows the change. Rejected in favour of exact versions.
- **Swift from nixpkgs**: cannot build Apple apps. Rejected.
