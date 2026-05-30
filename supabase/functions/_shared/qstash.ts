import { env } from "./env.ts";

type PublishOptions = {
  path: string;
  body: Record<string, unknown>;
  delaySeconds?: number;
};

export async function publishToWorker(
  options: PublishOptions,
): Promise<{ messageId?: string; raw: unknown }> {
  const destination = new URL(options.path, env.workerBaseUrl).toString();
  const headers: Record<string, string> = {
    Authorization: `Bearer ${env.qstashToken}`,
    "Content-Type": "application/json",
    "Upstash-Forward-Authorization": `Bearer ${env.workerSharedSecret}`,
  };

  if (options.delaySeconds && options.delaySeconds > 0) {
    headers["Upstash-Delay"] = `${Math.ceil(options.delaySeconds)}s`;
  }

  const qstashUrl = env.qstashUrl.replace(/\/$/, "");
  const response = await fetch(
    `${qstashUrl}/v2/publish/${encodeURI(destination)}`,
    {
      method: "POST",
      headers,
      body: JSON.stringify(options.body),
    },
  );

  const text = await response.text();
  let raw: unknown = text;
  try {
    raw = JSON.parse(text);
  } catch (_) {
    // QStash may return plain text for some failures.
  }

  if (!response.ok) {
    throw new Error(`QStash publish failed: ${response.status} ${text}`);
  }

  const messageId =
    typeof raw === "object" && raw !== null && "messageId" in raw
      ? String((raw as { messageId?: unknown }).messageId)
      : undefined;

  return { messageId, raw };
}
