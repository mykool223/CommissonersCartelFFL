// Landry answering the league thread.
//
// Fired by a trigger when somebody mentions him. He reads the last few
// messages for context, replies once, and posts under his own account.
//
// Public rather than private on purpose: a coach who settles an argument
// about whether a trade was fair should do it where the argument is.
import { SYSTEM, speak } from "../_shared/landry.ts";
import { BENCH, IR, bestLineup, projection, type Player } from "../_shared/lineup.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
const MODEL = Deno.env.get("COACH_MODEL") ?? "claude-sonnet-5";
const SECRET = Deno.env.get("PUSH_SECRET");

const ESPN_S2 = Deno.env.get("ESPN_S2");
const ESPN_SWID = Deno.env.get("ESPN_SWID");
const ESPN_LEAGUE_ID = Deno.env.get("ESPN_LEAGUE_ID");

/** How much of the conversation he is shown. Enough to follow it, not a novel. */
const HISTORY = 12;

async function rest(path: string, init?: RequestInit): Promise<unknown> {
  const response = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    ...init,
    headers: {
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
      "Content-Type": "application/json",
      Prefer: "return=representation",
      ...(init?.headers ?? {}),
    },
  });
  if (!response.ok) throw new Error(`${path}: ${response.status} ${await response.text()}`);
  const text = await response.text();
  return text ? JSON.parse(text) : null;
}

/**
 * Every team's projected week, solved.
 *
 * He was answering "who scores most this week" with "I do not have the
 * numbers here", which was true and needn't have been — the rosters and
 * projections are one request away, and the same solver the chat uses turns
 * them into a total. Empty on any failure: a thread reply is not worth
 * failing over, and he says he does not know rather than guessing.
 */
