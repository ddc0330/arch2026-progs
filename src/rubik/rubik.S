/*
 * rubik_solve_asm: RV32I implementation of the original 2x2x2 solver.
 *
 * Iterative deepening with exact radius-five completion. Quarter-turn
 * transitions and suffix records are derived from the original C tables.
 * No M, C, or floating-point instructions are required.
 *
 * a0 = state (14 ASCII characters plus NUL)
 * a1 = output buffer
 * a2 = output capacity
 * return: shortest move count, -1 invalid/unreachable, -2 output too small
 */

    .option norvc
    /* Public wrapper's 16-byte-aligned frame. */
    .equ WRAP_S0,        0
    .equ WRAP_S1,        4
    .equ WRAP_S2,        8
    .equ WRAP_S3,        12
    .equ WRAP_S8,        16
    .equ WRAP_S9,        20
    .equ WRAP_S10,       24
    .equ WRAP_S11,       28
    .equ WRAP_RA,        32
    .equ WRAP_PATH,      40
    .equ WRAP_SIZE,      64

    .section .text
    .balign 4

    .extern perm_next
    .extern ori_next
    .extern perm_dist
    .extern ori_dist

    .globl rubik_solve_asm
    .type rubik_solve_asm, @function
rubik_solve_asm:
    addi    sp, sp, -WRAP_SIZE
    sw      s0, WRAP_S0(sp)
    sw      s1, WRAP_S1(sp)
    sw      s2, WRAP_S2(sp)
    sw      s3, WRAP_S3(sp)
    sw      s8, WRAP_S8(sp)
    sw      s9, WRAP_S9(sp)
    sw      s10, WRAP_S10(sp)
    sw      s11, WRAP_S11(sp)
    sw      ra, WRAP_RA(sp)

    mv      s0, a0                  /* input */
    mv      s1, a1                  /* output */
    mv      s2, a2                  /* capacity */

    /* NULL input is invalid.  Do not touch output on invalid input. */
    beqz    s0, .Lrubik_invalid

    /* Validate permutation digits '1'..'7' and reject duplicates. */
    li      t0, 0                   /* i */
    li      t1, 0                   /* used bit mask */
.Lrubik_validate_perm:
    li      t2, 7
    bgeu    t0, t2, .Lrubik_validate_ori_start
    add     t2, s0, t0
    lbu     t3, 0(t2)
    li      t4, 49                  /* '1' */
    bltu    t3, t4, .Lrubik_invalid
    li      t4, 55                  /* '7' */
    bltu    t4, t3, .Lrubik_invalid
    addi    t3, t3, -49
    li      t4, 1
    sll     t4, t4, t3
    and     t5, t1, t4
    bnez    t5, .Lrubik_invalid
    or      t1, t1, t4
    addi    t0, t0, 1
    j       .Lrubik_validate_perm

    /* Validate orientation digits '1'..'3'. */
.Lrubik_validate_ori_start:
    li      t0, 0                   /* i */
    li      t1, 0                   /* orientation sum */
.Lrubik_validate_ori:
    li      t2, 7
    bgeu    t0, t2, .Lrubik_validate_sum
    addi    t2, t0, 7
    add     t2, s0, t2
    lbu     t3, 0(t2)
    li      t4, 49
    bltu    t3, t4, .Lrubik_invalid
    li      t4, 51                  /* '3' */
    bltu    t4, t3, .Lrubik_invalid
    addi    t3, t3, -49
    add     t1, t1, t3
    addi    t0, t0, 1
    j       .Lrubik_validate_ori

.Lrubik_validate_sum:
    /* Orientation sum must be divisible by three (sum is at most 14). */
    li      t2, 3
.Lrubik_mod3:
    bltu    t1, t2, .Lrubik_mod3_done
    sub     t1, t1, t2
    j       .Lrubik_mod3
