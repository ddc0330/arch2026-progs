# Implementing and Measuring Four Applications on RV32I

This is the local draft for **one HackMD note covering all four programs**.
The Rubik baseline is committed; quarter-turn compression is the next
checkpoint being prepared for review. The
other sections will be expanded from their actual source, history, and measured
results. This draft is not the completed assignment report.

The permitted target is RV32I plus Zicsr for counter reads. Multiplication,
division, floating-point, and compressed instructions are not permitted.
Host-side reference calculations may use wider arithmetic; target code may not
silently depend on those host capabilities.

The requested writing references are
[Optimizing 2D Line Drawing on RV32I with Fixed-Point Arithmetic](https://hackmd.io/@sysprog/line-draw-fixed-point)
and [Approximating sine function in BF16 data type](https://hackmd.io/@sysprog/bf16-sine).
Their contents could not be retrieved during this session. A style comparison
remains pending; their titles alone do not establish their writing approach.
In particular, floating-point instructions from a reference are not permitted
in this implementation.

## How results and code references are recorded

For each experiment, record the starting commit, a specific hypothesis, the
change, verification coverage, and before/after instruction, cycle, and size
measurements. An intermediate version can fail an assignment limit; record that
failure and distinguish it from a wrong answer. These checkpoints reconstruct
and remeasure the optimization sequence after an optimized version was already
found. They are not presented as a fabricated discovery chronology.

Each short code excerpt in the published note must have a link of the form
`https://github.com/ddc0330/arch2026-progs/blob/<full-commit-id>/<path>#Lx-Ly`
followed by an explanation of its role and correctness. The baseline commit is
`c12c3c22449d556469a87395e9b6f3de0ed90ff4`. Later excerpts will be linked
after their commits exist. A branch URL or a guessed hash is not a substitute.

Use `make CROSS_COMPILE=/home/ddc/.local/bin/rv32- grade DRIVER_ARGS="--prog rubik"`
for the Rubik checkpoints. The harness subtracts its counter overhead when
reporting per-call benchmark costs. rv32emu counter results are emulator
measurements, not physical hardware timings. Record the compiler and emulator
revisions alongside the final measurement tables.

## 1. BFloat16 arithmetic

Scope: binary32-to-BF16 conversion, BF16 multiplication, and BF16 square root.
This section is pending a separate review of the committed implementation.

The final discussion must derive sign/exponent/significand decomposition,
normal and subnormal ranges, conversion rounding, multiplication normalization,
and the integer square-root approximation. It must distinguish truncation from
round-to-nearest and describe zero, infinity, NaN, underflow, and overflow
according to this assignment's contract. Derive error bounds against a host
reference, report exhaustive and boundary coverage, and measure each C and
assembly optimization. Explain the cost of replacing floating-point operations
and multiplication with integer operations. Applications include reduced-memory
numerical processing, with attention to the effect of reduced precision.
No new BF16 verification or performance result is claimed in this checkpoint.

## 2. Binary greatest common divisor

This section is pending a separate review of the committed implementation.

Derive the parity identities used by binary GCD and the subtraction step;
explain termination, zero inputs, and the full unsigned 32-bit range. Results
are exact, so numerical approximation error does not apply; compare exact
answers with a host Euclidean reference. Document boundary pairs, exhaustive
small domains, adversarial inputs, and measured instruction/cycle changes.
Explain how shifts and subtraction replace division on RV32I. Applications
include fraction reduction and integer arithmetic in systems without a divider.
No new GCD verification or performance result is claimed in this checkpoint.

## 3. Bitwise arithmetic and Q11.20 multiplication

This section is pending a separate review of the committed implementation.

Derive carry propagation, two's-complement subtraction, and an overflow-safe
unsigned average. For Q11.20, derive the stored-integer scale, representable
range, resolution, product rescaling, rounding, and wraparound behavior from
the actual implementation. Bound quantization error separately from overflow.
Compare with a wider host reference and cover carry chains, signs, rounding
ties, and overflow boundaries. Measure the successive software multiplication
implementations, including any loop unrolling. Applications include embedded
geometry and control, where scale selection trades range for precision.
No new fixed-point verification or performance result is claimed here.

## 4. Optimal 2x2x2 Rubik's Cube solver

### Starting from the original implementation

The starting point is my existing `~/minirubik/solver.c` and `solver.S`, adapted
to the assignment API. The original assembly is a standalone program: it has
an entry point, a fixed input, and optional rendering. The assignment instead
needs a callable function taking a state pointer, an output pointer, and a
capacity. The first checkpoint retains the coordinate-based IDA* algorithm,
adds the API validation and output behavior, and preserves the RISC-V ABI.
The C solver and its supplied tables remain unchanged during later assembly
optimizations.

### Coordinates and exact integer representation

Fixing one corner leaves seven corner cubies. Their permutation has
`7! = 5040` possibilities. Let `c_i` count later cubies smaller than cubie `i`.
The permutation rank is

```
p = sum(i=0..6, c_i * (6-i)!)
```

The implementation evaluates this mixed-radix representation with Horner's
rule: `p = p * (7-i) + c_i`, initially zero. Thus `0 <= p <= 5039`.

Write each orientation digit minus ASCII '1' as `o_i` in `{0,1,2}`. The twist
constraint requires their sum to be zero modulo three. Therefore the first
six orientations determine the seventh, and their base-three rank is

```
o = sum(i=0..5, o_i * 3^(5-i)),    0 <= o <= 728.
```

There are `5040 * 729 = 3,674,160` coordinate states. These are exact integer
encodings, not approximate numerical formats. Both coordinates fit in unsigned
16-bit fields. Ranking intermediates and addresses use 32-bit registers. The
orientation validation sum is at most 14. No coordinate calculation overflows
its selected representation; no saturation or rounding is involved.

There are nine unit-cost moves: R, R2, R', B, B2, B', D, D2, and D'. A half
turn costs one move under this metric. The coordinate transition tables map
one move and one coordinate to the next coordinate. C uses move-major tables;
the baseline assembly tables use state-major rows. Each assembly row has nine
16-bit entries, so the byte offset is `18 * coordinate + 2 * move`.

### Why IDA* returns a shortest solution

The two abstract distance tables ignore one coordinate at a time. Any full
solution is also a path in each abstract graph, hence

```
h(p,o) = max(perm_dist[p], ori_dist[o]) <= optimal_distance(p,o).
```

The maximum is admissible; summing the distances would not generally be safe
because one move can improve both coordinates. Iterative deepening starts at
this lower bound and increases the allowed path length one at a time. A child
is pruned only if an abstract distance exceeds the remaining moves. Therefore
no solution within the current bound is discarded. The first successful bound
is the optimal distance.

Consecutive moves on the same face compose into at most one move in this move
metric. A shortest nonempty path cannot need two such consecutive moves.
Skipping them reduces the branching factor after the first level from nine
to six without losing optimality. The assembly represents the search stack
explicitly and restores callee-saved registers before returning.

### Baseline measurements and the actual failure

The baseline was restored and rerun before preparing this checkpoint.

| Quantity | Baseline result |
| --- | ---: |
| Official tests, each optimization level | 51 passed, 1 failed |
| Failing test | `rubik_asm_depth11` |
| Instructions for `21345671111111` | 9,773,561 |
| Assembly instruction limit | 7,500,000 |
| Best C benchmark, O3, cycles per call | 103,318.0 |
| Assembly benchmark, cycles per call | 130,413.3 |
| Assembly static data | 109,611 bytes |
| Assembly code | 1,332 bytes |
| C / assembly benchmark checksum | 29 / 29 |

The failing test reports the instruction limit before checking that call's
output. It is evidence of excessive search work, not evidence of a buffer or
move-format defect. Other tests, including C/assembly length consistency,
pass. Compilation, linking, instruction restrictions, static-data budget, and
hygiene checks pass. Overall grading still fails because the assembly exceeds
the depth-eleven instruction limit and is slower than the best C benchmark.
The first reported failure is not a measured global worst case.

### Verification and the meaning of zero error

For this exact search problem, the reference is an exact shortest distance,
not a floating-point approximation. Verification requires both a valid path
and equality between its move count and the reference distance. A valid but
longer path is incorrect.

The official tests cover depths zero through eleven, all nine single moves,
a chain descending from distance eleven to zero, invalid states, output buffer
boundaries, and agreement between C and assembly solution lengths. Invalid
input must leave the output untouched. Insufficient output space must return
-2 and clear the first output byte when capacity permits. These checks cover
separate API obligations; a checksum alone does not prove optimality.
The baseline has not undergone a target-side exhaustive sweep of all states.

### What RV32I costs in the baseline

Without multiplication, table row offsets use shifts and addition:
`18*p = (p << 4) + (p << 1)`. The orientation rank uses
`3*o = (o << 1) + o`. Face selection uses comparisons instead of division by
three. Search frames and 16-bit coordinate loads keep the implementation
bounded and avoid heap allocation. These transformations preserve the integer
algorithm, but the baseline still generates too many search candidates.

### Optimization checkpoints to remeasure

| Checkpoint | Hypothesis | Status |
| --- | --- | --- |
| 1. Original C + iterative IDA* assembly port | Establish API behavior and measured bottleneck | Committed as `c12c3c2` |
| 2. Quarter-turn transition tables | Compose turns to reduce table storage and reuse successor work | Implemented and measured; awaiting review |
| 3. Exact radius-five completion | Replace the last five search levels with a small exact lookup | Not yet applied in this sequence |
| 4. Complete distance-eleven membership table | Skip smaller bounds only when exact membership proves they fail | Not yet applied in this sequence |

Later checkpoints must explain both the memory saved and the extra instructions
spent composing turns, rather than assuming compression is automatically faster.
Every additional table must have a retained, reproducible derivation from my
original transitions. Before/after measurements will be added only after each
checkpoint is executed. The previously tested optimized endpoint is backed up
outside the commit candidate; its results are not attributed to this baseline.

### Checkpoint 2: make room for a stronger search table

The baseline indexes all nine transitions independently:

```asm
slli    t5, t3, 4
slli    t6, t3, 1
add     t5, t5, t6
```

[Baseline source at c12c3c2](https://github.com/ddc0330/arch2026-progs/blob/c12c3c22449d556469a87395e9b6f3de0ed90ff4/src/rubik/rubik.S#L518-L520).
These instructions form `18*p`, the offset of one nine-entry permutation
row. The orientation table has the same layout. This makes successor lookup
simple, but the two transition tables consume `5769 * 9 * 2 = 103842` bytes.

Let `Q_f` denote a quarter turn on face `f`. The other two moves on that face
are exactly `Q_f(Q_f(s))` and `Q_f(Q_f(Q_f(s)))`; four applications return to
`s`. Keeping only the three quarter-turn columns reduces transition storage
to `5769 * 3 * 2 = 34614` bytes. This does not change the move metric: the
search still evaluates each of the three resulting turns as one move.

The host-only generator `tools/rubik/gen_search_tables.py` reads the original
C tables without modifying them. For every permutation and orientation it
checks all three compositions on each face against the original nine entries,
then checks the fourth application returns to the original coordinate. Thus
all 51,921 original transitions are covered before the extra columns are
removed. Abstract distance arrays are copied unchanged. The target still uses
only shifts, addition, and naturally aligned 16-bit loads for row access.
The generator is retained to make the smaller table reproducible; Python is
not used during target execution or the ordinary build.

Within one search frame, the first move of each face starts from the parent's
coordinates. Subsequent turns start from that frame's preceding quarter-turn
result. Saving this result **before** heuristic pruning matters: a pruned
quarter turn must still be the input when generating the half turn. Child
frames must not overwrite a parent's cached result. Frames therefore grow
from 8 to 16 bytes, and the assembly search's stack allocation grows from
128 to 224 bytes. Search ordering, heuristic, and shortest-path proof are
unchanged. API parsing, ranking, and output formatting are unchanged too.

| Quantity | Baseline | Quarter-turn checkpoint |
| --- | ---: | ---: |
| Assembly static data, including alignment | 109,611 bytes | 40,385 bytes |
| Assembly code | 1,332 bytes | 1,356 bytes |
| Assembly benchmark cycles per call | 130,413.3 | 140,743.8 |
| Instructions for `21345671111111`, O3 caller | 9,773,561 | 10,553,435 |
| Official tests per optimization level | 51 pass / 1 fail | 51 pass / 1 fail |
| C / assembly benchmark checksum | 29 / 29 | 29 / 29 |

The saving is 69,226 static bytes including alignment. The extra first-turn
selection and cached-coordinate stores increase instruction and cycle counts;
this checkpoint is a storage tradeoff, not a speed improvement. The failing
test remains `rubik_asm_depth11` because of its instruction budget. Instruction
restrictions, footprint, hygiene, and the other tests pass at all four compiler
optimization levels. The reported failing input is not an exhaustive worst-case
measurement. Exact table-composition checks and the official tests support this
checkpoint; no new target-side exhaustive search sweep is claimed.

The next experiment can now spend the recovered storage on exact short suffixes
and reduce the number of generated search candidates. It has not been applied
to this checkpoint. A pinned excerpt for this change will be added after its
commit exists.

### Applications and transferable constraints

The same separation between exact state coordinates, admissible lower bounds,
and bounded search appears in small planning and puzzle problems. Precomputation
can exchange storage for reduced search, but the table generation and target
memory budget must both be explained. Integer-only embedded systems also make
layout, register use, and address arithmetic significant parts of the cost.

The publication checklist remains open: finish all four program sections,
retrieve and review both writing references, add pinned excerpt links after
commits exist, complete measurement tables, and publish this single note to
HackMD. No HackMD upload or GitHub push has been performed by this session.
