---------------------------- MODULE bootstrap ----------------------------
(* The bootstrap of docs/design.md ("Bootstrap"), as steps over persistent
   effects. A run may stop after any step and be started again from step 1. *)
EXTENDS Naturals

Hosts == {"personal-mac", "work-mac", "wsl"}
PersonalHosts == {"personal-mac", "wsl"}
NoHost == "none"
Done == 11

OsOf(h) == IF h = "wsl" THEN "linux" ELSE "mac"

VARIABLES
    os, intended,               \* the machine, fixed for a behaviour
    arg, running, pc,           \* the current run
    recorded, nix, checkout,    \* persistent effects
    switch1, switch2, lefthook, workProfile,
    signedIn, ghtknDone,        \* human steps
    keeperUp, ksmProfile, ksmCalled,
    careful                     \* the owner has stopped naming wrong hosts

effects == <<recorded, nix, checkout, switch1, switch2, lefthook, workProfile, ksmCalled>>
vars == <<os, intended, arg, running, pc, recorded, nix, checkout, switch1,
          switch2, lefthook, workProfile, signedIn, ghtknDone, keeperUp,
          ksmProfile, ksmCalled, careful>>

ArgOk == arg \in Hosts /\ OsOf(arg) = os /\ (recorded = NoHost \/ recorded = arg)

Init ==
    /\ intended \in Hosts
    /\ os = OsOf(intended)
    /\ arg \in Hosts \cup {NoHost}
    /\ running = TRUE /\ pc = 1
    /\ recorded = NoHost
    /\ nix = FALSE /\ checkout = FALSE
    /\ switch1 = FALSE /\ switch2 = FALSE /\ lefthook = FALSE
    /\ workProfile = "absent"
    /\ signedIn = FALSE /\ ghtknDone = FALSE
    /\ keeperUp \in BOOLEAN /\ ksmProfile = FALSE /\ ksmCalled = FALSE
    /\ careful = FALSE

Advance == pc' = pc + 1
Halt == running' = FALSE /\ UNCHANGED pc

