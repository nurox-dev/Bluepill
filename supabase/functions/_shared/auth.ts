import { createUserClient } from "./supabase.ts";

export type AuthenticatedUser = {
  id: string;
};

export async function requireUser(req: Request): Promise<AuthenticatedUser> {
  const header = req.headers.get("Authorization") ?? "";
  const token = header.replace(/^Bearer\s+/i, "").trim();
  if (!token) {
    throw new Error("Missing Authorization bearer token.");
  }

  const client = createUserClient(token);
  const { data, error } = await client.auth.getUser(token);
  if (error || !data.user) {
    throw new Error("Invalid Supabase user token.");
  }

  return {
    id: data.user.id,
  };
}
