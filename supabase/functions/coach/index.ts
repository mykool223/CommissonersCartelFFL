// Answers a member's question about their own team.
//
// The model is given the real roster, real projections and the optimal lineup
// already computed — not asked to work them out. That is the difference
// between an assistant and a plausible liar: it can reason about numbers it
// has been handed, and it cannot invent a player who is not on the list.
//
// Grounded, capped, and members-only. Every question costs money, so there is
// a daily limit per person and a hard ceiling on how much comes back.

const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY");
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ESPN_S2 = Deno.env.get("ESPN_S2");
const ESPN_SWID = Deno.env.get("ESPN_SWID");
const ESPN_LEAGUE_ID = Deno.env.get("ESPN_LEAGUE_ID");

const DAILY_LIMIT = Number(Deno.env.get("COACH_DAILY_LIMIT") ?? "20");
const MODEL = Deno.env.get("COACH_MODEL") ?? "claude-sonnet-5";

const BENCH = 20;
const IR = 21;

/** ESPN's defaultPositionId, for labelling other teams' players. */
const positionName: Record<number, string> = {
  1: "QB", 2: "RB", 3: "WR", 4: "TE", 5: "K", 16: "DST",
};

const SYSTEM = `You are Coach Landry, who runs football operations for the
Commissioner's Cartel.

You are given a manager's actual roster with this week's projections, the best
legal lineup already solved for them, the free agents worth considering with
what each would add, and every other team in the league with their rosters and
this week's opponent marked. Use those numbers. Do not invent players,
projections or matchups; if something is not in the data, say you do not know
rather than guessing. When asked about pickups, only name players from the free
agent list you are given — anyone else is already on a roster and cannot be
signed.

Voice: the league is run as a cartel and takes itself about half seriously, so
lean into it. The league is the outfit or the organisation. Managers are
operators. The waiver wire is the street or the open market. Trades are deals.
Starting somebody is putting them on the job; benching them is sitting them
down. Calm, understated, faintly menacing — the numbers make the case and you
merely read them out. Never shout, never pad, never threaten anybody for real.

Some players carry a bracket with FantasyPros' expert consensus: their
position rank, tier, projection, whether their rank is rising or falling, and
how likely they are to play. That is dozens of analysts rather than one
projection, so weigh it seriously — but say which source you are using when
they disagree, and never present one as the other. When you pass on anything
from that bracket, credit FantasyPros for it. Say only what the bracket says:
if it does not report a player's rank rising or falling, do not describe them
as rising or falling — early in the season there is no trend to report, and a
plausible-sounding one is just invented.

You can see every roster, so compare teams, judge a matchup, and say where an
opponent is strong or thin. Do not propose or evaluate trades yet — that is
not switched on, and the commissioner wants to talk it through first. If
somebody asks about a trade, say it is coming but not yet, and answer whatever
part of their question is not about trading.

Be direct and brief: three or four sentences unless asked for more. Give a
recommendation rather than a survey of options. Never dress up a close call as
obvious — if two players are within a point, say the numbers do not care which
one you pick.`;

