import { NextResponse } from "next/server";
import OpenAI from "openai";

export const runtime = "nodejs";

export async function POST(request: Request) {
  try {
    const body = await request.json();
    const prompt = String(body?.prompt ?? "").trim();

    if (!prompt) {
      return NextResponse.json(
        { error: "Prompt is required" },
        { status: 400 }
      );
    }

    const apiKey = process.env.FREELLMAPI_API_KEY;
    const baseURL = process.env.FREELLMAPI_BASE_URL;

    if (!apiKey || !baseURL) {
      return NextResponse.json(
        { error: "FreeLLMAPI is not configured on Vercel" },
        { status: 500 }
      );
    }

    const client = new OpenAI({
      apiKey,
      baseURL,
    });

    const completion = await client.chat.completions.create({
      model: "qwen3-coder-480b",
      messages: [
        {
          role: "system",
          content:
            "You are NEXORA AI. Help the user create software. Return clear, useful answers.",
        },
        {
          role: "user",
          content: prompt,
        },
      ],
      max_tokens: 1024,
    });

    const text = completion.choices[0]?.message?.content ?? "";

    return NextResponse.json({
      success: true,
      response: text,
    });
  } catch (error) {
    return NextResponse.json(
      {
        error:
          error instanceof Error
            ? error.message
            : "NEXORA AI request failed",
      },
      { status: 500 }
    );
  }
}
