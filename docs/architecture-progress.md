# Four Applications on RV32I: Arithmetic, Search, and Measured Optimization

[TOC]

This project implements BF16 arithmetic, binary GCD, bitwise/fixed-point arithmetic, and an optimal 2×2×2 Rubik's Cube solver in C and hand-written assembly. The goal is to preserve each function's exact contract while reducing work on an integer-only processor.

All code excerpts below link to the [tested repository snapshot][repo]. Historical links identify the individual optimization steps. Tests and grading limits were not modified.

## Experimental setup

| Item | Configuration |
|---|---|
| Target | RV32I + Zicsr, ILP32; no M, floating-point, or compressed instructions |
| Compiler | GCC 14.2.0; `-march=rv32i_zicsr -mabi=ilp32 -ffreestanding -fno-pic -fno-stack-protector`; `-O1`, `-O2`, `-O3`, `-Os` |
| Emulator | rv32emu interpreter, system emulation and ELF loader; revision `8e525ae4ceb858f9f63b9010b9329be70c7d4a1c` |
| Code snapshot | `1742b4081ca82b6c2ec21dd78cd50db29d96b64f` |
| Measurement date | November 9, 2026 |

In this emulator, **`cycle` and `instret` count executed guest instructions identically**. Every performance figure below is therefore both cycles/call and retired instructions/call, rather than a physical processor timing result. The harness subtracts counter, input-load, checksum, and loop overhead:

$$
C_{\text{call}}=\frac{C_{\text{measured}}-C_{\text{baseline}}}{N}.
$$

Counters and differences are unsigned 64-bit values. The harness reads high–low–high and retries on rollover; implementation objects never access counters or issue environment calls. Assembly columns use the `-O2` caller. Speedup ratios compare the best C build with assembly in that same ELF; caller differences can shift the displayed assembly column by a fraction of an instruction. Historical assembly was reassembled against the same current harness and C objects; those rows measure the named routine, rather than claiming every function was implemented at each early checkpoint. Small differences from earlier notes reflect caller/build differences, not changed arithmetic.

## 1. BFloat16 arithmetic

### Representation and conversion

BF16 stores one sign bit $s$, eight exponent bits $E$, and seven fraction bits $f$. For normal values,

$$
x=(-1)^s(1+f/128)2^{E-127},\qquad 1\le E\le254.
$$

It has eight significant binary digits. Its smallest positive normal is $2^{-126}$; its largest finite magnitude is $(2-2^{-7})2^{127}$. Subnormals use $x=(-1)^sf2^{-133}$, so their spacing is $2^{-133}$. Exponent 255 represents infinity when $f=0$, otherwise NaN. Within a normal binade, spacing is $2^{E-134}$.

Binary32 and BF16 share the exponent layout. Write the binary32 pattern as retained half $H$ and discarded half $L$. Round-to-nearest, ties-to-even increments $H$ when $L>\mathtt{0x8000}$, or when $L=\mathtt{0x8000}$ and $H$ is odd. This is equivalent to adding $\mathtt{0x7FFF}+(H\mathbin{\&}1)$ before shifting:

```c
uint32_t lsb = upper & 1u;
uint32_t rounded = f32bits + 0x7FFFu + lsb;
return (uint16_t) (rounded >> 16);
```

[Conversion source][bf-convert]. The added bias carries into the retained half exactly when rounding requires it. Finite overflow can produce infinity; sufficiently small inputs become subnormal or zero. Exponent-255 inputs bypass rounding and return the upper half unchanged. Consequently, a binary32 NaN whose payload exists only in the discarded half can become infinity; this is the assignment's bit-pattern contract, not general NaN preservation.

Without overflow, normal-result relative rounding error is at most $2^{-8}=0.390625\%$. Near zero, use the subnormal absolute bound $2^{-134}$ instead of a uniform small relative bound.

### Multiplication

For a normalized significand $S=128+f$,

$$
x=(-1)^s\frac{S}{128}2^{E-127}.
$$

Normalize a nonzero subnormal by starting with $S=f$, $E=1$, then doubling $S$ and decrementing $E$ until $128\le S\le255$. This preserves its value. For two normalized operands, $P=S_aS_b$ lies in $[16384,65025]$ and fits in 16 bits. The product sign is $s_a\oplus s_b$, and normalization gives

$$
(S_r,E_r)=
\begin{cases}
(P\gg8,\ E_a+E_b-126),&P\ge2^{15},\\
(P\gg7,\ E_a+E_b-127),&P<2^{15}.
\end{cases}
$$

The exponent adjustment compensates for shifting the product by one extra bit. Discarding the low bits truncates toward zero. For finite normal results, error is below one ULP, giving relative error below $2^{-7}=0.78125\%$. A host double-precision comparison over all $128^2=16,384$ normalized significand pairs measured a maximum of **0.769184%**; exponent scaling preserves this relative error away from overflow and underflow.