interface Player {
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

async function espn(path: string, query: string): Promise<Record<string, unknown>> {
  const response = await fetch(`https://lm-api-reads.fantasy.espn.com${path}?${query}`, {
    headers: {
      // ESPN's edge rejects browser-like agents and allows known clients.
      "User-Agent": "curl/8.7.1",
      Accept: "application/json",
      Cookie: `espn_s2=${ESPN_S2}; SWID=${ESPN_SWID}`,
    },
  });
  if (!response.ok) throw new Error(`ESPN ${response.status}`);
  return await response.json();
}

/** Free agents worth considering, newest ownership first. */
async function freeAgents(season: number, week: number): Promise<Player[]> {
  const filter = JSON.stringify({
    players: {
      filterStatus: { value: ["FREEAGENT", "WAIVERS"] },
      // Kickers and defences churn weekly; recommending them is noise.
      filterSlotIds: { value: [0, 2, 4, 6] },
      limit: 60,
      sortPercOwned: { sortAsc: false, sortPriority: 1 },
    },
  });

  const response = await fetch(
    `https://lm-api-reads.fantasy.espn.com/apis/v3/games/ffl/seasons/${season}` +
      `/segments/0/leagues/${ESPN_LEAGUE_ID}?view=kona_player_info`,
    {
      headers: {
        "User-Agent": "curl/8.7.1",
        Accept: "application/json",
        Cookie: `espn_s2=${ESPN_S2}; SWID=${ESPN_SWID}`,
        "X-Fantasy-Filter": filter,
      },
    },
  );
  if (!response.ok) return [];

  const body = await response.json();
  return (body.players ?? [])
    .map((entry: any) => {
      const raw = entry.player ?? {};
      return {
        espnId: raw.id,
        name: raw.fullName ?? "A player",
        slot: BENCH,
        points: projection(raw, week),
        status: String(raw.injuryStatus ?? "").toUpperCase(),
        eligible: raw.eligibleSlots ?? [],
        owned: Math.round((raw.ownership?.percentOwned ?? 0) * 10) / 10,
      };
    })
    .filter((p: Player & { owned: number }) => p.points > 0);
}

/** What the experts collectively think of one player. */
interface Consensus {
  posRank?: string;
  tier?: number;
  ecrDelta?: number;
  spread?: number;
  points?: number;
  rosRank?: string;
  status?: string;
  probability?: number;
  injuryType?: string;
}

/**
 * Reads the FantasyPros cache for a set of ESPN players.
 *
 * Nothing here calls FantasyPros. Their licence allows a hundred calls a day
 * in total, so a nightly job fills these tables and this reads them; if the
 * job has never run the map comes back empty and the coach works from ESPN
 * alone, which is how it behaved before.
 */
async function consensusFor(
  espnIds: number[],
  season: number,
  week: number,
): Promise<Map<number, Consensus>> {
  const out = new Map<number, Consensus>();
  const ids = espnIds.filter((id) => Number.isFinite(id));
  if (!ids.length) return out;

  try {
    const players = await rest(
      `fantasypros_players?select=fp_id,espn_id&espn_id=in.(${ids.join(",")})`,
    ) as Array<{ fp_id: number; espn_id: number }>;
    if (!players?.length) return out;

    const byFp = new Map(players.map((p) => [p.fp_id, p.espn_id]));
    const fpIds = players.map((p) => p.fp_id).join(",");
    const scope = `season=eq.${season}&week=eq.${week}&fp_id=in.(${fpIds})`;

    const [ranks, projections, injuries] = await Promise.all([
      rest(`fantasypros_rankings?select=fp_id,kind,pos_rank,tier,rank_std,ecr_delta&${scope}`),
      rest(`fantasypros_projections?select=fp_id,points_ppr&${scope}`),
      rest(`fantasypros_injuries?select=fp_id,status,probability,injury_type&${scope}`),
    ]) as [any[], any[], any[]];

    const entry = (fpId: number): Consensus => {
      const espnId = byFp.get(fpId)!;
      if (!out.has(espnId)) out.set(espnId, {});
      return out.get(espnId)!;
    };

    for (const row of ranks ?? []) {
      const it = entry(row.fp_id);
      if (row.kind === "ros") {
        it.rosRank = row.pos_rank ?? undefined;
      } else {
        it.posRank = row.pos_rank ?? undefined;
        it.tier = row.tier ?? undefined;
        it.ecrDelta = row.ecr_delta ?? undefined;
        it.spread = row.rank_std ?? undefined;
      }
    }
    for (const row of projections ?? []) {
      entry(row.fp_id).points = row.points_ppr ?? undefined;
    }
    for (const row of injuries ?? []) {
      const it = entry(row.fp_id);
      it.status = row.status ?? undefined;
      it.probability = row.probability ?? undefined;
      it.injuryType = row.injury_type ?? undefined;
    }
  } catch {
    // A cache miss is not worth failing a question over.
    return out;
  }
  return out;
}

/** How a player reads in the context line, when the experts have a view. */
function describeConsensus(view: Consensus | undefined): string {
  if (!view) return "";
  const parts: string[] = [];
  if (view.posRank) parts.push(`consensus ${view.posRank}`);
  if (view.tier !== undefined) parts.push(`tier ${view.tier}`);
  if (view.points !== undefined) parts.push(`FP projects ${view.points.toFixed(1)}`);
  // A rank that has moved several places in a week usually means news.
  if (view.ecrDelta !== undefined && Math.abs(view.ecrDelta) >= 3) {
    parts.push(`${view.ecrDelta > 0 ? "falling" : "rising"} ` +
      `${Math.abs(view.ecrDelta).toFixed(0)} places this week`);
  }
  if (view.probability !== undefined) {
    parts.push(`${Math.round(view.probability * 100)}% likely to play`);
  } else if (view.status) {
    parts.push(`listed ${view.status}`);
  }
  return parts.length ? ` [${parts.join(", ")}]` : "";
}

async function rest(path: string, init?: RequestInit): Promise<unknown> {
  const response = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    ...init,
    headers: {
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
      "Content-Type": "application/json",
      Prefer: "return=representation,resolution=merge-duplicates",
      ...(init?.headers ?? {}),
    },
  });
  if (!response.ok) throw new Error(`${path}: ${response.status} ${await response.text()}`);
  const text = await response.text();
  return text ? JSON.parse(text) : null;
}

