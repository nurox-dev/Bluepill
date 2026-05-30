import { requireUser } from "../_shared/auth.ts";
import { writeAuditLog } from "../_shared/audit.ts";
import { errorResponse, handleCors, jsonResponse } from "../_shared/cors.ts";
import { checkRateLimit } from "../_shared/permissions.ts";
import { publishToWorker } from "../_shared/qstash.ts";
import { createServiceClient } from "../_shared/supabase.ts";

type AgentChatRequest = {
  message: string;
  conversation_id?: string;
  attachments?: Array<Record<string, unknown>>;
  idempotency_key?: string;
};

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  if (req.method !== "POST") {
    return errorResponse("Method not allowed.", 405);
  }

  const client = createServiceClient();

  try {
    const user = await requireUser(req);
    const body = (await req.json()) as AgentChatRequest;
    const message = body.message?.trim();
    if (!message) {
      return errorResponse("message is required.", 422);
    }

    const permission = await checkRateLimit(client, {
      userId: user.id,
      endpoint: "agent-chat",
      action: "create_agent_run",
      metadata: { conversation_id: body.conversation_id },
    });

    if (!permission.allowed) {
      await writeAuditLog(client, {
        userId: user.id,
        actorType: "edge_function",
        eventType: "agent_run.blocked",
        metadata: { reason: permission.reason },
      });
      return errorResponse(permission.reason ?? "Rate limit exceeded.", 429);
    }

    let conversationId = body.conversation_id;
    if (!conversationId) {
      const { data, error } = await client
        .from("agent_conversations")
        .insert({
          user_id: user.id,
          title: message.length > 60 ? `${message.slice(0, 57)}...` : message,
        })
        .select("id")
        .single();

      if (error) throw error;
      conversationId = data.id as string;
    } else {
      const { data, error } = await client
        .from("agent_conversations")
        .select("id")
        .eq("id", conversationId)
        .eq("user_id", user.id)
        .single();

      if (error || !data) {
        return errorResponse("Conversation not found.", 404);
      }
    }

    const { data: messageRow, error: messageError } = await client
      .from("agent_messages")
      .insert({
        user_id: user.id,
        conversation_id: conversationId,
        role: "user",
        text: message,
        attachments: body.attachments ?? [],
      })
      .select("id")
      .single();

    if (messageError) throw messageError;

    await client
      .from("agent_conversations")
      .update({ updated_at: new Date().toISOString() })
      .eq("id", conversationId)
      .eq("user_id", user.id);

    const { data: run, error: runError } = await client
      .from("agent_runs")
      .insert({
        user_id: user.id,
        conversation_id: conversationId,
        message_id: messageRow.id,
        run_type: "chat",
        status: "queued",
        queue_provider: "qstash",
        idempotency_key: body.idempotency_key,
        input: {
          message,
          attachments: body.attachments ?? [],
        },
      })
      .select("id")
      .single();

    if (runError) throw runError;

    await writeAuditLog(client, {
      userId: user.id,
      actorType: "edge_function",
      eventType: "agent_run.created",
      targetTable: "agent_runs",
      targetId: run.id as string,
      agentRunId: run.id as string,
      metadata: { conversation_id: conversationId },
    });

    const published = await publishToWorker({
      path: "/jobs/agent-run",
      body: {
        user_id: user.id,
        agent_run_id: run.id,
      },
    });

    await client
      .from("agent_runs")
      .update({
        qstash_message_id: published.messageId,
        updated_at: new Date().toISOString(),
      })
      .eq("id", run.id);

    return jsonResponse({
      conversation_id: conversationId,
      message_id: messageRow.id,
      agent_run_id: run.id,
      status: "queued",
    });
  } catch (error) {
    return errorResponse(error instanceof Error ? error.message : String(error), 500);
  }
});