(* Step actions: one per numbered step, named like the script's functions. *)
StepCheckHost ==
    /\ running /\ pc = 1
    /\ IF ArgOk THEN Advance /\ UNCHANGED running ELSE Halt
    /\ UNCHANGED <<careful, os, intended, arg, effects, signedIn, ghtknDone, keeperUp, ksmProfile>>

StepInstallNix ==
    /\ running /\ pc = 2
    /\ nix' = TRUE /\ Advance
    /\ UNCHANGED <<careful, os, intended, arg, running, recorded, checkout, switch1, switch2,
                   lefthook, workProfile, signedIn, ghtknDone, keeperUp, ksmProfile, ksmCalled>>

StepRecordHost ==
    /\ running /\ pc = 3
    /\ recorded' = arg /\ Advance
    /\ UNCHANGED <<careful, os, intended, arg, running, nix, checkout, switch1, switch2,
                   lefthook, workProfile, signedIn, ghtknDone, keeperUp, ksmProfile, ksmCalled>>

StepClone ==
    /\ running /\ pc = 4
    /\ checkout' = TRUE /\ Advance
    /\ UNCHANGED <<careful, os, intended, arg, running, recorded, nix, switch1, switch2,
                   lefthook, workProfile, signedIn, ghtknDone, keeperUp, ksmProfile, ksmCalled>>

StepFirstSwitch ==
    /\ running /\ pc = 5
    /\ switch1' = TRUE /\ Advance
    /\ UNCHANGED <<careful, os, intended, arg, running, recorded, nix, checkout, switch2,
                   lefthook, workProfile, signedIn, ghtknDone, keeperUp, ksmProfile, ksmCalled>>

StepSignIn ==
    /\ running /\ pc = 6
    /\ IF signedIn THEN Advance /\ UNCHANGED running ELSE Halt
    /\ UNCHANGED <<careful, os, intended, arg, effects, signedIn, ghtknDone, keeperUp, ksmProfile>>

(* Step 7: work-mac only; skipped when the profile exists, so a rerun never
   overwrites unpushed edits. Pulls through ksm when Keeper is up and a KSM
   profile exists; otherwise waits for a person (ksm init or hand placement). *)
StepWorkProfile ==
    /\ running /\ pc = 7
    /\ IF recorded # "work-mac" \/ workProfile # "absent"
         THEN Advance /\ UNCHANGED <<careful, running, workProfile, ksmCalled>>
       ELSE IF keeperUp /\ ksmProfile
         THEN /\ workProfile' = "clean" /\ ksmCalled' = TRUE
              /\ Advance /\ UNCHANGED running
       ELSE Halt /\ UNCHANGED <<careful, workProfile, ksmCalled>>
    /\ UNCHANGED <<careful, os, intended, arg, recorded, nix, checkout, switch1, switch2,
                   lefthook, signedIn, ghtknDone, keeperUp, ksmProfile>>

StepSecondSwitch ==
    /\ running /\ pc = 8
    /\ switch2' = TRUE /\ Advance
    /\ UNCHANGED <<careful, os, intended, arg, running, recorded, nix, checkout, switch1,
                   lefthook, workProfile, signedIn, ghtknDone, keeperUp, ksmProfile, ksmCalled>>

StepGhtknAuth ==
    /\ running /\ pc = 9
    /\ IF ghtknDone THEN Advance /\ UNCHANGED running ELSE Halt
    /\ UNCHANGED <<careful, os, intended, arg, effects, signedIn, ghtknDone, keeperUp, ksmProfile>>

StepInstallHooks ==
    /\ running /\ pc = 10
    /\ lefthook' = TRUE /\ Advance
    /\ UNCHANGED <<careful, os, intended, arg, running, recorded, nix, checkout, switch1, switch2,
                   workProfile, signedIn, ghtknDone, keeperUp, ksmProfile, ksmCalled>>

Steps == StepCheckHost \/ StepInstallNix \/ StepRecordHost \/ StepClone
         \/ StepFirstSwitch \/ StepSignIn \/ StepWorkProfile \/ StepSecondSwitch
         \/ StepGhtknAuth \/ StepInstallHooks

(* Environment actions: no function in the script. *)
EnvStop ==
    /\ running /\ pc < Done
    /\ running' = FALSE
    /\ UNCHANGED <<careful, os, intended, arg, pc, effects, signedIn, ghtknDone, keeperUp, ksmProfile>>

(* The owner reruns the same command, naming the intended host. *)
EnvRestart ==
    /\ ~running /\ pc < Done
    /\ running' = TRUE /\ pc' = 1 /\ arg' = intended
    /\ UNCHANGED <<careful, os, intended, effects, signedIn, ghtknDone, keeperUp, ksmProfile>>

(* A rerun with a missing or wrong host, until the owner is careful. *)
EnvRestartWrongArg ==
    /\ ~careful /\ ~running /\ pc < Done
    /\ running' = TRUE /\ pc' = 1
    /\ arg' \in (Hosts \cup {NoHost}) \ {intended}
    /\ UNCHANGED <<careful, os, intended, effects, signedIn, ghtknDone, keeperUp, ksmProfile>>

EnvSignIn ==
    /\ ~signedIn /\ signedIn' = TRUE
    /\ UNCHANGED <<careful, os, intended, arg, running, pc, effects, ghtknDone, keeperUp, ksmProfile>>

EnvGhtknAuth ==
    /\ ~ghtknDone /\ ghtknDone' = TRUE
    /\ UNCHANGED <<careful, os, intended, arg, running, pc, effects, signedIn, keeperUp, ksmProfile>>

EnvKsmInit ==
    /\ recorded = "work-mac" /\ keeperUp /\ ~ksmProfile
    /\ ksmProfile' = TRUE
    /\ UNCHANGED <<careful, os, intended, arg, running, pc, effects, signedIn, ghtknDone, keeperUp>>

EnvPlaceWorkProfile ==
    /\ recorded = "work-mac" /\ workProfile = "absent" /\ ~keeperUp
    /\ workProfile' = "clean"
    /\ UNCHANGED <<careful, os, intended, arg, running, pc, recorded, nix, checkout, switch1,
                   switch2, lefthook, signedIn, ghtknDone, keeperUp, ksmProfile, ksmCalled>>

EnvEditWorkProfile ==
    /\ workProfile = "clean" /\ workProfile' = "edited"
    /\ UNCHANGED <<careful, os, intended, arg, running, pc, recorded, nix, checkout, switch1,
                   switch2, lefthook, signedIn, ghtknDone, keeperUp, ksmProfile, ksmCalled>>

EnvKeeperDown ==
    /\ keeperUp /\ keeperUp' = FALSE
    /\ UNCHANGED <<careful, os, intended, arg, running, pc, effects, signedIn, ghtknDone, ksmProfile>>

(* The recovery from a wrong first host, done by hand: push any work-profile
   edits, then delete the recorded host, ~/.config/dots-work/, and the KSM
   profile together. Deleting only the recorded host leaves the work profile on
   a personal machine (TLC counterexample). ksmCalled tracks the current
   recorded host, so it is cleared too. *)
EnvResetHost ==
    /\ ~running /\ recorded # NoHost /\ recorded # intended
    /\ recorded' = NoHost /\ workProfile' = "absent"
    /\ ksmProfile' = FALSE /\ ksmCalled' = FALSE
    /\ UNCHANGED <<careful, os, intended, arg, running, pc, nix, checkout, switch1, switch2,
                   lefthook, signedIn, ghtknDone, keeperUp>>

EnvBecomeCareful ==
    /\ ~careful /\ careful' = TRUE
    /\ UNCHANGED <<os, intended, arg, running, pc, effects, signedIn, ghtknDone, keeperUp, ksmProfile>>

(* A finished run stutters here, so TLC does not report it as a deadlock. *)
EnvDone == pc = Done /\ UNCHANGED vars

Env == EnvStop \/ EnvRestart \/ EnvRestartWrongArg \/ EnvSignIn \/ EnvGhtknAuth
       \/ EnvKsmInit \/ EnvPlaceWorkProfile \/ EnvEditWorkProfile \/ EnvKeeperDown
       \/ EnvResetHost \/ EnvBecomeCareful \/ EnvDone

Next == Steps \/ Env

(* Liveness assumptions: each step that is enabled again and again is taken
   (strong fairness, because a stop can disable it), a stopped run is restarted
   with the intended host, and people finish their human steps. The host check
   is fair only when the host is right: a check that halts a wrong-host rerun
   is not progress. *)
Fairness ==
    /\ WF_vars(StepCheckHost) /\ SF_vars(StepCheckHost /\ ArgOk) /\ SF_vars(StepInstallNix) /\ SF_vars(StepRecordHost)
    /\ SF_vars(StepClone) /\ SF_vars(StepFirstSwitch) /\ SF_vars(StepSignIn)
    /\ SF_vars(StepWorkProfile) /\ SF_vars(StepSecondSwitch)
    /\ SF_vars(StepGhtknAuth) /\ SF_vars(StepInstallHooks)
    /\ SF_vars(EnvRestart)
    /\ WF_vars(EnvSignIn) /\ WF_vars(EnvGhtknAuth)
    /\ WF_vars(EnvKsmInit) /\ WF_vars(EnvPlaceWorkProfile) /\ SF_vars(EnvResetHost) /\ WF_vars(EnvBecomeCareful)

Spec == Init /\ [][Next]_vars /\ Fairness

---------------------------------------------------------------------------
(* Properties, in the order docs/design.md lists them. *)

PersonalHostNeverTouchesKeeper ==
    recorded \in PersonalHosts => (~ksmCalled /\ workProfile = "absent")

(* No step after the host check runs with a missing or mismatched host. *)
BadHostChangesNothing == (running /\ pc > 1) => ArgOk

WorkMacNeverFinishesWithoutProfile ==
    (pc = Done /\ recorded = "work-mac") => (workProfile # "absent" /\ switch2)

(* No step of the script, rerun or not, discards unpushed edits. *)
UnpushedEditsSurvive == [][Steps => (workProfile = "edited" => workProfile' = "edited")]_vars

EventuallyFinishes == <>(pc = Done)
=============================================================================