/** ESPN's projection for a week. statSourceId 1 is the projection. */
function projection(player: Record<string, any>, week: number): number {
  for (const row of player.stats ?? []) {
    if (row.statSourceId === 1 && row.scoringPeriodId === week) {
      return Number(row.appliedTotal ?? 0);
    }
  }
  return 0;
}

/**
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

/**
 * Reads a JWT payload.
 *
 * `atob` alone is not enough: JWT payloads are base64*url*, which uses `-` and
 * `_` and drops the padding, and atob throws on both. A token containing
 * either — which is most of them — would fail before anything else ran.
 */
function decodeClaims(jwt: string): Record<string, unknown> {
    const payload = jwt.split(".")[1];
    if (!payload) return {};
    const base64 = payload.replace(/-/g, "+").replace(/_/g, "/");
    const padded = base64.padEnd(base64.length + ((4 - base64.length % 4) % 4), "=");
    try {
        return JSON.parse(atob(padded));
    } catch {
        return {};
    }
}

Deno.serve(async (request) => {
  try {
    if (!ANTHROPIC_API_KEY) {
      return Response.json(
        { error: "The coach is not configured yet. The commissioner needs to add an API key." },
        { status: 503 },
      );
    }

    // Supabase verifies the JWT before this runs; this reads who it belongs to.
    const authorization = request.headers.get("Authorization") ?? "";
    const jwt = authorization.replace(/^Bearer /, "");
    const claims = decodeClaims(jwt);
    const userId: string | undefined = claims.sub;
    if (!userId) return Response.json({ error: "Sign in first." }, { status: 401 });

    // Signing in is not the same as being a member.
    const profiles = await rest(
      `profiles?select=id,display_name,espn_swid&id=eq.${userId}`,
    ) as Array<{ espn_swid?: string; display_name?: string }>;
    const profile = profiles?.[0];
    if (!profile) {
      return Response.json({ error: "You are not on the league list." }, { status: 403 });
    }
    if (!profile.espn_swid) {
      return Response.json(
        { error: "Pick your team first, under Members, so I know whose roster to look at." },
        { status: 400 },
      );
    }

    const today = new Date().toISOString().slice(0, 10);
    const usage = await rest(
      `coach_usage?select=asked&user_id=eq.${userId}&day=eq.${today}`,
    ) as Array<{ asked: number }>;
    const asked = usage?.[0]?.asked ?? 0;
    if (asked >= DAILY_LIMIT) {
      return Response.json(
        { error: `That is ${DAILY_LIMIT} questions today. Try again tomorrow.` },
        { status: 429 },
      );
    }

    const { question } = await request.json();
    if (typeof question !== "string" || question.trim().length < 2) {
      return Response.json({ error: "Ask something." }, { status: 400 });
    }
    // A long question is a cost multiplier and never a better question.
    const trimmed = question.trim().slice(0, 500);

    const season = new Date().getUTCMonth() >= 5
      ? new Date().getUTCFullYear()
      : new Date().getUTCFullYear() - 1;
    const league = await espn(
      `/apis/v3/games/ffl/seasons/${season}/segments/0/leagues/${ESPN_LEAGUE_ID}`,
      "view=mRoster&view=mTeam&view=mSettings&view=mMatchupScore",
    ) as Record<string, any>;

    const week = league.status?.currentMatchupPeriod ?? 1;
    const swid = profile.espn_swid.trim().toUpperCase();
    const team = (league.teams ?? []).find((t: any) =>
      (t.owners ?? []).some((o: string) => o.trim().toUpperCase() === swid)
    );
    if (!team) {
      return Response.json({ error: "I could not find your team in ESPN." }, { status: 404 });
    }

    const unplayable = ["OUT", "DOUBTFUL", "INJURY_RESERVE", "SUSPENSION", "NOT_ACTIVE"];
    const players: Player[] = (team.roster?.entries ?? []).map((entry: any) => {
      const raw = entry.playerPoolEntry?.player ?? {};
      const status = String(raw.injuryStatus ?? "").toUpperCase();
      return {
        espnId: raw.id,
        name: raw.fullName ?? "A player",
        slot: entry.lineupSlotId,
        // Somebody who cannot play is worth zero whatever ESPN projects.
        points: unplayable.includes(status) ? 0 : projection(raw, week),
        status,
        eligible: raw.eligibleSlots ?? [],
      };
    });

    const counts = league.settings?.rosterSettings?.lineupSlotCounts ?? {};
    const slots: number[] = [];
    for (const [slot, count] of Object.entries(counts)) {
      const id = Number(slot);
      if (id === BENCH || id === IR) continue;
      for (let i = 0; i < Number(count); i++) slots.push(id);
    }

    const optimal = bestLineup(players, slots);
    const starting = players.filter((p) => p.slot !== BENCH && p.slot !== IR);
    const currentTotal = starting.reduce((sum, p) => sum + p.points, 0);

    const slotName: Record<number, string> = {
      0: "QB", 2: "RB", 4: "WR", 6: "TE", 16: "D/ST", 17: "K", 23: "FLEX",
      [BENCH]: "Bench", [IR]: "IR",
    };

    // What a free agent would add to the *best* lineup, which is the only
    // number that matters. A brilliant tight end is worth nothing to a team
    // that already has a better one.
    //
    // Exact value is a solve per candidate, so a cheap upper bound — their
    // projection minus the weakest starter — narrows the field first. Nobody
    // below that can help, and this runs inside an edge function's budget.
    const startersNow = optimal.picks.filter((i) => i >= 0).map((i) => players[i].points);
    const weakest = startersNow.length ? Math.min(...startersNow) : 0;

    const pool = await freeAgents(season, week);
    const shortlist = pool
      .filter((candidate) => candidate.points - weakest > 0)
      .sort((a, b) => b.points - a.points)
      .slice(0, 8);

    const upgrades = shortlist
      .map((candidate) => ({
        candidate,
        gain: bestLineup([...players, candidate], slots).total - optimal.total,
      }))
      .filter((row) => row.gain > 0.05)
      .sort((a, b) => b.gain - a.gain)
      .slice(0, 5);

    // The rest of the league. ESPN returns every roster in the same response
    // the manager's own team came from, so this costs nothing extra — it was
    // simply being thrown away. Rosters are public to the league anyway;
    // anybody can read them in ESPN's app.
    const rivals = (league.teams ?? [])
      .filter((t: any) => t.id !== team.id)
      .map((t: any) => ({
        id: t.id,
        name: (t.name ?? `Team ${t.id}`).trim(),
        squad: (t.roster?.entries ?? []).map((entry: any) => {
          const raw = entry.playerPoolEntry?.player ?? {};
          return {
            espnId: raw.id as number | undefined,
            name: raw.fullName ?? "A player",
            position: positionName[raw.defaultPositionId] ?? "",
            points: projection(raw, week),
            status: String(raw.injuryStatus ?? "").toUpperCase(),
            starting: entry.lineupSlotId !== BENCH && entry.lineupSlotId !== IR,
          };
        }),
      }));

    // Who the manager actually plays this week, so "my matchup" means
    // something without them having to name the opponent.
    const fixture = (league.schedule ?? []).find((game: any) =>
      game.matchupPeriodId === week &&
      (game.home?.teamId === team.id || game.away?.teamId === team.id));
    const opponentId = fixture
      ? (fixture.home?.teamId === team.id ? fixture.away?.teamId : fixture.home?.teamId)
      : undefined;

    // The experts' view of everybody in play, from the nightly cache.
    const view = await consensusFor(
      [...players, ...shortlist].map((p) => p.espnId ?? NaN)
        .concat(rivals.flatMap((r) => r.squad.map((p) => p.espnId ?? NaN))),
      season, week);

    // The genuinely useful signal is disagreement. ESPN's projection is one
    // number from one source; the consensus is dozens of analysts. Where they
    // would start different players, that is worth saying out loud — and it is
    // the sort of thing a manager cannot see from inside ESPN's app.
    const withConsensus = players.map((p) => {
      const points = view.get(p.espnId ?? NaN)?.points;
      return points === undefined ? p : { ...p, points };
    });
    const consensusBest = bestLineup(withConsensus, slots);
    const espnStarters = new Set(
      optimal.picks.filter((i) => i >= 0).map((i) => players[i].name));
    const consensusStarters = new Set(
      consensusBest.picks.filter((i) => i >= 0).map((i) => players[i].name));
    const disagreements = [...consensusStarters].filter((n) => !espnStarters.has(n));

    // An empty cache makes the two lineups identical, which would otherwise
    // read as the experts agreeing. They have not been asked. Claiming
    // corroboration that does not exist is worse than having no data at all,
    // so the coach is told there is none.
    // A general rule against inventing momentum was not enough — told only
    // that a bracket might mention movement, he twice described a rank as
    // "rising" or "sliding" when no movement was reported. Stating the
    // absence as a fact about this week's data is harder to talk past.
    const anyMovement = [...view.values()].some(
      (v) => v.ecrDelta !== undefined && Math.abs(v.ecrDelta) >= 3);

    const covered = players.filter(
      (p) => view.get(p.espnId ?? NaN)?.points !== undefined).length;
    const haveConsensus = covered >= Math.ceil(players.length / 2);

    const context = [
      `Manager: ${profile.display_name ?? "a member"}`,
      `Team: ${team.name?.trim() ?? "their team"}`,
      `Week ${week}.`,
      "",
      "Roster (slot, player, ESPN's projection, injury status), then in",
      "brackets what FantasyPros' expert consensus says about them:",
      ...players.map((p) =>
        `- ${slotName[p.slot] ?? p.slot}: ${p.name}, ${p.points.toFixed(1)}` +
        (p.status && p.status !== "ACTIVE" ? ` (${p.status})` : "") +
        describeConsensus(view.get(p.espnId ?? NaN))
      ),
      "",
      `Current starting lineup projects ${currentTotal.toFixed(1)} points.`,
      `The best legal lineup projects ${optimal.total.toFixed(1)} points.`,
      optimal.total - currentTotal > 0.05
        ? `That is ${(optimal.total - currentTotal).toFixed(1)} points being left on the bench.`
        : "The lineup is already optimal against these projections.",
      "",
      upgrades.length
        ? [
          "Free agents who would improve this lineup, with what each would add:",
          ...upgrades.map((row) =>
            `- ${row.candidate.name}, projected ${row.candidate.points.toFixed(1)}, ` +
            `owned in ${(row.candidate as any).owned}% of leagues, ` +
            `would add ${row.gain.toFixed(1)} points` +
            describeConsensus(view.get(row.candidate.espnId ?? NaN))
          ),
          "Anyone signed has to replace somebody, so say who to drop — the " +
          "lowest-projected bench player is usually the answer.",
        ].join("\n")
        : `${pool.length} free agents were checked and none would improve this ` +
          "lineup. Say so plainly rather than suggesting somebody anyway.",
      "",
      "Every other team in the league, with this week's projections. A star",
      "marks a current starter. Rosters are public — anybody in the league can",
      "read them in ESPN's app.",
      ...rivals.map((rival) => {
        const roster = [...rival.squad]
          .sort((a, b) => b.points - a.points)
          .map((p) => {
            const rank = view.get(p.espnId ?? NaN)?.posRank;
            return `${p.starting ? "*" : ""}${p.name} (${p.position}, ` +
              `${p.points.toFixed(1)}${rank ? `, ${rank}` : ""}` +
              `${p.status && p.status !== "ACTIVE" ? `, ${p.status}` : ""})`;
          })
          .join("; ");
        return `- ${rival.name}` +
          `${rival.id === opponentId ? " — THIS WEEK'S OPPONENT" : ""}: ${roster}`;
      }),
      "",
      anyMovement ? "" :
        "No week-on-week rank movement is reported this week, for anybody. " +
        "Do not describe any player as rising, falling, sliding, trending or " +
        "climbing — there is no such data here, and it would be invented.",
      "",
      !haveConsensus
        ? "No FantasyPros consensus is available for this roster right now, " +
          "so every number above is ESPN's. Work from those and do not " +
          "mention any consensus, agreement or expert ranking — you have not " +
          "been shown one."
        : disagreements.length
        ? "ESPN's projections and the expert consensus disagree about this " +
          `lineup. On the consensus numbers, ${disagreements.join(" and ")} ` +
          "would start instead. Say so and give your own view — a manager " +
          "cannot see this from inside ESPN's app, and it is often the most " +
          "useful thing you can tell them."
        : "ESPN's projections and the expert consensus would start the same " +
          "players, which is worth mentioning as confirmation when the " +
          "question is about the lineup.",
    ].join("\n");

    const response = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "x-api-key": ANTHROPIC_API_KEY,
        "anthropic-version": "2023-06-01",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: MODEL,
        // Thinking is on by default and spends the same budget the answer
        // does. With every roster in the context it swallowed all 400 tokens
        // and left nothing to say. These questions do not need it, and a
        // manager waiting on a phone would rather have the answer.
        thinking: { type: "disabled" },
        // Room for a real answer plus the odd longer one, still short enough
        // that a runaway reply cannot cost much.
        max_tokens: 700,
        system: SYSTEM,
        messages: [{ role: "user", content: `${context}\n\nQuestion: ${trimmed}` }],
      }),
    });

    if (!response.ok) {
      console.error(`Anthropic ${response.status}: ${await response.text()}`);
      return Response.json({ error: "The coach is unavailable right now." }, { status: 502 });
    }

    const body = await response.json();
    const answer = (body.content ?? [])
      .filter((block: any) => block.type === "text")
      .map((block: any) => block.text)
      .join("\n")
      .trim();

    // An empty reply used to reach the app as a blank bubble, which reads as
    // the coach ignoring you. Say something instead, and carry the reason.
    if (!answer) {
      const detail = `stop_reason=${body.stop_reason} ` +
        `blocks=${JSON.stringify((body.content ?? []).map((b: any) => b.type))} ` +
        `usage=${JSON.stringify(body.usage)}`;
      console.error(`Empty answer. ${detail}`);
      return Response.json(
        { error: "The coach had nothing to say. Try asking again.", detail },
        { status: 502 },
      );
    }

    await rest("coach_usage?on_conflict=user_id,day", {
      method: "POST",
      body: JSON.stringify([{ user_id: userId, day: today, asked: asked + 1 }]),
    });

    return Response.json({ answer, remaining: DAILY_LIMIT - asked - 1 });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`coach failed: ${message}`);
    return Response.json({ error: `Something went wrong: ${message}` }, { status: 500 });
  }
});
