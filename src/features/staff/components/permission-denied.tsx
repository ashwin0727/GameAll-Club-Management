import { ShieldAlert } from "lucide-react";
import { Card } from "@/components/ui/card";

export function PermissionDenied({ message }: { message: string }) {
  return (
    <Card className="mx-auto mt-10 max-w-md p-10 text-center">
      <span className="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-muted">
        <ShieldAlert className="h-6 w-6 text-muted-foreground" aria-hidden />
      </span>
      <p className="mt-3 text-sm font-semibold">Access restricted</p>
      <p className="mt-1 text-sm text-muted-foreground">{message}</p>
    </Card>
  );
}
