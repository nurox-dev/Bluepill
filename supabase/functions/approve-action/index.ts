import { requireUser } from "../_shared/auth.ts";
import { writeAuditLog } from "../_shared/audit.ts";
import { errorResponse, handleCors, jsonResponse } from "../_shared/cors.ts";
import { publishToWorker } from "../_shared/qstash.ts";
import { createServiceClient } from "../_shared/supabase.ts";

type ApprovalRequest = {
  approval_id: string;
  decision: "approved" | "rejected";
  decision_payload?: Record<string, unknown>;
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
    const body = (await req.json()) as ApprovalRequest;

    if (!body.approval_id || !["approved", "rejected"].includes(body.decision)) {
      return errorResponse("approval_id and decision are required.", 422);
    }

    const { data: approval, error: approvalError } = await client
      .from("agent_action_approvals")
      .select("id, agent_run_id, scheduled_job_id, tool_name, action, status")
      .eq("id", body.approval_id)
      .eq("user_id", user.id)
      .maybeSingle();

    if (approvalError) throw approvalError;
    if (!approval) return errorResponse("Approval not found.", 404);
    if (approval.status !== "pending") {
      return errorResponse("Approval is no longer pending.", 409);
    }

    const decidedAt = new Date().toISOString();
    const { error: updateError } = await client
      .from("agent_action_approvals")
      .update({
        status: body.decision,
        decision_payload: body.decision_payload ?? {},
        decided_at: decidedAt,
        updated_at: decidedAt,
      })
      .eq("id", body.approval_id)
      .eq("user_id", user.id);

    if (updateError) throw updateError;

    await writeAuditLog(client, {
      userId: user.id,
      actorType: "user",
      eventType: `approval.${body.decision}`,
      targetTable: "agent_action_approvals",
      targetId: body.approval_id,
      agentRunId: approval.agent_run_id ?? undefined,
      scheduledJobId: approval.scheduled_job_id ?? undefined,
      metadata: {
        tool_name: approval.tool_name,
        action: approval.action,
      },
    });

    if (body.decision === "approved" && approval.agent_run_id) {
      await publishToWorker({
        path: "/jobs/agent-run",
        body: {
          user_id: user.id,
          agent_run_id: approval.agent_run_id,
          approval_id: body.approval_id,
        },
      });
    }

    return jsonResponse({
      approval_id: body.approval_id,
      status: body.decision,
    });
  } catch (error) {
    return errorResponse(error instanceof Error ? error.message : String(error), 500);
  }
});