RV32I has no multiply instruction. Assembly computes $AB=\sum_i b_i(A\ll i)$ in at most eight multiplier-bit iterations:

```asm
andi    a5, t6, 1
beq     a5, zero, .Lmul_product_skip
add     a4, a4, t5
```

[Product loop][bf-product]. The test selects whether to add the current shifted multiplicand; subsequent shifts advance to the next multiplier bit. Local register control avoids the general multiplication helper used by C.

Special cases are deliberately ordered: operand `a` is inspected before `b`. An `a` NaN is returned unchanged; infinity times zero produces `0x7FC0`; an infinite `a` with a NaN `b` returns signed infinity. These bit patterns are not always commutative. Overflow returns signed infinity. For $E_r\le0$, the code **removes the hidden bit before shifting** the remaining fraction, and returns signed zero for $E_r<-6$. For example, `0x0080 × 0x3F00` returns zero although the mathematical product is a representable subnormal. The normal-result error bound does not cover this branch; correctness there means matching the specified implementation behavior.

### Square root

For a positive normal input, write $x=(m/128)2^e$. If $e$ is odd, replace $(m,e)$ by $(2m,e-1)$; the value is unchanged and the exponent is now even. The ideal output significand is $q\approx\sqrt{128m}$, with output exponent $e/2+127$.

```c
if ((mid * mid) / 128u <= m)
    low = mid;
else
    high = mid - 1u;
```

[Square-root search][bf-sqrt]. The predicate is monotone, so binary search over `[90,256]` finds its largest satisfying integer. Crucially, the division truncates: the predicate is equivalent to $q^2<128(m+1)$, not $q^2\le128m$. Thus the selected value is $\lfloor\sqrt{128(m+1)-1}\rfloor$, an approximation rather than a correctly rounded square root. Assembly implements each square by shift-and-add and division by 128 by a shift. Even-exponent halving also becomes a shift.

A host sweep of all **32,512 positive normal encodings**, compared with double-precision `sqrt`, measured maximum relative error **0.388351%**, first at `0x0081 → 0x2000`. The official tests independently require monotonicity and $|r^2/x-1|\le1\%$. This residual implies $|r/\sqrt{x}-1|\le1-\sqrt{0.99}\approx0.501256\%$; the measured maximum satisfies it.

NaNs pass through, positive infinity remains infinity, and negative nonzero non-NaN inputs produce `0x7FC0`. Both signed zeros and positive subnormals return positive zero. Flushing positive subnormals gives 100% relative error there, so the normal-input bound must not be extended to them.

### Verification, optimization, and use

[BF16 tests][bf-tests] compare conversion with an independent discarded-half comparison, and multiplication/square root with golden vectors and hashes. Coverage includes:

| Operation | Coverage per implementation |
|---|---|
| Conversion | 40 directed cases; $16\times65536$ low-half sweep; $65536\times5$ rounding-boundary sweep |
| Multiplication | 61 directed cases; $256^2$ characteristic pairs; all 65,536 encodings against eight constants; algebraic/class checks |
| Square root | 40 directed cases; all 65,536 encodings; all positive normals checked for monotonicity and residual error |

The multiplication sweeps are broad coverage, not an exhaustive test of all $2^{32}$ operand pairs. Host error sweeps measure mathematical accuracy separately from matching the assignment's bitwise results.

The commit sequence introduced [conversion][bf-convert-commit], [C multiplication][bf-mul-c-commit], [assembly multiplication][bf-mul-commit], then [square root][bf-sqrt-commit]. Initially, conversion cost 12.25 instructions/call against the best C result of 12.0625. A final [special-value check optimization][bf-check-commit] removes one instruction on every input:

```asm
lui     t0, 0xff000
slli    t1, a0, 1
bgeu    t1, t0, .Lfrom_f32_special
```

[Optimized conversion source][bf-check]. Left shift discards the sign and places the eight exponent bits in bits 31–24. The unsigned result is at least `0xFF000000` exactly when the original exponent is 255, regardless of its fraction. This replaces shift/mask/constant/equality with constant/shift/comparison, preserving every result. All directed and half-word sweeps pass at all four optimization levels. Conversion falls to **11.25 instructions/call**, its measured performance-check maximum falls from 15 to 14, and the BF16 assembly object shrinks from 696 to 692 bytes. The speedup changes from 0.98× to **1.07×**. Multiplication and square root retain their 1.19× and 1.15× gains from bounded local products.

The linked GCC `-O1` conversion first copies its input and extracts the retained half, then uses a mask test. GCC `-Os` multiplication and square root call `__mulsi3`, preserving registers around those calls; the hand-written versions are leaf routines with local bit-product loops. These are concrete disassembly differences, not assumed pipeline effects.

BF16 is useful for compact numerical storage and machine-learning workloads, often with wider accumulation. On this integer-only target, storage savings remain, but arithmetic must be emulated. The unusual underflow and special-value rules must be considered before reusing these routines outside the assignment.

