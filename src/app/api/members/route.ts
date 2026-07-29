import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";
import { getCurrentProfile } from "@/features/auth/api/auth.api";
import { createMemberSchema } from "@/features/members/validation";

export async function POST(request: Request) {
  const supabase = await createClient();
  const actor = await getCurrentProfile(supabase);

  if (!actor || (actor.role !== "admin" && actor.role !== "staff")) {
    return NextResponse.json({ error: "Not authorized" }, { status: 403 });
  }

  const body = await request.json();
  const parsed = createMemberSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: parsed.error.issues[0]?.message ?? "Invalid input" }, { status: 400 });
  }

  const { full_name, email, phone } = parsed.data;
  const admin = createAdminClient();

  const { data: created, error: createError } = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
    user_metadata: { full_name },
    password: crypto.randomUUID(),
  });

  if (createError || !created.user) {
    return NextResponse.json(
      { error: createError?.message ?? "Failed to create member" },
      { status: 400 },
    );
  }

  const { error: updateError } = await admin
    .from("profiles")
    .update({ full_name, phone: phone || null })
    .eq("id", created.user.id);

  if (updateError) {
    return NextResponse.json({ error: updateError.message }, { status: 400 });
  }

  const { error: resetError } = await admin.auth.resetPasswordForEmail(email);
  if (resetError) {
    console.error("Failed to send set-password email:", resetError.message);
  }

  return NextResponse.json({ id: created.user.id }, { status: 201 });
}