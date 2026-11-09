/*
 * rubik_solve_asm: RV32I implementation of the original 2x2x2 solver.
 *
 * This is a port of the supplied solver.S search core, adapted to the
 * assignment API.  It uses the original coordinate tables in solver_tables.S.
 * No M, C, or floating-point instructions are required.
 *
 * a0 = state (14 ASCII characters plus NUL)
 * a1 = output buffer
 * a2 = output capacity
 * return: shortest move count, -1 invalid/unreachable, -2 output too small
 */

    .option norvc
    .equ MAX_DEPTH, 11
    .equ MOVES, 9

    .equ FRAME_P,        0
    .equ FRAME_O,        2
    .equ FRAME_NEXT,     4
    .equ FRAME_PREV,     5
    .equ FRAME_INCOMING, 6
    .equ FRAME_SIZE,     8

    .equ SAVE_S0,        108
    .equ SAVE_S1,        112
    .equ SAVE_S2,        116
    .equ SAVE_S3,        120
    .equ SAVE_RA,        124
    .equ STACK_SIZE,     128

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

    /* Cache the original table bases used by the legacy search routines. */
    la      s8, perm_next
    la      s9, ori_next
    la      s10, perm_dist
    la      s11, ori_dist

    /* Convert the validated input to (permutation, orientation) ranks. */
    mv      a0, s0
    call    rank_input

    /* Run the original iterative IDA* search.  Path lives in this frame. */
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
    .globl coordinate_heuristic
    .type coordinate_heuristic, @function

coordinate_heuristic:

    add     t0, s10, a0
    lbu     t1, 0(t0)

    add     t0, s11, a1
    lbu     t2, 0(t0)


    /* max(t1, t2) */

    bgeu    t1, t2, .Lheuristic_perm

    mv      a0, t2
    ret


.Lheuristic_perm:

    mv      a0, t1
    ret

    .size coordinate_heuristic, . - coordinate_heuristic
    .globl ida_search_iterative
    .type ida_search_iterative, @function

ida_search_iterative:

    addi    sp, sp, -STACK_SIZE

    sw      s0, SAVE_S0(sp)
    sw      s1, SAVE_S1(sp)
    sw      s2, SAVE_S2(sp)
    sw      s3, SAVE_S3(sp)
    sw      ra, SAVE_RA(sp)

    mv      s0, sp             /* frames base */
    mv      s1, a3             /* solution path */
    mv      s2, a2             /* bound */
    li      s3, 0              /* depth */


    /* frames[0] = {p, o, 0, 3, 0} */

    sh      a0, FRAME_P(s0)
    sh      a1, FRAME_O(s0)
    sb      zero, FRAME_NEXT(s0)

    li      t0, 3
    sb      t0, FRAME_PREV(s0)

    sb      zero, FRAME_INCOMING(s0)


    /* solved root */

    or      t0, a0, a1
    beqz    t0, .Lida_success_root

    /* no moves allowed */

    beqz    s2, .Lida_fail


.Lida_loop:

    /*
     * frame = &frames[depth]
     *
     * FRAME_SIZE = 8
     */

    slli    t0, s3, 3
    add     t0, s0, t0


    /* move = frame->next_move */

    lbu     t1, FRAME_NEXT(t0)

    li      t2, MOVES
    beq     t1, t2, .Lida_exhausted


    /*
     * face = move / 3
     *
     * move 0..2 -> face 0
     * move 3..5 -> face 1
     * move 6..8 -> face 2
     *
     * Avoid DIV.
     */

    li      t2, 3
    bltu    t1, t2, .Lida_face0

    li      t2, 6
    bltu    t1, t2, .Lida_face1

    li      t2, 2
    j       .Lida_face_ready


.Lida_face0:
    li      t2, 0
    j       .Lida_face_ready


.Lida_face1:
    li      t2, 1