## 2. Binary GCD

### Algorithm and integer invariants

For unsigned 32-bit inputs, the required range is $[0,2^{32}-1]$, with $\gcd(a,0)=a$ and $\gcd(0,0)=0$. Binary GCD replaces division using

$$
\gcd(2a,2b)=2\gcd(a,b),\qquad
\gcd(2a,b)=\gcd(a,b)\quad(b\text{ odd}),
$$

$$
\gcd(a,b)=\gcd(a,b-a)\quad(0<a\le b).
$$

Remove shared factors of two and remember their count $k$. Make both remaining operands odd, order them, subtract the smaller from the larger, and strip powers of two from the difference. These identities preserve the GCD; each nonterminal subtraction reduces the positive operands, ensuring termination. Restore $2^k$ at the end.

The shared shift is at most 31 for nonzero operands. Subtraction occurs only after ordering, so there is no unsigned underflow. The final result fits the input range. This is exact integer arithmetic: quantization, numerical approximation, and rounding do not apply.

```asm
srli    a1, a1, 1
andi    t1, a1, 1
beqz    t1, .Lstrip_b
```

[Difference-stripping loop][gcd-loop]. A nonzero difference of two odd values is necessarily even, so its first shift is unconditional. This avoids repeating a general parity test. Additional exits exploit $\gcd(1,x)=1$, including after normalization, while preserving the remembered common factor. In the linked GCC `-O1` listing, subtraction returns to `.L7`, whose `andi`/`beq` tests parity before shifting. The hand-written `.Lstrip_b` performs the known-safe first shift immediately, and its one-operand exits avoid entering that loop.

### Measured optimization and verification

| Version | Cycles/instructions per call | Function bytes |
|---|---:|---:|
| [Original assembly][gcd-base] | 120.1 | 112 |
| [Early exits and parity-loop specialization][gcd-opt] | 87.8 | 152 |
| Best C, `-O1` | 101.6 | 140 |

The optimized version trades 40 bytes for less loop work. Against the best C build it is **1.16× faster**, or about **13.6% fewer instructions**, not 16% fewer. RV32I's missing divider motivates binary GCD; the hand-written improvement comes from exploiting known parity and termination conditions rather than changing the mathematical result.

[GCD tests][gcd-tests] check all **65,536 pairs below 256** against Euclid, all 1,024 power-of-two exponent pairs, shared factors of two, 2,048 generated pairs with symmetry/divisibility checks, Fibonacci identities through $F_{47}$, and 4,096 extra C/assembly comparisons. Zero, equality, coprime pairs, and 32-bit extremes cover the control-flow boundaries. The host Euclidean/reference calculations provide exact answers, so any mismatch is an error rather than an approximation tolerance.

Applications include reducing rational numbers and finding common periods in integer schedules. The same parity identities remain useful on small processors without division hardware.

## 3. Bitwise arithmetic and Q11.20 multiplication

### Exact bitwise operations

For unsigned 32-bit words,

$$
a+b=(a\oplus b)+2(a\mathbin{\&}b).
$$

`op1` repeatedly replaces the operands with the partial sum and shifted carry:

```c
uint32_t c = (a & b) << 1;
a = a ^ b;
b = c;
```

[Adder source][fixed-add]. Each iteration preserves the sum modulo $2^{32}$. Carries move left and disappear within 32 passes. The returned pass count is observable, so replacing the loop with `add` would violate the contract. Overflow wraps; adding zero takes zero passes.

Two's complement gives $a-b=a+(\sim b+1)\pmod{2^{32}}$. `op2` uses a direct `sub` because it does not expose an adder pass count. For the average, the same sum identity gives

$$
\left\lfloor\frac{a+b}{2}\right\rfloor
=(a\mathbin{\&}b)+((a\oplus b)\gg1).
$$

[Subtraction and average][fixed-basic]. The right side obtains the exact unsigned average without overflowing an intermediate sum; the result is between the inputs. All three routines are exact in their specified integer domains.

### Q format, product, and error

A signed stored integer $A$ represents $x=A2^{-20}$: one sign bit, eleven integer-magnitude bits, and twenty fractional bits. Therefore

$$
-2048\le x\le2048-2^{-20},\qquad\Delta=2^{-20}.
$$

Since $xy=AB2^{-40}$, the stored result must approximate $AB2^{-20}$. Adding half a stored unit before flooring gives

$$
R=\left\lfloor\frac{AB+2^{19}}{2^{20}}\right\rfloor,
$$

then only the low 32 bits are retained. Ties round toward **positive infinity**: `q_mul(3,524288)=2`, while `q_mul(-3,524288)=-1`. Overflow wraps rather than saturates. When the rounded result fits the format, multiplication's absolute quantization error is at most $2^{-21}$; this excludes prior input-quantization error and wraparound.

The C routine avoids an unavailable 64-bit multiplication helper by splitting unsigned magnitudes into 16-bit halves:

