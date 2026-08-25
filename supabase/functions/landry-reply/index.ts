// Landry answering the league thread.
//
// Fired by a trigger when somebody mentions him. He reads the last few
// messages for context, replies once, and posts under his own account.
//
// Public rather than private on purpose: a coach who settles an argument
// about whether a trade was fair should do it where the argument is.
import { SYSTEM, speak } from "../_shared/landry.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
const MODEL = Deno.env.get("COACH_MODEL") ?? "claude-sonnet-5";
const SECRET = Deno.env.get("PUSH_SECRET");

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

    const brief = [
      "You are in the league's group thread. The most recent messages, oldest",
      "first:",
      ...recent.map((m) => `${m.author_name}: ${m.body}`),
      "",
      standing?.length
        ? "The league power ranking, if it is relevant:\n" +
          standing.map((r) => `${r.rank}. ${r.team_name}: ${r.score}`).join("\n")
        : "",
    ].join("\n");

    const text = await speak(
      ANTHROPIC_API_KEY, MODEL,
      `${brief}\n\n` +
      `${asked.author_name} has just addressed you. Reply to the thread in ` +
      "one short paragraph — three sentences at most. You are talking to the " +
      "whole league, not one manager, so no greeting and no sign-off. You do " +
      "not have anybody's roster in front of you here: if the answer needs " +
      "one, say so and tell them to ask you under Matchups, where you do. " +
      "Never invent a number.",
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
