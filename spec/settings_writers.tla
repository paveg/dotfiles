------------------------- MODULE settings_writers -------------------------
(* The writers of ~/.claude/settings.json in docs/design.md ("Generated
   settings.json"): the switch's generator, Orca merging its hook entries at
   app start, Orca's theme sync, and Claude Code enabling a plugin. Each reads
   the file and later writes the whole file back; nothing serialises them, so any write may
   land between another writer's read and write. On macOS the generator first
   writes the guard hooks to a managed-settings drop-in, which no other writer
   touches. herdr is left out until it is adopted. *)
EXTENDS Naturals

Entries == {"guard", "orca", "plugin"}
Idle == "idle"
Reading == "read"

VARIABLES
    file,                   \* the entries in ~/.claude/settings.json
    managedGuard,           \* the guard hooks are in managed-settings.d/
    gen, genBuf, orca, orcaBuf, cc, ccBuf,
    genLeft, orcaLeft, ccLeft,  \* runs left: keeps the state space finite
    genRan,
    theme, themeBuf, themeLeft  \* Orca's theme sync

vars == <<file, managedGuard, gen, genBuf, orca, orcaBuf, cc, ccBuf,
          genLeft, orcaLeft, ccLeft, genRan, theme, themeBuf, themeLeft>>

Init ==
    /\ file = {} /\ managedGuard = FALSE
    /\ gen = Idle /\ genBuf = {} /\ orca = Idle /\ orcaBuf = {}
    /\ cc = Idle /\ ccBuf = {}
    /\ genLeft = 2 /\ orcaLeft = 2 /\ ccLeft = 1
    /\ genRan = FALSE
    /\ theme = Idle /\ themeBuf = {} /\ themeLeft = 1

GenRead ==
    /\ gen = Idle /\ genLeft > 0
    /\ gen' = Reading /\ genBuf' = file /\ genLeft' = genLeft - 1
    /\ UNCHANGED <<file, managedGuard, orca, orcaBuf, cc, ccBuf, orcaLeft, ccLeft, genRan, theme, themeBuf, themeLeft>>

GenWriteDropIn ==
    /\ gen = Reading /\ ~managedGuard
    /\ managedGuard' = TRUE
    /\ UNCHANGED <<file, gen, genBuf, orca, orcaBuf, cc, ccBuf, genLeft, orcaLeft, ccLeft, genRan, theme, themeBuf, themeLeft>>

(* The generator writes Orca's entries itself, so its write never depends on
   what it read. A plugin enabled in Claude Code is dropped: by design, the
   next switch overwrites changes made inside Claude Code. *)
GenWrite ==
    /\ gen = Reading
    /\ managedGuard            \* the drop-in is written first
    /\ file' = {"guard", "orca"}
    /\ gen' = Idle /\ genRan' = TRUE
    /\ UNCHANGED <<managedGuard, genBuf, orca, orcaBuf, cc, ccBuf, genLeft, orcaLeft, ccLeft, theme, themeBuf, themeLeft>>

(* Orca's hook installer: read the whole file, merge, rename over it, with no
   lock and no re-check (Orca source, see docs/verification.md). *)
OrcaRead ==
    /\ orca = Idle /\ orcaLeft > 0
    /\ orca' = Reading /\ orcaBuf' = file /\ orcaLeft' = orcaLeft - 1
    /\ UNCHANGED <<file, managedGuard, gen, genBuf, cc, ccBuf, genLeft, ccLeft, genRan, theme, themeBuf, themeLeft>>

OrcaWrite ==
    /\ orca = Reading
    /\ file' = orcaBuf \cup {"orca"} /\ orca' = Idle
    /\ UNCHANGED <<managedGuard, gen, genBuf, orcaBuf, cc, ccBuf, genLeft, orcaLeft, ccLeft, genRan, theme, themeBuf, themeLeft>>

(* Claude Code takes settings.json.lock and re-reads inside it, but neither
   other writer takes that lock, so its read and write are still two steps. *)
CCRead ==
    /\ cc = Idle /\ ccLeft > 0
    /\ cc' = Reading /\ ccBuf' = file /\ ccLeft' = ccLeft - 1
    /\ UNCHANGED <<file, managedGuard, gen, genBuf, orca, orcaBuf, genLeft, orcaLeft, genRan, theme, themeBuf, themeLeft>>

CCWrite ==
    /\ cc = Reading
    /\ file' = ccBuf \cup {"plugin"} /\ cc' = Idle
    /\ UNCHANGED <<managedGuard, gen, genBuf, orca, orcaBuf, ccBuf, genLeft, orcaLeft, ccLeft, genRan, theme, themeBuf, themeLeft>>

(* Orca's theme sync: re-reads after its last await, then writes back what it
   read plus its theme key, under a lock only Orca takes. It adds no hooks. *)
ThemeRead ==
    /\ theme = Idle /\ themeLeft > 0
    /\ theme' = Reading /\ themeBuf' = file /\ themeLeft' = themeLeft - 1
    /\ UNCHANGED <<file, managedGuard, gen, genBuf, orca, orcaBuf, cc, ccBuf, genLeft, orcaLeft, ccLeft, genRan>>

ThemeWrite ==
    /\ theme = Reading
    /\ file' = themeBuf /\ theme' = Idle
    /\ UNCHANGED <<managedGuard, gen, genBuf, orca, orcaBuf, cc, ccBuf, genLeft, orcaLeft, ccLeft, genRan, themeBuf, themeLeft>>

(* All runs are over; stutter so TLC does not report a deadlock. *)
EnvDone ==
    /\ gen = Idle /\ orca = Idle /\ cc = Idle /\ theme = Idle
    /\ genLeft = 0 /\ orcaLeft = 0 /\ ccLeft = 0 /\ themeLeft = 0
    /\ UNCHANGED vars

Next == GenRead \/ GenWriteDropIn \/ GenWrite \/ OrcaRead \/ OrcaWrite \/ CCRead \/ CCWrite \/ ThemeRead \/ ThemeWrite \/ EnvDone

Spec == Init /\ [][Next]_vars

---------------------------------------------------------------------------
(* Once a switch has written settings.json, the guard hooks are in effect in
   every state. This follows from the drop-in, not from the interleavings.
   Assumes nothing else writes the drop-in and Claude Code reads it; when a
   higher managed source (server-managed settings, an MDM profile) hides it,
   only the copy in
   settings.json is left, and Orca or Claude Code can drop that copy until the
   next switch (docs/design.md). *)
GuardsInEffect == genRan => (managedGuard \/ "guard" \in file)

(* A switch never drops Orca's entries. A stale write by Claude Code or by
   Orca's own theme sync still can: those races are between other tools and
   outside this design. *)
SwitchKeepsOrca ==
    [][("orca" \in file /\ "orca" \notin file') => ~GenWrite]_vars
=============================================================================