.Lrubik_mod3_done:
    bnez    t1, .Lrubik_invalid

    /* Require exactly 14 characters. */
    lbu     t0, 14(s0)
    bnez    t0, .Lrubik_invalid

    /* Cache quarter-turn transitions and abstract distance tables. */
    la      s8, perm_next
    la      s9, ori_next
    la      s10, perm_dist
    la      s11, ori_dist

    /* Convert the validated input to (permutation, orientation) ranks. */
    mv      a0, s0
    call    rank_input

    /* Run the optimal prefix search. Path lives in this frame. */
    addi    a2, sp, WRAP_PATH
    call    solve_coordinates
    mv      s3, a0
    blt     s3, zero, .Lrubik_invalid

    /* Compute required output bytes, including spaces and trailing NUL. */
    li      t0, 0                   /* path index */
    li      t4, 1                   /* required bytes: NUL */
.Lrubik_size_loop:
    bgeu    t0, s3, .Lrubik_size_done
    addi    t1, sp, WRAP_PATH
    add     t1, t1, t0
    lbu     t2, 0(t1)               /* move index 0..8 */
    li      t3, 3
    bltu    t2, t3, .Lrubik_size_turn_ready
    li      t3, 6
    bltu    t2, t3, .Lrubik_size_turn_b
    addi    t2, t2, -6
    j       .Lrubik_size_turn_ready
.Lrubik_size_turn_b:
    addi    t2, t2, -3
.Lrubik_size_turn_ready:
    addi    t4, t4, 1               /* face letter */
    beqz    t2, .Lrubik_size_no_suffix
    addi    t4, t4, 1               /* '2' or apostrophe */
.Lrubik_size_no_suffix:
    beqz    t0, .Lrubik_size_no_space
    addi    t4, t4, 1               /* separator */
.Lrubik_size_no_space:
    addi    t0, t0, 1
    j       .Lrubik_size_loop

.Lrubik_size_done:
    /* NULL output or insufficient capacity returns -2. */
    beqz    s1, .Lrubik_too_small
    bltu    s2, t4, .Lrubik_too_small

    /* Emit the space-separated move names. */
    li      t0, 0                   /* path index */
    mv      t5, s1                  /* output cursor */
.Lrubik_write_loop:
    bgeu    t0, s3, .Lrubik_write_done
    beqz    t0, .Lrubik_write_move
    li      t6, 32                  /* space */
    sb      t6, 0(t5)
    addi    t5, t5, 1
.Lrubik_write_move:
    addi    t1, sp, WRAP_PATH
    add     t1, t1, t0
    lbu     t2, 0(t1)
    li      t3, 3
    bltu    t2, t3, .Lrubik_face_r
    li      t3, 6
    bltu    t2, t3, .Lrubik_face_b

    /* D, D2, D' */
    li      t3, 68                  /* 'D' */
    addi    t2, t2, -6
    j       .Lrubik_write_face
.Lrubik_face_b:
    li      t3, 66                  /* 'B' */
    addi    t2, t2, -3
    j       .Lrubik_write_face
.Lrubik_face_r:
    li      t3, 82                  /* 'R' */
.Lrubik_write_face:
    sb      t3, 0(t5)
    addi    t5, t5, 1
    beqz    t2, .Lrubik_write_next
    li      t3, 50                  /* '2' */
    li      t6, 1
    beq     t2, t6, .Lrubik_write_suffix
    li      t3, 39                  /* apostrophe */
.Lrubik_write_suffix:
    sb      t3, 0(t5)
    addi    t5, t5, 1
.Lrubik_write_next:
    addi    t0, t0, 1
    j       .Lrubik_write_loop

.Lrubik_write_done:
    sb      zero, 0(t5)
    mv      a0, s3
    j       .Lrubik_return

.Lrubik_too_small:
    /* Contract: clear out[0] only when out != NULL and cap >= 1. */
    beqz    s1, .Lrubik_too_small_ret
    beqz    s2, .Lrubik_too_small_ret
    sb      zero, 0(s1)
.Lrubik_too_small_ret:
    li      a0, -2
    j       .Lrubik_return

.Lrubik_invalid:
    li      a0, -1