$$
|A||B|=A_LB_L+(A_LB_H+A_HB_L)2^{16}+A_HB_H2^{32}.
$$

Each partial product fits unsigned 32 bits. Magnitudes include $2^{31}$ for `INT32_MIN`, so the complete product is at most $2^{62}$ and fits signed 64 bits even after rounding bias. Sign restoration precedes rounding. [C product source][fixed-product-c] uses GCC's arithmetic signed right shift and 32-bit narrowing behavior; those target conventions implement the required floor and wrap semantics.

Assembly holds the 64-bit multiplicand and accumulator in register pairs and consumes multiplier bits by shift-and-add. Its low-word addition propagates carry explicitly:

```asm
add     t1, t1, a0
sltu    t5, t1, a0
add     t2, t2, t0
add     t2, t2, t5
```

[Accumulator source][fixed-product-asm]. Unsigned wrap makes the new low word smaller than the addend exactly when a carry occurred. The high word receives both the high multiplicand and that carry. After sign restoration and rounding, shifts combine product bits `[51:20]` into the returned word. No M-extension instruction is required.

### Optimization and verification

| Routine/version | Cycles/instructions per call | Function bytes |
|---|---:|---:|
| `op1`: [baseline][add-base] | 27.4 | 40 |
| `op1`: [remove carry copy][add-copy] | 24.8 | 36 |
| `op1`: [initial check plus backward branch][add-loop] | 22.1 | 36 |
| `q_mul`: [32-step baseline][q-base] | 356.9 | 160 |
| `q_mul`: [remove accumulator copy][q-copy] | 348.1 | 156 |
| `q_mul`: [two bits per iteration][q-two] | 316.1 | 200 |
| `q_mul`: [four bits per iteration][q-four] | 300.1 | 288 |

For `op1`, writing carry directly to its destination removes a copy; moving the initial zero check outside the loop removes an unconditional loop-back jump. For `q_mul`, processing 32 bits in 16 then 8 loop iterations reduces loop-control work, while increasing code size. The mathematical product and number of processed bits stay unchanged. The final multiplication is **1.08×** faster than the best current C build, not 1.06×. Direct subtraction and the already compact average match C: their linked listings need only `sub; ret` and `xor; srli; and; add; ret`, respectively. There is no redundant arithmetic instruction to remove from these leaf bodies.

[Fixed-point tests][fixed-tests] cover a $64\times64$ characteristic operand grid, generated pairs, carry-chain pass counts, modulo identities, signed extremes, rounding ties, overflow, and 4,096 cross-implementation comparisons. Product tests compare with a signed 64-bit reference and check algebraic properties. A separate host check compared **110,144 pairs** with Python's exact integer $AB$, floor division, and explicit low-word wrapping: 144 boundary pairs, 100,000 full-range pairs, and 10,000 bounded pairs, using seed `20261109`. All matched. Among the 10,585 representable rounded results, maximum absolute error reached $2^{-21}$. These checks are not exhaustive over all 64-bit input pairs; the error bound follows from the rounding formula, not sampling alone.

Fixed-point scaling is useful in geometry, signal processing, and control when the required range is known. Q11.20 offers constant resolution and integer-only execution; applications must keep rounded results within range or deliberately accept wraparound.

## 4. Optimal 2×2×2 Rubik's Cube solver

### Exact coordinates and admissible search

Fixing one corner leaves seven movable cubies. If $c_i$ counts later cubies smaller than cubie $i$, the permutation rank is

$$
p=\sum_{i=0}^{6}c_i(6-i)!,\qquad0\le p<5040.
$$

The seven twists are in $\{0,1,2\}$ and sum to zero modulo three. The first six determine the seventh, giving

$$
o=\sum_{i=0}^{5}o_i3^{5-i},\qquad0\le o<729.
$$

The state space has $5040\times729=3,674,160$ states. Both coordinates fit unsigned 16 bits; ranking and addresses use 32-bit registers without overflow. These are exact encodings, with no rounding or approximation. The move metric counts each of `R R2 R' B B2 B' D D2 D'` as one move.

The original IDA* uses

$$
h(p,o)=\max(d_p[p],d_o[o]).
$$

Every full solution also solves each projected coordinate, so each abstract distance is a lower bound. Their maximum is admissible; their sum need not be. Increasing the depth bound from this lower bound makes the first successful search optimal. Consecutive moves on one face combine into at most one move, so skipping them cannot remove a shortest path.

### Four measured checkpoints

| Checkpoint | Cycles/instructions per call | `.rodata` bytes | Code + data bytes |
|---|---:|---:|---:|
| [Original IDA* port][rubik-one] | 130,413.0 | 109,611 | 110,943 |
| [Quarter-turn transitions][rubik-two] | 140,743.5 | 40,385 | 41,741 |
| [Exact suffixes within five moves][rubik-three] | 19,910.5 | 99,368 | 100,836 |
| [Distance-eleven membership][rubik-four] | 19,971.2 | 109,944 | 111,492 |