.Lida_face_ready:

    /*
     * same-face pruning
     */

    lbu     t3, FRAME_PREV(t0)
    beq     t2, t3, .Lida_same_face


    /*
     * Parent resumes from next move when child finishes.
     */

    addi    t3, t1, 1
    sb      t3, FRAME_NEXT(t0)


    /* current p / o */

    lhu     t3, FRAME_P(t0)    /* p */
    lhu     t4, FRAME_O(t0)    /* o */


    /* ------------------------------------------------------------
     * next_p = perm_next[p][move]
     *
     * byte offset = p * 18 + move * 2
     * ------------------------------------------------------------ */

    slli    t5, t3, 4          /* p * 16 */
    slli    t6, t3, 1          /* p * 2 */
    add     t5, t5, t6         /* p * 18 */

    slli    t6, t1, 1
    add     t5, t5, t6

    add     t5, t5, s8

    lhu     t3, 0(t5)          /* next_p */


    /* ------------------------------------------------------------
     * next_o = ori_next[o][move]
     * ------------------------------------------------------------ */

    slli    t5, t4, 4
    slli    t6, t4, 1
    add     t5, t5, t6         /* o * 18 */

    slli    t6, t1, 1
    add     t5, t5, t6

    add     t5, t5, s9

    lhu     t4, 0(t5)          /* next_o */


    /*
     * child_remaining = bound - depth - 1
     */

    sub     t5, s2, s3
    addi    t5, t5, -1


    /* ------------------------------------------------------------
     * heuristic pruning
     *
     * Instead of explicitly calculating max(),
     * prune if either component is > child_remaining.
     * ------------------------------------------------------------ */

    add     t6, s10, t3
    lbu     a4, 0(t6)

    bltu    t5, a4, .Lida_loop


    add     t6, s11, t4
    lbu     a5, 0(t6)

    bltu    t5, a5, .Lida_loop


    /*
     * solved?
     */

    or      t6, t3, t4
    beqz    t6, .Lida_found


    /*
     * Cannot go deeper.
     */

    beqz    t5, .Lida_loop


    /* ------------------------------------------------------------
     * Push child frame.
     * ------------------------------------------------------------ */

    addi    s3, s3, 1

    slli    t0, s3, 3
    add     t0, s0, t0

    sh      t3, FRAME_P(t0)
    sh      t4, FRAME_O(t0)

    sb      zero, FRAME_NEXT(t0)
    sb      t2, FRAME_PREV(t0)
    sb      t1, FRAME_INCOMING(t0)

    j       .Lida_loop


.Lida_same_face:

    /*
     * Skip all three moves belonging to this face.
     */

    addi    t1, t1, 3
    sb      t1, FRAME_NEXT(t0)

    j       .Lida_loop


.Lida_exhausted:

    /*
     * All moves at this depth have been tried.
     */

    beqz    s3, .Lida_fail

    addi    s3, s3, -1
    j       .Lida_loop


.Lida_found:

    /*
     * frames[1..depth] contain the moves used to descend.
     *
     * Copy them into path[0..depth-1].
     */

    li      t0, 0


.Lida_copy_path:

    bgeu    t0, s3, .Lida_copy_last

    addi    t2, t0, 1
    slli    t2, t2, 3
    add     t2, s0, t2

    lbu     t3, FRAME_INCOMING(t2)

    add     t4, s1, t0
    sb      t3, 0(t4)

    addi    t0, t0, 1
    j       .Lida_copy_path


.Lida_copy_last:

    /*
     * Current move solves the cube.
     */

    add     t4, s1, s3
    sb      t1, 0(t4)

    li      a0, 1
    j       .Lida_return


.Lida_success_root:

    li      a0, 1
    j       .Lida_return


.Lida_fail:

    li      a0, 0


.Lida_return:

    lw      ra, SAVE_RA(sp)
    lw      s3, SAVE_S3(sp)
    lw      s2, SAVE_S2(sp)
    lw      s1, SAVE_S1(sp)
    lw      s0, SAVE_S0(sp)

    addi    sp, sp, STACK_SIZE

    ret

    .size ida_search_iterative, . - ida_search_iterative
    .globl solve_coordinates
    .type solve_coordinates, @function

solve_coordinates:

    addi    sp, sp, -32

    sw      s0, 12(sp)
    sw      s1, 16(sp)
    sw      s2, 20(sp)
    sw      s3, 24(sp)
    sw      ra, 28(sp)

    mv      s0, a0             /* start p */
    mv      s1, a1             /* start o */
    mv      s2, a2             /* path buffer */


    /* Initial bound = heuristic(p, o) */

    mv      a0, s0
    mv      a1, s1
    call    coordinate_heuristic

    mv      s3, a0             /* current bound */


.Lsolve_bound_loop:

    li      t0, MAX_DEPTH

    /* if bound > MAX_DEPTH -> fail */
    bltu    t0, s3, .Lsolve_fail


    /* ida_search_iterative(p, o, bound, path) */

    mv      a0, s0
    mv      a1, s1
    mv      a2, s3
    mv      a3, s2

    call    ida_search_iterative

    bnez    a0, .Lsolve_found

    addi    s3, s3, 1
    j       .Lsolve_bound_loop


.Lsolve_found:

    /* First successful bound is the optimal solution length. */

    mv      a0, s3
    j       .Lsolve_return


.Lsolve_fail:

    li      a0, -1


.Lsolve_return:

    lw      ra, 28(sp)
    lw      s3, 24(sp)
    lw      s2, 20(sp)
    lw      s1, 16(sp)
    lw      s0, 12(sp)

    addi    sp, sp, 32

    ret
    .size solve_coordinates, . - solve_coordinates