.Lrubik_return:
    lw      ra, WRAP_RA(sp)
    lw      s11, WRAP_S11(sp)
    lw      s10, WRAP_S10(sp)
    lw      s9, WRAP_S9(sp)
    lw      s8, WRAP_S8(sp)
    lw      s3, WRAP_S3(sp)
    lw      s2, WRAP_S2(sp)
    lw      s1, WRAP_S1(sp)
    lw      s0, WRAP_S0(sp)
    addi    sp, sp, WRAP_SIZE
    ret
    .size rubik_solve_asm, .-rubik_solve_asm

    .globl rank_input
    .type rank_input, @function

rank_input:

    /* ------------------------------------------------------------
     * Permutation rank
     *
     * For every position i:
     *
     * smaller = number of later cubies smaller than p[i]
     * rank = rank * (7 - i) + smaller
     *
     * ASCII digits can be compared directly because their order
     * is the same as the numeric order.
     * ------------------------------------------------------------ */

    li      t0, 0              /* i */
    li      t1, 0              /* permutation rank */

.Lrank_p_outer:
    li      t3, 7
    bgeu    t0, t3, .Lrank_p_done

    add     t3, a0, t0
    lbu     t2, 0(t3)          /* input[i] */

    li      t4, 0              /* smaller */
    addi    t5, t0, 1          /* j = i + 1 */

.Lrank_p_inner:
    li      t3, 7
    bgeu    t5, t3, .Lrank_p_count_done

    add     t6, a0, t5
    lbu     t6, 0(t6)          /* input[j] */

    bgeu    t6, t2, .Lrank_p_no_inc

    addi    t4, t4, 1          /* smaller++ */

.Lrank_p_no_inc:
    addi    t5, t5, 1
    j       .Lrank_p_inner


.Lrank_p_count_done:

    /*
     * rank *= (7 - i)
     *
     * No MUL instruction because only RV32I is allowed.
     * Ranking is done only once, so repeated addition is fine here.
     */

    li      t5, 7
    sub     t5, t5, t0        /* multiplier = 7 - i */

    li      t6, 0

.Lrank_p_mul:
    beqz    t5, .Lrank_p_mul_done

    add     t6, t6, t1
    addi    t5, t5, -1

    j       .Lrank_p_mul


.Lrank_p_mul_done:

    add     t1, t6, t4        /* rank += smaller */

    addi    t0, t0, 1
    j       .Lrank_p_outer


.Lrank_p_done:

    /* ------------------------------------------------------------
     * Orientation rank
     *
     * Only the first six orientations are stored:
     *
     * o = o * 3 + orientation[i]
     *
     * input orientation characters are '1'..'3',
     * therefore subtract ASCII '1' (49).
     * ------------------------------------------------------------ */

    li      t2, 0              /* orientation rank */
    addi    t3, a0, 7          /* first orientation character */
    li      t0, 0              /* i */

.Lrank_o_loop:
    li      t4, 6
    bgeu    t0, t4, .Lrank_done

    lbu     t4, 0(t3)
    addi    t4, t4, -49        /* '1' -> 0, '2' -> 1, '3' -> 2 */

    /*
     * o * 3 = o * 2 + o
     */
    slli    t5, t2, 1
    add     t2, t5, t2
    add     t2, t2, t4

    addi    t3, t3, 1
    addi    t0, t0, 1

    j       .Lrank_o_loop


.Lrank_done:

    mv      a0, t1             /* return p */
    mv      a1, t2             /* return o */

    ret

    .size rank_input, . - rank_input
/* Lookup exact distance and first solving move for a radius-five state.
 * a0=p, a1=o; result a0=record, or -1. Only temporaries/a0 are clobbered.
 * Each permutation's bucket is sorted by orientation. */
    .type near_lookup, @function
near_lookup:
    la      t0, near_offsets
    slli    t1, a0, 1
    add     t0, t0, t1
    lhu     t1, 0(t0)
    lhu     t2, 2(t0)
    la      t0, near_records
