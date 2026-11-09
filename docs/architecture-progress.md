# Implementing and Measuring Four Applications on RV32I

This is the local draft for **one HackMD note covering all four programs**.
The four Rubik checkpoints are implemented, measured, and committed.
The final Rubik implementation meets the stated correctness, instruction, and
space limits. The other sections will be expanded from their actual source,
history, and measured
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
measurements, not physical hardware timings. Final measurements used GCC 14.2.0
(`rv32-gcc 14.2.0+19`) and rv32emu revision
`ffb041bab9d1513e5329f25f486378778dceed13`, with
`-march=rv32i_zicsr -mabi=ilp32`.

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
| 2. Quarter-turn transition tables | Compose turns to reduce table storage and reuse successor work | Committed as `7c0017a` |
| 3. Exact radius-five completion | Replace the last five search levels with a small exact lookup | Committed as `7107364` |
| 4. Complete distance-eleven membership table | Skip smaller bounds only when exact membership proves they fail | Committed as `7b864c1` |

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

The recovered storage makes room for exact short suffixes. This checkpoint
is preserved at [7c0017a](https://github.com/ddc0330/arch2026-progs/blob/7c0017ae7fbb689fc0f6e7cfdb671d94f1f3250c/src/rubik/rubik.S#L508-L538).
Those instructions select either the parent or cached coordinates, apply one
quarter turn, and save the result before pruning. That ordering preserves
the composition even when the intermediate quarter turn is not expanded.

### Checkpoint 3: replace the last five search levels with an exact lookup

The second checkpoint showed that reducing table size alone increased search
cost. The next hypothesis is to spend some of that recovered memory on exact
short suffixes, removing many candidate expansions rather than only reducing
the cost of each expansion. The quarter-turn layout is retained.

The generator now runs unit-cost BFS from the solved coordinate, stopping at
radius five. Every move has an inverse in the nine-move set, so the distance
from solved is also the shortest solution length. The ball contains exactly
12,224 states: 1, 9, 54, 321, 1,847, and 9,992 at distances zero through five.
Only that ball is generated for the target; a full-state distance table is
neither linked nor needed by the ordinary table generator.

For each state, store one move whose successor has distance one smaller. The
word encoding is `(orientation << 8) | (distance << 4) | move`. Orientations
need ten bits, distances zero through five need three bits, and moves zero
through eight need four bits. Move 15 marks solved. These fields do not overlap
and fit in an unsigned 32-bit record. Orientation comparisons use `record >> 8`.
Records are grouped by permutation, sorted by orientation within a group.
A 5,041-entry unsigned 16-bit prefix-offset array identifies each group's
half-open range. The largest offset is 12,224, well below 65,536. Empty buckets
are valid. The largest bucket has eleven entries, so lookup needs at most four
binary comparisons. No division, multiplication, floating-point arithmetic,
or heap allocation is introduced on the target.

| Added table | Entries and width | Bytes before alignment |
| --- | --- | ---: |
| `near_offsets` | 5,041 x uint16 | 10,082 |
| `near_records` | 12,224 x uint32 | 48,896 |

Roots in this ball are solved directly by following the stored moves. Other
roots begin at `max(6, perm_dist[p], ori_dist[o])`. At bound `b`, the search
explores prefixes of length `b-5` and asks whether the resulting coordinate
has an exact suffix of length at most five. Bounds still increase one at a
time. Abstract-distance pruning and same-face pruning are retained.

Why does the first successful bound remain optimal? Every shortest path of
length `b` has a prefix of length `b-5` and a shortest suffix of length five.
The prefix is enumerated unless an admissible lower bound rules it out, which
cannot happen for a valid shortest path. If lookup found a suffix shorter than
five at the first successful bound, its prefix plus suffix would be a shorter
solution, and an earlier bound would already have succeeded. Roots outside
the ball cannot have a solution shorter than six. Likewise, a suffix starting
on the same face as the last prefix move cannot invalidate optimality: merging
those moves would imply a shorter solution. The lookup need not carry a
previous-face restriction. Suffix reconstruction strictly decreases distance,
so it terminates at the solved coordinate.

The assembly search is reorganized to keep current coordinates, remaining
moves, the next move, and the excluded face in registers. Each 32-byte frame
saves parent coordinates and the state needed to resume enumeration. Parent
quarter-turn results survive descent. A leaf performs the exact lookup, then
writes the prefix's final move and reconstructs the suffix. The search allocates
320 stack bytes and preserves s0 through s7; the existing public wrapper
preserves its own saved registers. Total frame allocation is 384 bytes,
including the wrapper. Input validation, coordinate ranking, C source, and
output-capacity behavior are unchanged.

| Quantity | Quarter-turn checkpoint | Radius-five checkpoint |
| --- | ---: | ---: |
| Assembly static data, including alignment | 40,385 bytes | 99,368 bytes |
| Assembly code | 1,356 bytes | 1,468 bytes |
| Code plus static data | 41,741 bytes | 100,836 bytes |
| Assembly benchmark cycles per call | 140,743.8 | 19,910.8 |
| Instructions for `21345671111111` | 10,553,435 | 1,230,539 |
| Official tests per optimization level | 51 pass / 1 fail | 52 pass / 0 fail |
| C / assembly benchmark checksum | 29 / 29 | 29 / 29 |

Clean official grading is now 55/55. Assembly is 5.19 times as fast as the
best C build, which remains 103,318.0 cycles per call. The O3 benchmark totals
are 119,492 cycles for assembly and 619,935 for C, each with 27 cycles of
harness overhead over six calls. Division after subtracting that overhead
produces the per-call figures above. Exact lookup makes shallow roots cheap
and removes the expensive last five search levels for deeper roots. The memory
increase is 58,983 bytes including alignment and remains below 128 KiB even
when code is included. Instruction restrictions and hygiene checks pass.

Supplementary target verification uses a separate temporary harness and leaves
the instructor's tests unchanged. A host BFS computed exact distances for all
3,674,160 states to select references. The target then checked every state at
distances zero through five, every one of the 2,644 distance-eleven states,
and deterministic samples spread over coordinates at distances six through
ten. Each call checked exact length, independently replayed the move string
on cubies, and measured retired instructions using the harness counter helper.
All 20,013 selected states passed.

| Depth | Target states checked | Maximum measured instructions |
| --- | ---: | ---: |
| 0 | 1 | 757 |
| 1 | 9 | 900 |
| 2 | 54 | 1,035 |
| 3 | 321 | 1,182 |
| 4 | 1,847 | 1,337 |
| 5 | 9,992 | 1,485 |
| 6 | 1,045 | 2,089 |
| 7 | 1,025 | 6,537 |
| 8 | 1,025 | 31,954 |
| 9 | 1,025 | 181,543 |
| 10 | 1,025 | 1,088,853 |
| 11 | 2,644 | 3,383,998 |

The depth-eleven maximum occurs at `54721631111111`. The maxima at depths
six through ten are sample maxima, not exhaustive target measurements. For
those remaining roots, even ignoring all pruning and early successes, bounds
six through ten generate at most
`9 * sum(L=1..5, sum(i=0..L-1, 6^i)) = 16,785` candidate edges. A conservative
charge of 256 instructions per candidate covers coordinate updates, a lookup
with at most four comparisons, and amortized frame/face-skip work; internal
candidates cost less than that. Reserving another 4,096 instructions for root
setup, validation, reconstruction, and output gives an upper bound of
`16,785 * 256 + 4,096 = 4,301,056`. Together with exhaustive radius-five and
distance-eleven measurements, this establishes margin below 7,500,000 without
claiming a target sweep of every state. The numerical answer remains exact:
there is no approximation error in distance or in the returned path.

These supplementary sources and logs are temporary session artifacts, not new
required tools in the repository. They are kept under `/tmp/rubik-radius5-*`;
that location is not durable storage. The committed generator retains the
reproducible radius-five derivation, transition checks, and descending-move
selection. Official grading is reproducible with the command at the start of
this note. Table regeneration is deterministic and was checked by comparing
SHA-256 before and after a second generation.

A complete distance-eleven membership set was **not** present in checkpoint
three. That version already passes the assignment limits. Its lookup is
preserved at [7107364](https://github.com/ddc0330/arch2026-progs/blob/7107364beb883f6d5faf09f295d1673595f8f48f/src/rubik/rubik.S#L359-L385):

```asm
lhu     t1, 0(t0)
lhu     t2, 2(t0)
```

These loads obtain the prefix offsets for one permutation and the next one.
Their difference is that permutation's orientation bucket size. Binary search
is confined to this half-open interval, avoiding a search over all 12,224
records. Empty intervals return a miss safely.

### Checkpoint 4: prove which roots can skip smaller bounds

The radius-five version still repeats searches at bounds six through ten for
roots that can only be solved in eleven moves. The hypothesis is to retain a
complete exact set of those roots and skip these unsuccessful bounds. This is
a time-space tradeoff for the hardest states; it is not necessary to fix a
correctness defect in checkpoint three.

The generator now continues the same host-side BFS until every coordinate is
visited. Its distance populations are:

```
0:1  1:9  2:54  3:321  4:1847  5:9992  6:50136
7:227536  8:870072  9:1887748  10:623800  11:2644
```

All 3,674,160 states are reached. Only the radius-five records and the 2,644
keys at distance eleven are emitted; the full distance array is host scratch
memory and is not part of the target executable. The existing quarter-turn
composition checks are retained. Radius-five records and both abstract distance
arrays have the same values as checkpoint three.

A key is `(permutation << 10) | orientation`. Since permutation is at most
5,039 and orientation at most 728, the two fields do not overlap and the largest
possible key is 5,160,664. It fits in 23 unsigned bits. Iterating permutation
then orientation emits strictly increasing keys. Each key occupies an aligned
32-bit word, adding exactly `2644 * 4 = 10,576` bytes. Binary search needs at
most twelve comparisons. The target forms keys with a shift and OR, and forms
word addresses with a shift and addition, all using RV32I instructions.

The root is first checked against the radius-five table, so shallow roots
never pay for the new lookup. For every other root, a successful membership
lookup initializes the bound to eleven. A miss leaves the previous initial
bound unchanged. No lookup occurs in the DFS candidate loop. All prefix search,
pruning, suffix reconstruction, validation, and output behavior is unchanged.
The search stack requirement remains 384 bytes including the public wrapper.

Why can this skip preserve optimality? Unit-cost BFS gives exact distances,
and every key in this complete set has distance eleven. There is therefore no
solution at any smaller bound for a member. For a nonmember, no bound is skipped
beyond the already admissible initial lower bound. Membership does not rely on
any particular grading input, and the full set is computed from the original
transitions rather than copied from a test vector list.

| Quantity | Radius-five checkpoint | Distance-eleven checkpoint |
| --- | ---: | ---: |
| Assembly static data, including alignment | 99,368 bytes | 109,944 bytes |
| Assembly code | 1,468 bytes | 1,548 bytes |
| Code plus static data | 100,836 bytes | 111,492 bytes |
| Assembly benchmark cycles per call | 19,910.8 | 19,971.5 |
| Instructions for `21345671111111` | 1,230,539 | 251,151 |
| Maximum over all distance-eleven roots | 3,383,998 | 2,402,538 |
| Official tests per optimization level | 52 pass / 0 fail | 52 pass / 0 fail |
| C / assembly benchmark checksum | 29 / 29 | 29 / 29 |

The distance-eleven maximum, still at `54721631111111`, falls by 981,460
instructions, about 29 percent. The original failing state improves even more
because much of its previous work was spent proving the smaller bounds fail.
However, the official benchmark has no distance-eleven root: its measured cost
increases by about 60.7 cycles per call, or 0.30 percent. The new set lookup is
extra work for those nonmembers. The official speedup over the best C build
therefore changes from 5.19x to 5.17x, despite the lower worst-case search cost.
These are different objectives and both effects must be reported.

Clean grading remains 55/55. The O3 benchmark reports 119,856 assembly cycles
for six calls with 27 cycles of overhead; C remains at 619,935 cycles under the
same accounting. Code plus static data is below 131,072 bytes. RV32I/Zicsr,
footprint, hygiene, and C/assembly consistency checks pass. No tests, header,
Makefile, original C table file, or C implementation was changed.

The same independent temporary target harness rechecked all 20,013 selected
states against host BFS distances, replayed their output moves, and enforced
the instruction budget. Coverage and measured maxima are:

| Depth | Target states checked | Maximum measured instructions |
| --- | ---: | ---: |
| 0 | 1 | 757 |
| 1 | 9 | 900 |
| 2 | 54 | 1,035 |
| 3 | 321 | 1,182 |
| 4 | 1,847 | 1,337 |
| 5 | 9,992 | 1,485 |
| 6 | 1,045 | 2,217 |
| 7 | 1,025 | 6,665 |
| 8 | 1,025 | 32,082 |
| 9 | 1,025 | 181,671 |
| 10 | 1,025 | 1,088,971 |
| 11 | 2,644 | 2,402,538 |

All checked states pass. Depths zero through five and eleven are exhaustive
on the target; depths six through ten are samples. The latter roots retain
the same DFS work bound as checkpoint three. Their one root membership lookup
has at most twelve comparisons and fits comfortably within the conservative
4,096-instruction root/setup allowance used there. The resulting all-input
upper bound of 4,301,056 for those depths still lies below 7,500,000. This is a
conservative bound, not a claim that the target measured that many instructions.
Together with the exhaustive deepest-state measurements it verifies the budget
without representing a full target sweep of all 3,674,160 states.

The extra measurement logs are temporary files under `/tmp/rubik-depth11-*`.
The only retained host tool is the table generator. A second generation is
checked for identical SHA-256 output, and ordinary grading requires no Python
table-generation step. The final root lookup is pinned at
[7b864c1](https://github.com/ddc0330/arch2026-progs/blob/7b864c15a95ac12b1f9d467913c18024d2c4a90f/src/rubik/rubik.S#L428-L452):

```asm
slli    a0, s4, 10
or      a0, a0, s5
```

These instructions form the exact membership key without multiplication.
The following binary search compares that key with aligned words. Only an
exact hit sets the initial bound to eleven; a miss retains the admissible
initial bound. The table is independently reproducible from the
[generator at the same commit](https://github.com/ddc0330/arch2026-progs/blob/7b864c15a95ac12b1f9d467913c18024d2c4a90f/tools/rubik/gen_search_tables.py).

The completed Rubik checkpoint history is:

| Version | Pinned commit | Main result |
| --- | --- | --- |
| API and original IDA* | `c12c3c22449d556469a87395e9b6f3de0ed90ff4` | Reproduce the depth-eleven budget failure |
| Quarter-turn compression | `7c0017ae7fbb689fc0f6e7cfdb671d94f1f3250c` | Recover table space |
| Exact short suffixes | `7107364beb883f6d5faf09f295d1673595f8f48f` | Pass all official Rubik checks |
| Deepest-state bound selection | `7b864c15a95ac12b1f9d467913c18024d2c4a90f` | Reduce hardest-state search work |

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