async function leagueProjections(
  consensus: Map<number, { posRank?: string; rank?: number }>,
): Promise<string> {
  if (!ESPN_LEAGUE_ID || !ESPN_S2 || !ESPN_SWID) return "";
  try {
    const season = new Date().getUTCMonth() >= 5
      ? new Date().getUTCFullYear()
      : new Date().getUTCFullYear() - 1;
    const response = await fetch(
      `https://lm-api-reads.fantasy.espn.com/apis/v3/games/ffl/seasons/${season}` +
        `/segments/0/leagues/${ESPN_LEAGUE_ID}` +
        "?view=mRoster&view=mTeam&view=mSettings",
      {
        headers: {
          // Their edge rejects browser-like agents and allows known clients.
          "User-Agent": "curl/8.7.1",
          Accept: "application/json",
          Cookie: `espn_s2=${ESPN_S2}; SWID=${ESPN_SWID}`,
        },
      },
    );
    if (!response.ok) return "";
    const league = await response.json();
    const week = league.status?.currentMatchupPeriod ?? 1;

    const counts = league.settings?.rosterSettings?.lineupSlotCounts ?? {};
    const slots: number[] = [];
    for (const [slot, count] of Object.entries(counts)) {
      const id = Number(slot);
      if (id === BENCH || id === IR) continue;
      for (let i = 0; i < Number(count); i++) slots.push(id);
    }

    // Who owns whom, by ESPN player id, so a positional table can say which
    // manager a player belongs to.
    const owners = new Map<number, string>();
    for (const team of league.teams ?? []) {
      const name = (team.name ?? `Team ${team.id}`).trim();
      for (const entry of team.roster?.entries ?? []) {
        const id = entry.playerPoolEntry?.player?.id;
        if (id != null) owners.set(id, name);
      }
    }

    const rows = (league.teams ?? []).map((team: any) => {
      const players: Player[] = (team.roster?.entries ?? []).map((entry: any) => {
        const raw = entry.playerPoolEntry?.player ?? {};
        return {
          espnId: raw.id,
          name: raw.fullName ?? "A player",
          slot: entry.lineupSlotId,
          points: projection(raw, week),
          status: String(raw.injuryStatus ?? "").toUpperCase(),
          eligible: raw.eligibleSlots ?? [],
        };
      });
      const best = bestLineup(players, slots);
      const top = best.picks.filter((i) => i >= 0)
        .map((i) => players[i])
        .sort((a, b) => b.points - a.points)
        .slice(0, 3)
        .map((p) => `${p.name} ${p.points.toFixed(1)}`)
        .join(", ");
      return {
        name: (team.name ?? `Team ${team.id}`).trim(),
        total: best.total,
        top,
      };
    }).sort((a: any, b: any) => b.total - a.total);

    if (!rows.length) return "";

    // A positional table, so "who is the best quarterback in this league" has
    // an answer rather than an improvisation. Asked that before this existed
    // he named a quarterback and attributed him to a running back's manager,
    // which is what happens when the question has no data behind it.
    const positions: Record<number, string> = {
      1: "QB", 2: "RB", 3: "WR", 4: "TE", 5: "K", 16: "DST",
    };
    const byPosition = new Map<string, Array<{ line: string; rank: number }>>();
    for (const team of league.teams ?? []) {
      for (const entry of team.roster?.entries ?? []) {
        const raw = entry.playerPoolEntry?.player ?? {};
        const position = positions[raw.defaultPositionId];
        if (!position || raw.id == null) continue;
        const seen = consensus.get(raw.id);
        // Ordered by the experts where we have them, by projection where we
        // do not — and the source is stated either way.
        const rank = seen?.rank ?? 900 + (200 - projection(raw, week));
        const detail = [
          seen?.posRank ? `${seen.posRank} on the consensus` : null,
          `${projection(raw, week).toFixed(1)} projected`,
        ].filter(Boolean).join(", ");
        const list = byPosition.get(position) ?? [];
        list.push({
          rank,
          line: `${raw.fullName} (${owners.get(raw.id) ?? "unowned"}) — ${detail}`,
        });
        byPosition.set(position, list);
      }
    }

    const positional = [...byPosition.entries()].map(([position, list]) => {
      const top = list.sort((a, b) => a.rank - b.rank).slice(0, 5);
      return `${position}, best first:\n` +
        top.map((p, i) => `  ${i + 1}. ${p.line}`).join("\n");
    }).join("\n");

    return [
      `Week ${week} projections, ESPN's own numbers, for the best legal lineup`,
      "each team could field. Highest first:",
      ...rows.map((r: any, i: number) =>
        `${i + 1}. ${r.name}: ${r.total.toFixed(1)} (${r.top})`),
      "",
      "Every rostered player by position, ranked on the FantasyPros expert",
      "consensus where there is one and on projection where there is not.",
      "The manager who owns them is in brackets:",
      positional,
    ].join("\n");
  } catch (error) {
    console.error(`projections unavailable: ${error}`);
    return "";
  }
}