.Lnear_loop:
    bgeu    t1, t2, .Lnear_miss
    add     t3, t1, t2
    srli    t3, t3, 1
    slli    t4, t3, 2
    add     t4, t0, t4
    lw      a0, 0(t4)
    srli    t4, a0, 8
    beq     t4, a1, .Lnear_return
    bltu    t4, a1, .Lnear_right
    mv      t2, t3
    j       .Lnear_loop
.Lnear_right:
    addi    t1, t3, 1
    j       .Lnear_loop
.Lnear_miss:
    li      a0, -1
.Lnear_return:
    ret
    .size near_lookup, .-near_lookup

/* Iterative DFS, with exact radius-five completion at the leaves.
 * Frames (32 bytes) save parent coordinates and resume registers. All saved
 * registers obey the ABI; the deepest stack usage is below 512 bytes.
 * s0=current frame, s1=path cursor, s2=bound, s3=remaining moves;
 * s4/s5=successor coordinates, s6=move, s7=excluded face first move.
 * s8..s11 are the immutable table bases installed by the public wrapper. */
    .type solve_coordinates, @function
solve_coordinates:
    addi    sp, sp, -320
    sw      s0, 280(sp)
    sw      s1, 284(sp)
    sw      s2, 288(sp)
    sw      s3, 292(sp)
    sw      s4, 296(sp)
    sw      s5, 300(sp)
    sw      s6, 304(sp)
    sw      s7, 308(sp)
    sw      ra, 312(sp)
    mv      s0, sp
    mv      s1, a2
    mv      s4, a0
    mv      s5, a1
    call    near_lookup
    bgez    a0, .Lroot_near

    /* Outside radius five, begin at six unless either abstract distance
     * proves a larger lower bound. */
    li      s2, 6
    add     t0, s10, s4
    lbu     t0, 0(t0)
    bgeu    s2, t0, .Lbound_ori
    mv      s2, t0
.Lbound_ori:
    add     t0, s11, s5
    lbu     t0, 0(t0)
    bgeu    s2, t0, .Lcheck_eleven
    mv      s2, t0
.Lcheck_eleven:
    /* Exact membership proves that smaller bounds cannot succeed. The list
     * contains every distance-eleven coordinate, not just test inputs.
     * Key = (permutation << 10) | orientation; orientation fits in 10 bits. */
    slli    a0, s4, 10
    or      a0, a0, s5
    la      t0, depth11_keys
    li      t1, 0
    li      t2, 2644
.Leleven_loop:
    bgeu    t1, t2, .Lnew_bound
    add     t3, t1, t2
    srli    t3, t3, 1
    slli    t4, t3, 2
    add     t4, t0, t4
    lw      t4, 0(t4)
    beq     t4, a0, .Lis_eleven
    bltu    t4, a0, .Leleven_right
    mv      t2, t3
    j       .Leleven_loop
.Leleven_right:
    addi    t1, t3, 1
    j       .Leleven_loop
.Lis_eleven:
    li      s2, 11
.Lnew_bound:
    mv      s3, s2
    li      s6, 0
    li      s7, 9
    sw      s4, 0(s0)
    sw      s5, 4(s0)
    sw      s7, 12(s0)
.Lsearch_loop:
    li      t0, 9
    beq     s6, t0, .Lpop
    beq     s6, s7, .Lskip_face
    /* Determine quarter-turn column; reset coordinates on each new face.
     * Successive turns of a face compose the same quarter transition. */
    li      t0, 0
    li      t1, 3
    bltu    s6, t1, .Lface_column
    li      t0, 2
    li      t1, 6
    bltu    s6, t1, .Lface_column
    li      t0, 4
.Lface_column:
    srli    t1, t0, 1
    add     t1, t1, t0         /* first move = column*3/2 */
    bne     s6, t1, .Lcompose
    lw      s4, 0(s0)
    lw      s5, 4(s0)
