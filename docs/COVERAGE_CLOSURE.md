# Coverage-closure update: byte/half, traps, cache stress, extreme values, full RV32M

This update covers the 5 requested items. It also fixes 4 reference-model / scoreboard / generator bugs that the new tests exposed.

## 1. What changed

| File | Status | Purpose |
|---|---|---|
| `tb/common/riscv_asm_pkg.sv` | **new** | RV32IM+Zicsr mnemonic encoders (`LB(rd,rs1,imm)`, `MULHSU(...)`, `CSRRW(...)`, `ECALL()`...) and a `riscv_program` image builder (`li`, `org`, `emit`, `data`, `halt`). No hand-written hex in the new tests. |
| `tb/refmodel/reference_model.sv` | rewritten | LB/LH/LBU/LHU/SB/SH (byte-lane accurate memory), full M-ext, M-mode traps (ECALL 11, EBREAK 3, illegal 2, misaligned load 4 / store 6), MRET, CSR file matching `riscv_csr_regfile.v` (masks, MIE/MPIE/MPP stacking), FENCE/FENCE.I/D$-CSRs as no-ops, self-loop end detection, `+REF_MAX_STEPS`, `exec_ap` |
| `tb/refmodel/riscv_exec_item.sv` | **new** | per-executed-instruction record for functional coverage |
| `tb/refmodel/coverage_collector.sv` | extended | 6 new covergroups (below); the original 3 are unchanged |
| `tb/refmodel/scoreboard.sv` | hardened | strict in-order compare; leftover expected/actual writes are now `UVM_ERROR` |
| `tb/refmodel/refmodel_pkg.sv`, `tb/env/riscv_env_pkg.sv` | small | `_exec` imp, `ref_model.exec_ap -> cov.exec_export` |
| `tb/tests/rand_program.sv` | fixed + extended | legal SLLI/SRLI/SRAI, all 18 R-type ops, full signed imm range, `rand_load/store/mext/extreme_value` |
| `tb/tests/riscv_prog_base_test.sv` | **new** | base class: builds the program, loads it, **drain-based end of test** + watchdog, standard trap handler |
| `tb/tests/riscv_byte_half_test.sv` | **new** | item 1 |
| `tb/tests/riscv_trap_test.sv` | **new** | item 2 |
| `tb/tests/riscv_cache_stress_test.sv` | **new** | item 3 |
| `tb/tests/riscv_extreme_test.sv` | **new** | item 4 |
| `tb/tests/riscv_mext_test.sv` | **new** | item 5 |
| `tb/tests/riscv_full_random_test.sv` | **new** | constrained-random mix of everything (multi-seed) |
| `sim/files.f`, `sim/Makefile`, `sim/run_coverage.sh`, `sim/regress.sh` | updated | new sources; `make newtests`; coverage regression includes the new tests; `./regress.sh <n> <test>` |
| `tools/verilator_check/` | **new** | optional Verilator smoke-regression flow (see its README) |
| `tb/tests/riscv_reset_test.sv`, `tb/interfaces/reset_ctrl_if.sv` | **new** | mid-run reset injection -> FSM reset arcs + reset-recovery check (section 8) |
| `tb/top/tb_top.sv` | updated | reset = power-on reset AND injector pulse; injector (off by default) |
| `tb/agents/*/*_driver.sv`, `*_monitor.sv` | updated | reset-aware: abandon a half-finished AXI burst when reset asserts |
| `tb/env/riscv_env_pkg.sv`, `scoreboard.sv`, `reference_model.sv` | updated | on mid-run reset: flush scoreboard, restart model from PC 0 with the real memory contents |

## 2. Bugs found in the existing testbench

1. **MULH always predicted 0.** `(($signed(a))*($signed(b))) >> 32` is evaluated at 32 bits (the width of the LHS), so the upper half is discarded before the shift.
2. **SRA / SRAI / DIV / REM wrong for negative operands.** A `?:` with one unsigned branch makes the whole expression unsigned, so `$signed(a) >>> n` becomes a logical shift and DIV/REM become unsigned. Confirmed in Verilator and Icarus: `0xF0000000 sra 4 -> 0x0F000000` (correct `0xFF000000`), `-12/3 -> 0x55555551`. The existing tests used only positive operands, so these bugs were never visible.
3. **`rand_itype()` generated illegal SLLI encodings** (random `imm[11:5]`). The DUT takes an illegal-instruction trap and jumps to `mtvec`; the old model kept executing. That is the source of `riscv_mega_test`'s "22 unmatched expected". In some Verilator seeds the program restarted from `mtvec=0` and produced thousands of extra writes.
4. **The scoreboard hid both of these.** On an rd mismatch it silently dropped the expected entry, and leftovers were only an INFO "NOTE", so the summary still said `0 FAIL`.

Also: the step limit of 500 was too small for the new programs, and the CSR model accepted any CSR address.

## 3. DUT observations (spec deviations in this configuration)

All of these were confirmed on the RTL. The reference model follows the RISC-V spec for decode legality, so the new generators simply avoid these encodings.

