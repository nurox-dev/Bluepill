import { requireUser } from "../_shared/auth.ts";
import { writeAuditLog } from "../_shared/audit.ts";
import { errorResponse, handleCors, jsonResponse } from "../_shared/cors.ts";
import { checkRateLimit } from "../_shared/permissions.ts";
import { publishToWorker } from "../_shared/qstash.ts";
import { createServiceClient } from "../_shared/supabase.ts";

type ScheduleJobRequest = {
  job_type: string;
  scheduled_for: string;
  payload?: Record<string, unknown>;
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
    const body = (await req.json()) as ScheduleJobRequest;
    const jobType = body.job_type?.trim();
    const scheduledFor = new Date(body.scheduled_for);

    if (!jobType || Number.isNaN(scheduledFor.getTime())) {
      return errorResponse("job_type and scheduled_for are required.", 422);
    }

    const permission = await checkRateLimit(client, {
      userId: user.id,
      endpoint: "schedule-job",
      action: jobType,
      limitCount: 100,
      metadata: { scheduled_for: scheduledFor.toISOString() },
    });

    if (!permission.allowed) {
      return errorResponse(permission.reason ?? "Rate limit exceeded.", 429);
    }

    const { data: job, error: jobError } = await client
      .from("scheduled_jobs")
      .insert({
        user_id: user.id,
        job_type: jobType,
        status: "scheduled",
        queue_provider: "qstash",
        idempotency_key: body.idempotency_key,
        scheduled_for: scheduledFor.toISOString(),
        payload: body.payload ?? {},
      })
      .select("id")
      .single();

    if (jobError) throw jobError;

    await writeAuditLog(client, {
      userId: user.id,
      actorType: "edge_function",
      eventType: "scheduled_job.created",
      targetTable: "scheduled_jobs",
      targetId: job.id as string,
      scheduledJobId: job.id as string,
      metadata: { job_type: jobType },
    });

    const delaySeconds = Math.max(
      0,
      Math.ceil((scheduledFor.getTime() - Date.now()) / 1000),
    );

    const published = await publishToWorker({
      path: "/jobs/scheduled-job",
      delaySeconds,
      body: {
        user_id: user.id,
        scheduled_job_id: job.id,
      },
    });

    await client
      .from("scheduled_jobs")
      .update({
        external_job_id: published.messageId,
        updated_at: new Date().toISOString(),
      })
      .eq("id", job.id);

    return jsonResponse({
      scheduled_job_id: job.id,
      status: "scheduled",
      qstash_message_id: published.messageId,
    });
  } catch (error) {
    return errorResponse(error instanceof Error ? error.message : String(error), 500);
  }
});
