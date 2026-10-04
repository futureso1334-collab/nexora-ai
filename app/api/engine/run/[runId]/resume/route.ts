import { NextResponse } from "next/server";

export async function POST(
  request: Request,
  { params }: { params: Promise<{ runId: string }> }
) {
  try {
    const { runId } = await params;
    const body = await request.json();

    const response = await fetch(
      "http://127.0.0.1:8000/api/v1/agent/runs/" + runId + "/resume",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      }
    );

    const data = await response.json();
    return NextResponse.json(data, { status: response.status });
  } catch (error) {
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "Resume failed" },
      { status: 502 }
    );
  }
}