The original depth-eleven failure was an instruction-budget failure: `21345671111111` retired **9,773,561** instructions against a 7,500,000 limit. Its counts across the four versions were 9,773,561; 10,553,435; 1,230,539; and 251,151. These are measurements of that input, not four global worst cases.

**First, recover table space.** Keep only three quarter-turn transitions. Composition produces the half and inverse turns: $Q_f^2$, $Q_f^3$, with $Q_f^4=I$. The generator checks all **51,921 original coordinate transitions** against these compositions. Each row shrinks from eighteen bytes to six; RV32I forms offsets with $6p=(p\ll2)+(p\ll1)$. Cached intermediate turns must be stored before pruning and preserved across descent. The extra selection/stores initially make search slower, but recover space for the next table.

**Second, replace the last five search levels.** Host BFS constructs the exact radius-five ball of 12,224 states. Group records by permutation and sort by orientation. A 5,041-entry `uint16` prefix array delimits the buckets:

```asm
lhu     t1, 0(t0)
lhu     t2, 2(t0)
```

[Bucket lookup][rubik-lookup]. These loads obtain the beginning and end of one permutation's interval. The largest bucket has eleven records, requiring at most four binary comparisons. Each aligned 32-bit record stores `(o << 8) | (distance << 4) | move`; the fields do not overlap. Move 15 marks solved. The added offset and record tables occupy 10,082 and 48,896 bytes before alignment.

A root within five moves follows stored distance-decreasing moves directly. Otherwise, bound $b$ explores prefixes of length $b-5$, then appends an exact suffix. Every shortest $b$-move path has such a prefix and suffix. A shorter successful suffix would imply a solution at an earlier bound, so the first success remains optimal. This removes substantial search work instead of merely making each generated move cheaper.

**Third, skip provably unsuccessful bounds.** Continue host BFS over the full state graph and emit only the 2,644 distance-eleven coordinates, sorted as `(p << 10) | o`:

```asm
slli    a0, s4, 10
or      a0, a0, s5
```

[Root membership lookup][rubik-membership]. Orientation fits in ten bits, so the key is exact and fits in 23 bits. Binary search needs at most twelve comparisons. A hit proves all smaller bounds impossible and starts at eleven; a miss retains ordinary iterative deepening. The set is complete and derived from transitions, not from grading vectors.

This adds **10,576 bytes**. The maximum over all distance-eleven states falls from **3,383,998 to 2,402,538 instructions**, about 29%. The timed benchmark contains no distance-eleven root, so its extra membership checks instead add about **60.7 instructions/call**. Report both outcomes: hardest-state work improves while that benchmark slightly regresses.

### Memory, verification, and use

The final assembly has 1,548 code bytes and 109,944 table bytes, totaling **111,492 bytes**. The grader's 128 KiB limit counts code as well as allocated data; debug information is excluded. No writable static state or heap is used. Stack frames total 384 bytes, including the ABI-preserving public wrapper. The [host generator][rubik-generator] retains reproducible table derivation; its full BFS scratch array is not linked into the target. The C solver and original C tables remain unchanged.

[Official tests][rubik-tests] cover depths 0–11, every single move, a descending solution chain, invalid digits/permutations/twist sums, output capacities, solution replay, and C/assembly length consistency. Invalid input leaves output untouched; insufficient capacity returns `-2` and clears the first byte when capacity permits. A valid but longer path is incorrect.

Supplementary target checks used exact host-BFS distances and independent cubie replay:

| Depth | States checked | Maximum measured instructions |
|---|---:|---:|
| 0–5 | All 12,224 | 1,485 |
| 6 | 1,045 | 2,217 |
| 7 | 1,025 | 6,665 |
| 8 | 1,025 | 32,082 |
| 9 | 1,025 | 181,671 |
| 10 | 1,025 | 1,088,971 |
| 11 | All 2,644 | 2,402,538 |

All **20,013 selected states** passed. The deepest maximum occurs at `54721631111111`. Depths 6–10 are samples, not exhaustive target sweeps. For all roots in those depths, ignoring pruning and early success gives at most

$$
9\sum_{L=1}^{5}\sum_{i=0}^{L-1}6^i=16,785
$$

candidate edges across bounds 6–10. A conservative charge of 256 instructions per edge covers transitions, bounded lookup, and amortized frame/face-skip work; 4,096 more cover root setup, ranking, reconstruction, and output. The bound is **4,301,056**, below 7,500,000. Combined with the exhaustive shallow/deepest measurements, this covers the instruction limit without claiming every state was executed on the target. The full graph was traversed only on the host.

The transferable technique is to combine exact state coordinates, admissible lower bounds, and small precomputed suffix sets. Similar time-space tradeoffs apply to bounded planning problems when a complete state table would exceed embedded memory.