.Lcompose:
    slli    t2, s4, 1
    slli    t3, s4, 2
    add     t2, t2, t3         /* p*6 */
    add     t2, t2, t0
    add     t2, t2, s8
    lhu     s4, 0(t2)
    slli    t2, s5, 1
    slli    t3, s5, 2
    add     t2, t2, t3
    add     t2, t2, t0
    add     t2, t2, s9
    lhu     s5, 0(t2)
    addi    t2, s3, -1
    li      t3, 5
    beq     t2, t3, .Lleaf
    add     t3, s10, s4
    lbu     t3, 0(t3)
    bltu    t2, t3, .Lnext_move
    add     t3, s11, s5
    lbu     t3, 0(t3)
    bltu    t2, t3, .Lnext_move
    /* Save resume state and descend. */
    sw      s6, 8(s0)
    sw      s4, 16(s0)
    sw      s5, 20(s0)
    sub     t3, s2, s3
    add     t3, s1, t3
    sb      s6, 0(t3)
    addi    s0, s0, 32
    sw      s4, 0(s0)
    sw      s5, 4(s0)
    sw      t1, 12(s0)
    mv      s7, t1
    li      s6, 0
    addi    s3, s3, -1
    j       .Lsearch_loop
.Lleaf:
    mv      a0, s4
    mv      a1, s5
    call    near_lookup
    bltz    a0, .Lnext_move
    sub     t0, s2, s3
    add     s1, s1, t0
    sb      s6, 0(s1)
    addi    s1, s1, 1
    j       .Lfinish_near
.Lnext_move:
    addi    s6, s6, 1
    j       .Lsearch_loop
.Lskip_face:
    addi    s6, s6, 3
    j       .Lsearch_loop
.Lpop:
    beq     s0, sp, .Lbound_exhausted
    addi    s0, s0, -32
    addi    s3, s3, 1
    lw      s6, 8(s0)
    lw      s7, 12(s0)
    lw      s4, 16(s0)
    lw      s5, 20(s0)
    j       .Lnext_move
.Lbound_exhausted:
    lw      s4, 0(s0)
    lw      s5, 4(s0)
    addi    s2, s2, 1
    li      t0, 11
    bgeu    t0, s2, .Lnew_bound
    li      s2, -1
    j       .Lsearch_return
.Lroot_near:
    srli    s2, a0, 4
    andi    s2, s2, 15
.Lfinish_near:
    /* The record stores a move that strictly decreases exact BFS distance.
     * Repeated bucket lookups reconstruct a shortest suffix, including root
     * states at distance zero. */
    andi    t0, a0, 15
    li      t1, 15
    beq     t0, t1, .Lsearch_return
    sb      t0, 0(s1)
    addi    s1, s1, 1
    li      t1, 0              /* quarter-table column */
    li      t2, 3
    bltu    t0, t2, .Lsuffix_face
    addi    t0, t0, -3
    li      t1, 2
    bltu    t0, t2, .Lsuffix_face
    addi    t0, t0, -3
    li      t1, 4
.Lsuffix_face:
    addi    t0, t0, 1
.Lsuffix_turn:
    slli    t2, s4, 1
    slli    t3, s4, 2
    add     t2, t2, t3
    add     t2, t2, t1
    add     t2, t2, s8
    lhu     s4, 0(t2)
    slli    t2, s5, 1
    slli    t3, s5, 2
    add     t2, t2, t3
    add     t2, t2, t1
    add     t2, t2, s9
    lhu     s5, 0(t2)
    addi    t0, t0, -1
    bnez    t0, .Lsuffix_turn
    mv      a0, s4
    mv      a1, s5
    call    near_lookup
    j       .Lfinish_near
.Lsearch_return:
    mv      a0, s2
    lw      ra, 312(sp)
    lw      s7, 308(sp)
    lw      s6, 304(sp)
    lw      s5, 300(sp)
    lw      s4, 296(sp)
    lw      s3, 292(sp)
    lw      s2, 288(sp)
    lw      s1, 284(sp)
    lw      s0, 280(sp)
    addi    sp, sp, 320
    ret
    .size solve_coordinates, .-solve_coordinates
