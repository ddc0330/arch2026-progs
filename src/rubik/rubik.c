
#include "rubik.h"

enum {
    CUBIES = 7,
    PERMUTATIONS = 5040,
    ORIENTATIONS = 729,
    MOVES = 9,
    MAX_DEPTH = 11
};

typedef struct {
    uint8_t p[CUBIES];
    uint8_t o[CUBIES];
} state_t;

typedef struct {
    uint16_t p;
    uint16_t o;
} coordinates_t;

/* Precomputed coordinate transition and distance tables. */
#include "solver_tables.inc"

static const char *const move_names[MOVES] = {"R",  "R2", "R'", "B", "B2",
                                              "B'", "D",  "D2", "D'"};

/* Validate and parse the 14-character cube state. */
static int parse_state(const char *input, state_t *state)
{
    if (input == NULL)
        return 0;

    uint8_t used = 0;
    uint8_t sum = 0;

    for (uint8_t i = 0; i < CUBIES; ++i) {
        unsigned char ch = (unsigned char) input[i];

        if (ch < '1' || ch > '7')
            return 0;

        uint8_t value = (uint8_t) (ch - '1');
        uint8_t bit = (uint8_t) (1U << value);

        if (used & bit)
            return 0;

        used |= bit;
        state->p[i] = value;
    }

    for (uint8_t i = 0; i < CUBIES; ++i) {
        unsigned char ch = (unsigned char) input[i + CUBIES];

        if (ch < '1' || ch > '3')
            return 0;

        state->o[i] = (uint8_t) (ch - '1');
        sum = (uint8_t) (sum + state->o[i]);
    }

    if (input[RUBIK_STATE_LEN] != '\0')
        return 0;

    return sum == 0 || sum == 3 || sum == 6 || sum == 9 || sum == 12;
}

/* Convert the cube into permutation and orientation coordinates. */
static coordinates_t rank_coordinates(const state_t *state)
{
    uint32_t p = 0;
    uint32_t o = 0;

    for (uint8_t i = 0; i < CUBIES; ++i) {
        uint8_t smaller = 0;

        for (uint8_t j = (uint8_t) (i + 1U); j < CUBIES; ++j) {
            if (state->p[j] < state->p[i])
                ++smaller;
        }

        p = p * (CUBIES - i) + smaller;
    }

    /* The seventh orientation is determined by the modulo-3 constraint. */
    for (uint8_t i = 0; i < 6; ++i)
        o = o * 3U + state->o[i];

    return (coordinates_t) {(uint16_t) p, (uint16_t) o};
}

/* Admissible heuristic: maximum of two abstract distances. */
static uint8_t coordinate_heuristic(uint16_t p, uint16_t o)
{
    uint8_t pd = perm_dist[p];
    uint8_t od = ori_dist[o];

    return pd > od ? pd : od;
}

/*
 * IDA* depth-limited search.
 *
 * previous_face prevents consecutive moves on the same face.
 * path stores the solution moves when a solution is found.
 */
static int ida_search(uint16_t p,
                      uint16_t o,
                      uint8_t remaining,
                      uint8_t previous_face,
                      uint8_t depth,
                      uint8_t *path)
{
    if (p == 0 && o == 0)
        return 1;

    if (remaining == 0)
        return 0;

    uint8_t child_remaining = (uint8_t) (remaining - 1U);

    for (uint8_t face = 0; face < 3; ++face) {
        if (face == previous_face)
            continue;

        uint8_t first_move = (uint8_t) (face * 3U);

        for (uint8_t turn = 0; turn < 3; ++turn) {
            uint8_t move = (uint8_t) (first_move + turn);

            uint16_t next_p = perm_next[move][p];
            uint16_t next_o = ori_next[move][o];

            if (coordinate_heuristic(next_p, next_o) > child_remaining)
                continue;

            if (ida_search(next_p, next_o, child_remaining, face,
                           (uint8_t) (depth + 1U), path)) {
                path[depth] = move;
                return 1;
            }
        }
    }

    return 0;
}

/* Iteratively increase the search bound until the optimal solution is found. */
static int solve_coordinates(uint16_t p, uint16_t o, uint8_t *path)
{
    uint8_t bound = coordinate_heuristic(p, o);

    while (bound <= MAX_DEPTH) {
        if (ida_search(p, o, bound, 3, 0, path))
            return bound;

        ++bound;
    }

    return -1;
}

/*
 * Public API.
 *
 * Returns:
 *   >= 0 : shortest solution length
 *   -1   : invalid input
 *   -2   : output buffer too small
 */
int rubik_solve(const char *state, char *out, size_t cap)
{
    state_t cube;
    uint8_t path[MAX_DEPTH];

    /* Invalid input must not modify the output buffer. */
    if (!parse_state(state, &cube))
        return -1;

    coordinates_t coordinates = rank_coordinates(&cube);

    int length = solve_coordinates(coordinates.p, coordinates.o, path);

    if (length < 0)
        return -1;

    /* Calculate the required output size, including the NUL byte. */
    size_t needed = 1;

    for (int i = 0; i < length; ++i) {
        const char *name = move_names[path[i]];
        size_t name_length = 0;

        while (name[name_length] != '\0')
            ++name_length;

        needed += name_length;

        if (i != 0)
            ++needed;
    }

    if (out == NULL || cap < needed) {
        if (out != NULL && cap >= 1)
            out[0] = '\0';

        return -2;
    }

    /* Write the space-separated solution. */
    size_t pos = 0;

    for (int i = 0; i < length; ++i) {
        if (i != 0)
            out[pos++] = ' ';

        const char *name = move_names[path[i]];

        while (*name != '\0')
            out[pos++] = *name++;
    }

    out[pos] = '\0';

    return length;
}