## 5. Final results and reproduction

### Compiler disassembly versus hand-written assembly

`make dump` produces linked ELF listings under `build/<program>/<opt>/`. The following GCC `-O2` excerpt comes from the linked [C bitwise adder][fixed-add]; addresses and debug labels are omitted:

```asm
and     a3, a0, a1
addi    a4, a1, 0
slli    a1, a3, 1
addi    a5, a5, 1
xor     a0, a0, a4
bne     a1, zero, .L3
```

GCC saves the old carry operand in `a4` before overwriting `a1`. The [hand-written loop][fixed-add-asm] orders XOR first and avoids that copy:

```asm
and     t1, a0, a1
xor     a0, a0, a1
slli    a1, t1, 1
addi    t0, t0, 1
bne     a1, zero, .Lop1_loop
```

Both retain the observable pass count. The five-instruction loop explains the measured gain over GCC's six-instruction body.

| Program | Observed compiler listing | Hand-written difference |
|---|---|---|
| BF16 | `-O1` conversion copies input and tests an exponent mask; `-Os` multiply/square root call `__mulsi3` | Three-instruction sign-dropping exponent test; leaf software-product loops without helper-call frames |
| GCD | `-O1` returns to a parity test after subtraction | Exploit the even difference and exit on one |
| Fixed-point | `-O2` adder saves old carry; product uses a 32-byte frame and four linked `__mulsi3` calls | Reorder XOR to remove the copy; a leaf register-pair product processes four bits per loop |
| Rubik | `-O2` recursive IDA* allocates an 80-byte nonterminal frame | A bounded prefix DFS uses one 320-byte allocation plus the 64-byte wrapper and exact suffix completion |

The Rubik `-O3` object contains eighteen call relocations to `ida_search`, versus two at `-O2`, with repeated move cases in both the recursive search and root code. Its `.text` grows from 1,328 to 7,528 bytes while benchmark cost falls from 117,393.3 to 103,318.0. This demonstrates a compiler speed/size tradeoff rather than a pipeline or cache effect. `-O1` is best for GCD and square root, `-Os` for BF16 multiplication, and `-O2` for the fixed-point product; stronger optimization is not uniformly faster.

To inspect the same linked function and identify helper relocations:

```sh
/home/ddc/.local/bin/rv32-objdump -d -M no-aliases \
    --disassemble=op1 build/fixed/O2/fixed.elf
/home/ddc/.local/bin/rv32-objdump -dr -M no-aliases build/fixed/O2/impl.o
```

The first is linked executable code; the second identifies relocatable helper calls, which the linker may relax. All cycle counts come from the linked ELFs. The [pinned Makefile][build-source] fixes the source inputs and compiler options used to regenerate the listings.

### Benchmark comparison

All figures below are **cycles = retired instructions per call** in rv32emu. Assembly columns use the `-O2` caller; speedups use assembly in the best-C ELF, calculated before rounding. All measurements were rerun after `make update` with emulator revision `8e525ae`.

| Function | C `-O1` | C `-O2` | C `-O3` | C `-Os` | Assembly | Speedup |
|---|---:|---:|---:|---:|---:|---:|
| BF16 conversion | 12.1 | 12.1 | 13.8 | 12.1 | 11.2 | 1.07× |
| BF16 multiplication | 95.5 | 91.3 | 92.7 | 89.2 | 75.0 | 1.19× |
| BF16 square root | 330.7 | 332.1 | 333.4 | 335.0 | 288.2 | 1.15× |
| Binary GCD | 101.6 | 116.5 | 118.8 | 119.6 | 87.8 | 1.16× |
| Bitwise adder | 24.8 | 24.6 | 26.8 | 24.6 | 22.1 | 1.11× |
| Subtraction | 4.0 | 4.0 | 5.8 | 4.0 | 4.0 | 1.00× |
| Unsigned average | 7.0 | 7.0 | 8.8 | 7.0 | 7.0 | 1.00× |
| Q11.20 product | 329.2 | 324.8 | 326.6 | 325.8 | 300.1 | 1.08× |
| Rubik solver | 112,807.0 | 117,393.3 | 103,318.0 | 104,209.2 | 19,971.2 | 5.17× |

### Footprint against the best-size C build

Select the smallest sum of allocated sections across all four C optimization levels, independently of the best-cycle choice. Sizes come from `size -A` on implementation objects, excluding the shared runtime, tests, and debug information. Fixed-point ties at `-O2`, `-O3`, and `-Os`.

| Program / build | `.text` | `.rodata` | `.data` | `.bss` | Total bytes |
|---|---:|---:|---:|---:|---:|
| BF16, C `-Os` | 724 | 0 | 0 | 0 | 724 |
| BF16, assembly | 692 | 0 | 0 | 0 | 692 |
| GCD, C `-Os` | 120 | 0 | 0 | 0 | 120 |
| GCD, assembly | 152 | 0 | 0 | 0 | 152 |
| Fixed-point, C `-O2` | 368 | 0 | 0 | 0 | 368 |
| Fixed-point, assembly | 352 | 0 | 0 | 0 | 352 |
| Rubik, C `-Os` | 1,160 | 109,687 | 0 | 0 | 110,847 |
| Rubik, assembly | 1,548 | 109,944 | 0 | 0 | 111,492 |

