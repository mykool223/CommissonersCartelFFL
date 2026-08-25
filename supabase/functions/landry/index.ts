// Landry's voice, for the league's own jobs.
//
// The Sunday lineup guard, the weekly recap and the league thread all want
// something said in his register. They already hold the facts — a solved
// lineup, a week's scores, a question from the thread — so this takes a brief
// and an instruction and hands back one short piece of writing.
//
// Deliberately not part of the chat function: that one verifies a member's
// token and spends their daily quota, neither of which a cron job has. Same
// persona either way, because both import it from one file.
import { SYSTEM, speak } from "../_shared/landry.ts";

const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
const MODEL = Deno.env.get("COACH_MODEL") ?? "claude-sonnet-5";

// The same secret the push function uses. These are league jobs, not clients:
// nothing holding only the anon key can reach this.
const SECRET = Deno.env.get("PUSH_SECRET");

Deno.serve(async (request) => {
  try {
    if (!ANTHROPIC_API_KEY) {
      return Response.json({ error: "No API key configured." }, { status: 503 });
    }
    if (!SECRET || request.headers.get("x-cartel-secret") !== SECRET) {
      return new Response("Not authorised", { status: 401 });
    }

    const { brief, instruction, max_tokens } = await request.json();
    if (!brief || !instruction) {
      return Response.json(
        { error: "brief and instruction are both required." }, { status: 400 });
    }

    // Short by default: these become a push notification or a thread message,
    // and a model given room will use it.
    const text = await speak(
      ANTHROPIC_API_KEY, MODEL, `${brief}\n\n${instruction}`,
      Math.min(Number(max_tokens) || 260, 700),
    );

    return text
      ? Response.json({ text })
      : Response.json({ error: "Nothing came back." }, { status: 502 });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`landry failed: ${message}`);
    return Response.json({ error: message }, { status: 500 });
  }
});
