import { redirect } from "next/navigation";

/** The separate Members list is gone — memberships are managed from the Membership dashboard. */
export default function Page() {
  redirect("/memberships/v1");
}
