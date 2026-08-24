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

const SYSTEM = `You are Coach Madden, the Commissioner's Cartel fantasy football coach.

You are given a manager's actual roster with this week's projections, and the
best legal lineup already solved for them. Use those numbers. Do not invent
players, projections or matchups; if something is not in the data, say you do
not know rather than guessing.

Be direct and brief — three or four sentences unless asked for more. Give a
recommendation rather than a survey of options. Dry humour is welcome; the
league is themed as a cartel and takes itself about half seriously. You are a
gruff old-school coach in a cap and shades; play it lightly, and never at the
expense of being useful. Never
pretend a close call is obvious: if two players are within a point, say so.`;

interface Player {
  name: string;
  slot: number;
  points: number;
  status: string;
  eligible: number[];
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

    const context = [
      `Manager: ${profile.display_name ?? "a member"}`,
      `Team: ${team.name?.trim() ?? "their team"}`,
      `Week ${week}.`,
      "",
      "Roster (slot, player, projected points this week, injury status):",
      ...players.map((p) =>
        `- ${slotName[p.slot] ?? p.slot}: ${p.name}, ${p.points.toFixed(1)}` +
        (p.status && p.status !== "ACTIVE" ? ` (${p.status})` : "")
      ),
      "",
      `Current starting lineup projects ${currentTotal.toFixed(1)} points.`,
      `The best legal lineup projects ${optimal.total.toFixed(1)} points.`,
      optimal.total - currentTotal > 0.05
        ? `That is ${(optimal.total - currentTotal).toFixed(1)} points being left on the bench.`
        : "The lineup is already optimal against these projections.",
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
        max_tokens: 400,
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