BF16 and fixed-point save 32 and 16 bytes. GCD spends 32 more bytes on exits and specialized control flow. Rubik spends 645 more bytes overall to reduce search work. The smallest C Rubik code is `-Os`, while its fastest is `-O3`; comparing assembly only against the latter's 7,528 code bytes would overstate the size improvement. All Rubik implementations remain below 128 KiB, including code.

### Measured instruction-budget checks

These are maxima **within the official performance-check domains**, not universal worst-case claims. Square root covers all encodings; conversion, multiplication, GCD, and fixed-point use the sweeps/grids/generated inputs described above.

| Function | C `-O2` measured / limit | Assembly measured / limit |
|---|---:|---:|
| BF16 conversion | 15 / 150 | 14 / 60 |
| BF16 multiplication | 157 / 1,000 | 166 / 400 |
| BF16 square root | 626 / 4,000 | 563 / 1,500 |
| Binary GCD | 457 / 4,000 | 317 / 1,500 |
| Bitwise adder | 201 / 1,500 | 169 / 600 |
| Subtraction | 6 / 150 | 6 / 40 |
| Unsigned average | 9 / 150 | 9 / 40 |
| Q11.20 product | 525 / 3,000 | 394 / 1,200 |

Rubik has separate limits of 50,000,000 for C and 7,500,000 for assembly. Its deepest-state measurements and remaining-depth bound are given above. A lower mean benchmark cost does not imply a lower maximum: BF16 multiplication illustrates the distinction.

### Reproduction

```sh
make clean
make CROSS_COMPILE=/home/ddc/.local/bin/rv32- update
make CROSS_COMPILE=/home/ddc/.local/bin/rv32- test
make CROSS_COMPILE=/home/ddc/.local/bin/rv32- cycles
make CROSS_COMPILE=/home/ddc/.local/bin/rv32- sanitize
```

The all-program grading result is **100/100**, with all four optimization levels passing. The `-O2` test binaries report 42 passing tests for BF16, 34 for GCD, 38 for fixed-point, and 52 for Rubik; these summaries include shared runtime tests. Instruction restrictions, benchmark checksums, memory footprint, and hygiene also pass. Host ASan/UBSan checks pass. No test or grading file was changed.

`cycles` writes `results/cycles.csv`, `results/footprint.csv`, and `results/cycles.md`. Charts are optional and were skipped because matplotlib is unavailable; the numeric measurements do not depend on plotting. Temporary historical/error sweeps were additional experiments, not changes to the grading harness. The retained Rubik generator can recreate its tables with `python3 tools/rubik/gen_search_tables.py`.

### Writing references

The organization follows the course's requested progression from representation and derivation to implementation, verification, and measured revisions: [fixed-point line drawing](https://hackmd.io/@sysprog/line-draw-fixed-point) and [BF16 approximation](https://hackmd.io/@sysprog/bf16-sine). Accessible versions discuss [fixed-point scaling and arithmetic](https://hackmd.io/@maromaSamsa/HkjefPbFs) and [precision analysis tied to implementation attempts](https://hackmd.io/@Max042004/bf16_sin). They guide presentation; this project uses integer-only implementations and its own repository history for results.

