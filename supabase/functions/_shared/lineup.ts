// The lineup solver, shared by everything that needs to know what a
// roster is worth.
//
// One implementation on purpose: the chat function, the thread and the
// Sunday jobs must agree about what a lineup projects, or the coach will
// contradict himself in public.

export const BENCH = 20;
export const IR = 21;

export interface Player {
  /** ESPN's player id, which joins to the FantasyPros cache. */
  espnId?: number;
  name: string;
  slot: number;
  points: number;
  status: string;
  eligible: number[];
  /** Percent of leagues rostering them. Free agents only. */
  owned?: number;
}

export /** ESPN's projection for a week. statSourceId 1 is the projection. */
function projection(player: Record<string, any>, week: number): number {
  for (const row of player.stats ?? []) {
    if (row.statSourceId === 1 && row.scoringPeriodId === week) {
      return Number(row.appliedTotal ?? 0);
    }
  }
  return 0;
}

export /**
 * Best legal lineup. The same exact solve the Sunday coach does — greedy gets
 * the FLEX case wrong, and two coaches disagreeing about what a lineup is
 * worth would be worse than having one.
 */
function bestLineup(players: Player[], slots: number[]): { total: number; picks: number[] } {
  const memo = new Map<string, { total: number; picks: number[] }>();

  function solve(slotIndex: number, used: number): { total: number; picks: number[] } {
    if (slotIndex === slots.length) return { total: 0, picks: [] };
    const key = `${slotIndex}:${used}`;
    const cached = memo.get(key);
    if (cached) return cached;

    let best = { total: -Infinity, picks: [] as number[] };
    const slot = slots[slotIndex];
    for (let i = 0; i < players.length; i++) {
      if (used & (1 << i)) continue;
      if (!players[i].eligible.includes(slot)) continue;
      const rest = solve(slotIndex + 1, used | (1 << i));
      const total = players[i].points + rest.total;
      if (total > best.total) best = { total, picks: [i, ...rest.picks] };
    }
    // A slot with nobody eligible is left empty rather than failing.
    const empty = solve(slotIndex + 1, used);
    if (empty.total > best.total) best = { total: empty.total, picks: [-1, ...empty.picks] };

    memo.set(key, best);
    return best;
  }

  return solve(0, 0);
}