Deno.serve(async (request) => {
  try {
    if (!SECRET || request.headers.get("x-cartel-secret") !== SECRET) {
      return new Response("Not authorised", { status: 401 });
    }
    if (!ANTHROPIC_API_KEY) return new Response("No API key", { status: 503 });

    const { message_id } = await request.json();
    if (!message_id) return new Response("message_id required", { status: 400 });

    // One reply per message. The trigger fires on insert, but a retry or a
    // replayed request should not produce a second answer.
    const already = await rest(
      `landry_replies?select=message_id&message_id=eq.${message_id}`,
    ) as unknown[];
    if (already?.length) return Response.json({ skipped: "already replied" });

    const asked = (await rest(
      `league_messages?select=id,body,author_name,created_at&id=eq.${message_id}`,
    ) as Array<{ body: string; author_name: string; created_at: string }>)?.[0];
    if (!asked) return new Response("no such message", { status: 404 });

    // The conversation up to that message, oldest first, so a follow-up like
    // "what about him?" means something.
    const recent = (await rest(
      `league_messages?select=body,author_name,created_at` +
      `&created_at=lte.${encodeURIComponent(asked.created_at)}` +
      `&order=created_at.desc&limit=${HISTORY}`,
    ) as Array<{ body: string; author_name: string }>).reverse();

    const landryId = (await rest(
      "profiles?select=id&display_name=eq.Landry",
    ) as Array<{ id: string }>)?.[0]?.id;
    if (!landryId) return new Response("Landry has no profile", { status: 500 });

    // The league's power ranking, so an argument about who is any good has a
    // number behind it rather than a guess.
    const season = new Date().getUTCMonth() >= 5
      ? new Date().getUTCFullYear()
      : new Date().getUTCFullYear() - 1;
    const standing = await rest(
      `power_rankings?select=team_name,rank,score&season=eq.${season}` +
      "&source=eq.fantasypros&order=week.desc,rank.asc&limit=12",
    ) as Array<{ team_name: string; rank: number; score: number }>;

    // The expert consensus for this week, from the nightly cache. Positional
    // rank is what "who is the best quarterback" actually means.
    const consensus = new Map<number, { posRank?: string; rank?: number }>();
    try {
      const ranked = await rest(
        "fantasypros_rankings?select=pos_rank,rank_ecr,fantasypros_players!inner(espn_id)" +
        `&season=eq.${season}&kind=eq.weekly&limit=2000`,
      ) as Array<{ pos_rank?: string; rank_ecr?: number;
                   fantasypros_players: { espn_id: number } }>;
      for (const row of ranked ?? []) {
        const espnId = row.fantasypros_players?.espn_id;
        if (espnId == null) continue;
        // "RB7" → 7, which is what orders a position.
        const digits = (row.pos_rank ?? "").replace(/\D/g, "");
        consensus.set(espnId, {
          posRank: row.pos_rank ?? undefined,
          rank: digits ? Number(digits) : undefined,
        });
      }
    } catch (error) {
      console.error(`consensus unavailable: ${error}`);
    }

    const projections = await leagueProjections(consensus);

    const brief = [
      "You are in the league's group thread. The most recent messages, oldest",
      "first:",
      ...recent.map((m) => `${m.author_name}: ${m.body}`),
      "",
      standing?.length
        ? "The league power ranking, which grades whole rosters:\n" +
          standing.map((r) => `${r.rank}. ${r.team_name}: ${r.score}`).join("\n")
        : "",
      "",
      projections,
    ].join("\n");

    const text = await speak(
      ANTHROPIC_API_KEY, MODEL,
      `${brief}\n\n` +
      `${asked.author_name} has just addressed you. Reply to the thread in ` +
      "one short paragraph — three sentences at most. You are talking to the " +
      "whole league, not one manager, so no greeting and no sign-off. Use the " +
      "numbers above when they answer the question. You have this week's " +
      "projections for every team and every rostered player ranked by " +
      "position on the expert consensus, with their manager in brackets — so " +
      "\"who is the best quarterback in the league\" is answerable, and the " +
      "answer is the top of the QB list, not somebody you remember. Attribute " +
      "a player to the manager the table gives, never another one. What you " +
      "do not have here is the free agent pool, so send waiver questions to " +
      "Matchups. Stay in character — you run football operations for a " +
      "cartel and you talk like it. Never invent a number.",
      300,
    );
    if (!text) return Response.json({ error: "nothing came back" }, { status: 502 });

    await rest("league_messages", {
      method: "POST",
      body: JSON.stringify([{
        author_id: landryId,
        author_name: "Coach Landry",
        body: text.slice(0, 2000),
      }]),
    });
    await rest("landry_replies", {
      method: "POST",
      body: JSON.stringify([{ message_id }]),
    });

    return Response.json({ replied: true });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`landry-reply failed: ${message}`);
    return Response.json({ error: message }, { status: 500 });
  }
});
