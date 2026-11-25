------------------------- MODULE settings_writers -------------------------
(* The writers of ~/.claude/settings.json in docs/design.md ("Generated
   settings.json"): the switch's generator, Orca merging its hook entries at
   app start, and Claude Code enabling a plugin. Each reads the file and later
   writes the whole file back; nothing serialises the three, so any write may
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
    genRan

vars == <<file, managedGuard, gen, genBuf, orca, orcaBuf, cc, ccBuf,
          genLeft, orcaLeft, ccLeft, genRan>>

Init ==
    /\ file = {} /\ managedGuard = FALSE
    /\ gen = Idle /\ genBuf = {} /\ orca = Idle /\ orcaBuf = {}
    /\ cc = Idle /\ ccBuf = {}
    /\ genLeft = 2 /\ orcaLeft = 2 /\ ccLeft = 1
    /\ genRan = FALSE

GenRead ==
    /\ gen = Idle /\ genLeft > 0
    /\ gen' = Reading /\ genBuf' = file /\ genLeft' = genLeft - 1
    /\ UNCHANGED <<file, managedGuard, orca, orcaBuf, cc, ccBuf, orcaLeft, ccLeft, genRan>>

GenWriteDropIn ==
    /\ gen = Reading /\ ~managedGuard
    /\ managedGuard' = TRUE
    /\ UNCHANGED <<file, gen, genBuf, orca, orcaBuf, cc, ccBuf, genLeft, orcaLeft, ccLeft, genRan>>

(* The generator writes Orca's entries itself, so its write never depends on
   what it read. A plugin enabled in Claude Code is dropped: by design, the
   next switch overwrites changes made inside Claude Code. *)
GenWrite ==
    /\ gen = Reading
    /\ managedGuard            \* the drop-in is written first
    /\ file' = {"guard", "orca"}
    /\ gen' = Idle /\ genRan' = TRUE
    /\ UNCHANGED <<managedGuard, genBuf, orca, orcaBuf, cc, ccBuf, genLeft, orcaLeft, ccLeft>>

(* Orca's hook installer: read the whole file, merge, rename over it, with no
   lock and no re-check (Orca source, see docs/verification.md). *)
OrcaRead ==
    /\ orca = Idle /\ orcaLeft > 0
    /\ orca' = Reading /\ orcaBuf' = file /\ orcaLeft' = orcaLeft - 1
    /\ UNCHANGED <<file, managedGuard, gen, genBuf, cc, ccBuf, genLeft, ccLeft, genRan>>

OrcaWrite ==
    /\ orca = Reading
    /\ file' = orcaBuf \cup {"orca"} /\ orca' = Idle
    /\ UNCHANGED <<managedGuard, gen, genBuf, orcaBuf, cc, ccBuf, genLeft, orcaLeft, ccLeft, genRan>>

(* Claude Code takes settings.json.lock and re-reads inside it, but neither
   other writer takes that lock, so its read and write are still two steps. *)
CCRead ==
    /\ cc = Idle /\ ccLeft > 0
    /\ cc' = Reading /\ ccBuf' = file /\ ccLeft' = ccLeft - 1
    /\ UNCHANGED <<file, managedGuard, gen, genBuf, orca, orcaBuf, genLeft, orcaLeft, genRan>>

CCWrite ==
    /\ cc = Reading
    /\ file' = ccBuf \cup {"plugin"} /\ cc' = Idle
    /\ UNCHANGED <<managedGuard, gen, genBuf, orca, orcaBuf, ccBuf, genLeft, orcaLeft, ccLeft, genRan>>

(* All runs are over; stutter so TLC does not report a deadlock. *)
EnvDone ==
    /\ gen = Idle /\ orca = Idle /\ cc = Idle
    /\ genLeft = 0 /\ orcaLeft = 0 /\ ccLeft = 0
    /\ UNCHANGED vars

Next == GenRead \/ GenWriteDropIn \/ GenWrite \/ OrcaRead \/ OrcaWrite \/ CCRead \/ CCWrite \/ EnvDone

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

(* Only a Claude Code write can drop Orca's entries: that race is between two
   other tools and outside this design. *)
OnlyClaudeCodeDropsOrca ==
    [][("orca" \in file /\ "orca" \notin file') => CCWrite]_vars
=============================================================================
