import type { SupabaseClient } from "./supabase.ts";

export async function writeAuditLog(
  client: SupabaseClient,
  params: {
    userId?: string;
    actorType: "user" | "edge_function" | "worker" | "system";
    eventType: string;
    targetTable?: string;
    targetId?: string;
    agentRunId?: string;
    scheduledJobId?: string;
    metadata?: Record<string, unknown>;
  },
): Promise<void> {
  const { error } = await client.from("audit_logs").insert({
    user_id: params.userId,
    actor_type: params.actorType,
    event_type: params.eventType,
    target_table: params.targetTable,
    target_id: params.targetId,
    agent_run_id: params.agentRunId,
    scheduled_job_id: params.scheduledJobId,
    metadata: params.metadata ?? {},
  });

  if (error) {
    throw error;
  }
}
