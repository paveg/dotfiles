# ADR 0010: personal-mac as the unattended host, reached through Tailscale

- Status: Accepted (laptop sleep behaviour and headless Orca runtime to be measured)
- Date: 2026-11-25

## Context

Goal 9 asks that an agent loop started from the Orca iOS app never waits on a prompt only the host's screen can answer. The design left open which host runs agents when the owner is away. The Orca iOS app is a thin client: the host must stay awake, keep Orca's server running, and be reachable from the phone. That holds outside the home LAN too.

## Decision

- `personal-mac` is the unattended host. A headless Linux host is not used, because 1Password's SSH signing and `op` need the macOS desktop app, so on Linux they would need a 1Password service account, which reads only custom vaults (see Open questions).
- Orca is installed by hand (it has no Homebrew cask). `orca serve service install --command <Orca's bundled CLI>` runs its server as a LaunchAgent with a fixed PATH; Orca writes it, not nix-darwin. The phone joins the tailnet and pairs with the host's Tailscale address (`orca pair --mobile --address`).
- nix-darwin's `power.sleep.computer = "never"` keeps the Mac awake.
- Tailscale (`services.tailscale` in nix-darwin, the open-source `tailscaled`) on `personal-mac` only, brought up with `--ssh` and with key expiry disabled for that device. The Tailscale GUI app is removed from that host, because only the open-source daemon can be a Tailscale SSH server. `orca serve` accepts Tailscale addresses without `--allow-public`. Tailscale SSH is the way in when Orca is stuck.
- FileVault stays on. An unplanned restart is accepted as class 3. A planned restart uses `sudo fdesetup authrestart`; whether Orca's per-user service runs again before someone logs in is to be measured.

## Consequences

- Tailscale's node key is a credential on disk, and a Tailscale account is a new dependency.
- The Orca LaunchAgent is state that nix-darwin does not manage; a rebuild from scratch reinstalls it through `scripts/unattended-setup.sh`, which the owner runs by hand after the bootstrap. It is kept out of the bootstrap because almost all of it needs a person and CI cannot stub it.
- After a power loss the host is unreachable until someone unlocks FileVault at the Mac.
- `work-mac` and `wsl` cannot be reached from outside their LAN.

## Alternatives considered

- **Headless Linux `orca serve` host**: runs without a desktop login, but loses 1Password signing and `op`. Rejected until the 1Password service-account question is settled.
- **Cloudflare Tunnel, ZeroTier, plain WireGuard**: `orca serve` would accept them too (a tunnel connects from localhost, and ZeroTier or WireGuard addresses normally fall in a LAN range), but none gives an SSH path back into the host when Orca is stuck without running and securing a separate SSH server. Rejected.
- **A keep-awake app (Amphetamine) or a `caffeinate` agent**: a second owner for what one nix-darwin option does. Rejected.
- **FileVault off**: removes the class 3 restart, but leaves the disk readable to anyone holding the laptop. Rejected.
