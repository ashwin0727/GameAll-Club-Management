import { Card } from "@/components/ui/card";

/** A section whose underlying module doesn't exist yet — an honest "not available" state instead of fabricated numbers. */
export function UnavailableCard({ title, message }: { title: string; message: string }) {
  return (
    <Card className="space-y-2 p-4 sm:p-5">
      <h3 className="text-sm font-semibold">{title}</h3>
      <p className="text-sm text-muted-foreground">{message}</p>
    </Card>
  );
}