* SLLI/SRLI/SRAI with `imm[25]=1` are accepted as legal. The masks are `0xFC00707F`, i.e. RV64 `shamt[5]`; RV32 requires an illegal-instruction trap.
* `LWU` (LOAD funct3=110, RV64-only) executes as LW instead of trapping.
* Accesses to unimplemented CSRs, and writes to read-only CSRs such as `cycle` (0xC00), do not trap (`csr_fault_r` only exists with `SUPPORT_SUPER=1`). The reference model mirrors the DUT here: it reads 0 and ignores writes.
* MRET sets `mstatus.MPP=U` even though U-mode is not implemented (spec: MPP should be the least-privileged supported mode, i.e. M). The reference model mirrors this so that `mstatus` reads can be checked.

## 4. New functional coverage (all bins hit by the merged regression)

| covergroup | content |
|---|---|
| `ls_cg` | {LB,LH,LW,LBU,LHU,SB,SH,SW} x byte offset (misaligned combos ignored), sign-extension cases, data address region [31:28] |
| `mext_cg` | 8 ops x 7 operand classes for rs1 and for rs2, div-by-zero x4, overflow x2 |
| `trap_cg` / `mret_cg` | 5 causes x mstatus.MIE at trap; MRET with MPIE 0/1 |
| `value_cg` | 0 / ~0 / MIN / MAX / 0xAAAAAAAA / 0x55555555, walking-1, walking-0, every rd written with 0 and ~0 |
| `sys_cg` | DFLUSH/DWRITEBACK/DINVALIDATE/FENCE/FENCE.I, fetch PC region [31:28] |

## 5. Results from the validation run

VCS was not available, so the numbers below come from a Verilator run of the real TB code (see `tools/verilator_check`). Treat them as indicative. VCS will report different absolute numbers, and condition coverage is not measured.

Regression = 7 original tests + random seeds, vs the same plus the 6 new tests (22 runs):

| DUT metric (Verilator) | before | after |
|---|---|---|
| line | 72.9 % | 86.1 % |
| branch | 78.8 % | 90.9 % |
| toggle | 48.8 % | 79.7 % |
| FSM transitions (dcache+icache, same 38 arcs as urg) | 10 / 38 | **26 / 38** (every reachable arc) |

Biggest movers: `dcache_core` line 67->98 %, toggle 58->93 %; `riscv_lsu` line 65->97 %; `riscv_multiplier` toggle 40->99 %; `riscv_alu` / `riscv_regfile` / tag RAMs toggle -> 100 %; `dcache_axi_axi` toggle 25->82 %.

* All 13 tests: 0 FAIL, 0 UVM_ERROR, no protocol-check failures. A 66-run seed sweep (full_random x30, random x20, mega x8, mext x8) was also clean.
* Mutation check: injecting a MULHSU bug, an LBU sign-extension bug, and a wrong store `mtval` into the model produced 27, 30 and 10 scoreboard FAILs respectively, so the checks have teeth.
* The whole TB compiles with zero errors in slang against the Accellera UVM library.

## 6. How to run (VCS)

```
cd sim
make compile
make run TEST=riscv_trap_test SEED=1
make newtests SEED=1                 # the 6 new tests, quick pass/fail table
./regress.sh 50 riscv_full_random_test
./run_coverage.sh                    # all tests -> merged.vdb + cov_report/
```

## 7. What still limits code coverage (next steps)

* **12 FSM arcs are reset arcs.** These are `<any>->STATE_RESET` in dcache_core (10) and `REFILL/RELOOKUP->STATE_FLUSH` in icache (2). They need reset asserted mid-operation. Either exclude them in Verdi/URG (standard practice) or add a mid-test reset sequence. With the exclusion, FSM transition coverage is 100 %.
* **Interrupts.** `intr_i` is tied to 0 in `tb_top`, and the mtimecmp timer is never armed. Most of the remaining `riscv_csr_regfile` lines are interrupt paths. Drive `intr_i` from a small interrupt agent and add interrupt cause/MIE modelling.
* **AXI error responses.** The drivers always return OKAY, so the fault exceptions (causes 1, 5, 7) are unreachable. Add a driver knob that returns SLVERR/DECERR for an address window.
* **Uncached D$ path** (`dcache_if_pmem`, `u_uncached`). `riscv_top` defaults to `MEM_CACHE_ADDR_MIN=0 / MAX=0xFFFFFFFF`, so everything is cacheable. Instantiate the DUT with e.g. `MAX=32'h7FFF_FFFF` in a second build to cover the uncached path.
* **Not reachable in this configuration:** the I$ AXI write channel, `SUPPORT_SUPER`/MMU logic, and `/*verilator public*/` debug functions. Exclude them.

## 8. Reset-injection test (FSM reset arcs)

The 12 FSM arcs that are left after the tests above are "<state> -> reset". `riscv_reset_test` covers them:

* **Injector (`tb_top`, enabled through `reset_ctrl_if`):** at a negedge, if the D$ controller is in one of its 10 non-reset states (or the I$ is in REFILL / RELOOKUP) that has not been reset from yet, it applies a 4-cycle reset. One run hits all 12 targets.
* **Reset-aware drivers and monitors:** a burst interrupted by reset is abandoned and the driver goes idle, as a real slave would after a system reset.
* **Checking:** after each reset the env flushes the scoreboard and restarts the reference model from PC 0, using the memory contents as they really are. Dirty cache lines are legitimately lost by a reset. After the last reset the program must complete with 0 mismatches, which proves recovery from reset in every cache state.

Verilator results: 12/12 targets hit, 1795 PASS / 0 FAIL, FSM transitions **38/38 (100 %)** when merged with the other tests. The other 13 tests are unchanged (injector off by default).
