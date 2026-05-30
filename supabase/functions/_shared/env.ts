export function requiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

export const env = {
  supabaseUrl: requiredEnv("SUPABASE_URL"),
  supabaseAnonKey: requiredEnv("SUPABASE_ANON_KEY"),
  supabaseServiceRoleKey: requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
  qstashUrl: Deno.env.get("QSTASH_URL") ?? "https://qstash.upstash.io",
  qstashToken: requiredEnv("QSTASH_TOKEN"),
  workerBaseUrl: requiredEnv("WORKER_BASE_URL"),
  workerSharedSecret: requiredEnv("WORKER_SHARED_SECRET"),
  agentDailyRunLimit: Number(Deno.env.get("AGENT_DAILY_RUN_LIMIT") ?? "50"),
};