[repo]: https://github.com/ddc0330/arch2026-progs/tree/1742b4081ca82b6c2ec21dd78cd50db29d96b64f
[bf-convert]: https://github.com/ddc0330/arch2026-progs/blob/1742b4081ca82b6c2ec21dd78cd50db29d96b64f/src/bf16/bf16.c#L4-L16
[bf-product]: https://github.com/ddc0330/arch2026-progs/blob/1742b4081ca82b6c2ec21dd78cd50db29d96b64f/src/bf16/bf16.S#L137-L149
[bf-sqrt]: https://github.com/ddc0330/arch2026-progs/blob/1742b4081ca82b6c2ec21dd78cd50db29d96b64f/src/bf16/bf16.c#L150-L183
[bf-tests]: https://github.com/ddc0330/arch2026-progs/blob/1742b4081ca82b6c2ec21dd78cd50db29d96b64f/tests/tbf16.c
[bf-convert-commit]: https://github.com/ddc0330/arch2026-progs/commit/46f3d42fa8c028eac8017f8bb8c18fdd2def02e7
[bf-mul-c-commit]: https://github.com/ddc0330/arch2026-progs/commit/70de1a9ea0872ef335efc2bbbb5602e016d6e87f
[bf-mul-commit]: https://github.com/ddc0330/arch2026-progs/commit/a8a23e383bbfb6a82973e48ed232807cc87d7a2e
[bf-sqrt-commit]: https://github.com/ddc0330/arch2026-progs/commit/1a44572c7804549493be56762d90b8d5b0f09892
[gcd-loop]: https://github.com/ddc0330/arch2026-progs/blob/1742b4081ca82b6c2ec21dd78cd50db29d96b64f/src/gcd/gcd.S#L54-L69
[gcd-base]: https://github.com/ddc0330/arch2026-progs/commit/815bc6d8d8ab71ffdf09cad34184204c7a06d899
[gcd-opt]: https://github.com/ddc0330/arch2026-progs/commit/e8127fed25bd2abb726a71fcce00de238ae9ea92
[gcd-tests]: https://github.com/ddc0330/arch2026-progs/blob/1742b4081ca82b6c2ec21dd78cd50db29d96b64f/tests/tgcd.c
[fixed-add]: https://github.com/ddc0330/arch2026-progs/blob/1742b4081ca82b6c2ec21dd78cd50db29d96b64f/src/fixed/fixed.c#L4-L19
[fixed-basic]: https://github.com/ddc0330/arch2026-progs/blob/1742b4081ca82b6c2ec21dd78cd50db29d96b64f/src/fixed/fixed.c#L21-L29
[fixed-product-c]: https://github.com/ddc0330/arch2026-progs/blob/1742b4081ca82b6c2ec21dd78cd50db29d96b64f/src/fixed/fixed.c#L32-L59
[fixed-product-asm]: https://github.com/ddc0330/arch2026-progs/blob/1742b4081ca82b6c2ec21dd78cd50db29d96b64f/src/fixed/fixed.S#L103-L117
[fixed-tests]: https://github.com/ddc0330/arch2026-progs/blob/1742b4081ca82b6c2ec21dd78cd50db29d96b64f/tests/tfixed.c
[add-base]: https://github.com/ddc0330/arch2026-progs/commit/112613f2452e0c83051556e51fef790a408d80f8
[add-copy]: https://github.com/ddc0330/arch2026-progs/commit/f722440ba544be1601e6822f67dc03a3f162982c
[add-loop]: https://github.com/ddc0330/arch2026-progs/commit/ddb0ad9d2240d39eacea3261c2cb88d0b0efe787
[q-base]: https://github.com/ddc0330/arch2026-progs/commit/1446612982360d3d5e0af011834b39759aeb6931
[q-copy]: https://github.com/ddc0330/arch2026-progs/commit/820512bddfb96113d704c28792150a1985c665ee
[q-two]: https://github.com/ddc0330/arch2026-progs/commit/b67b7b0a86a4a67bfef17152b21f1caa24c56fa3
[q-four]: https://github.com/ddc0330/arch2026-progs/commit/55cc580ee67c3d597337f151beb89c293c9a2bee
[rubik-one]: https://github.com/ddc0330/arch2026-progs/commit/c12c3c22449d556469a87395e9b6f3de0ed90ff4
[rubik-two]: https://github.com/ddc0330/arch2026-progs/commit/7c0017ae7fbb689fc0f6e7cfdb671d94f1f3250c
[rubik-three]: https://github.com/ddc0330/arch2026-progs/commit/7107364beb883f6d5faf09f295d1673595f8f48f
[rubik-four]: https://github.com/ddc0330/arch2026-progs/commit/7b864c15a95ac12b1f9d467913c18024d2c4a90f
[rubik-lookup]: https://github.com/ddc0330/arch2026-progs/blob/1742b4081ca82b6c2ec21dd78cd50db29d96b64f/src/rubik/rubik.S#L359-L385
[rubik-membership]: https://github.com/ddc0330/arch2026-progs/blob/1742b4081ca82b6c2ec21dd78cd50db29d96b64f/src/rubik/rubik.S#L428-L452
[rubik-generator]: https://github.com/ddc0330/arch2026-progs/blob/1742b4081ca82b6c2ec21dd78cd50db29d96b64f/tools/rubik/gen_search_tables.py
[rubik-tests]: https://github.com/ddc0330/arch2026-progs/blob/1742b4081ca82b6c2ec21dd78cd50db29d96b64f/tests/trubik.c

[bf-check]: https://github.com/ddc0330/arch2026-progs/blob/1742b4081ca82b6c2ec21dd78cd50db29d96b64f/src/bf16/bf16.S#L12-L33
[bf-check-commit]: https://github.com/ddc0330/arch2026-progs/commit/ddd0c684e7ede93cc2510f8c650086b234b67af4
[fixed-add-asm]: https://github.com/ddc0330/arch2026-progs/blob/1742b4081ca82b6c2ec21dd78cd50db29d96b64f/src/fixed/fixed.S#L13-L28
[build-source]: https://github.com/ddc0330/arch2026-progs/blob/1742b4081ca82b6c2ec21dd78cd50db29d96b64f/Makefile#L65-L76
