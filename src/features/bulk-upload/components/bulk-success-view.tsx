"use client";

import { useState, type ReactNode } from "react";
import Link from "next/link";
import { AlertTriangle, Check, CheckCircle2, Copy } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";

export interface SuccessColumn<T> {
  header: string;
  cell: (row: T) => ReactNode;
  className?: string;
}

/** Copies a payment link; falls back to a prompt where the clipboard is blocked. */
export function CopyLinkButton({ url }: { url: string }) {
  const [copied, setCopied] = useState(false);
  async function copy() {
    try {
      await navigator.clipboard.writeText(url);
    } catch {
      window.prompt("Copy this link:", url);
    }
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }
  return (
    <Button type="button" size="sm" variant="outline" className="h-7 px-2 text-xs" onClick={() => void copy()}>
      {copied ? <Check className="mr-1 h-3.5 w-3.5" aria-hidden /> : <Copy className="mr-1 h-3.5 w-3.5" aria-hidden />}
      {copied ? "Copied" : "Copy Link"}
    </Button>
  );
}

interface Props<T extends { error: string | null; rowNumber: number; shortUrl: string | null }> {
  title: string;
  noun: "Members" | "Students";
  rows: T[] | null;
  columns: SuccessColumn<T>[];
  /** Where the list of everyone lives, and the form to upload more. */
  listHref: string;
  listLabel: string;
  addHref: string;
}

/** The page after a bulk upload: who was created, and each person's payment link. */
export function BulkSuccessView<T extends { error: string | null; rowNumber: number; shortUrl: string | null; name: string }>({
  title,
  noun,
  rows,
  columns,
  listHref,
  listLabel,
  addHref,
}: Props<T>) {
  if (!rows) {
    return (
      <Card className="mx-auto max-w-xl space-y-3 p-8 text-center">
        <h1 className="text-lg font-semibold">Nothing to show</h1>
        <p className="text-sm text-muted-foreground">This page appears right after a bulk upload. Start one from the add form.</p>
        <Button asChild>
          <Link href={addHref}>Go to Bulk Upload</Link>
        </Button>
      </Card>
    );
  }
  const failed = rows.filter((r) => r.error && !r.shortUrl && !isCreated(r));
  const created = rows.length - failed.length;
  const needAttention = rows.filter((r) => r.error);

  return (
    <div className="space-y-5">
      <Card className="flex flex-col items-center gap-2 p-8 text-center">
        <span className="flex h-14 w-14 items-center justify-center rounded-full bg-success/15 text-success">
          <CheckCircle2 className="h-8 w-8" aria-hidden />
        </span>
        <h1 className="text-xl font-bold text-foreground">{title}</h1>
        <p className="text-sm text-muted-foreground">
          {created} of {rows.length} {noun.toLowerCase()} added. Razorpay is sending each a payment link by SMS — you can also copy any link below, or later from their details page.
        </p>
      </Card>

      {needAttention.length > 0 && (
        <Card className="space-y-2 border-warning/40 bg-warning/5 p-4" role="alert">
          <p className="flex items-center gap-1.5 text-sm font-medium text-foreground">
            <AlertTriangle className="h-4 w-4 text-warning" aria-hidden />
            {needAttention.length} {needAttention.length === 1 ? "row needs" : "rows need"} attention
          </p>
          <ul className="space-y-1 text-xs text-muted-foreground">
            {needAttention.map((r) => (
              <li key={r.rowNumber}>
                Row {r.rowNumber} · {r.name}: {r.error}
              </li>
            ))}
          </ul>
        </Card>
      )}

      <Card className="overflow-hidden p-0">
        <div className="overflow-x-auto">
          <table className="w-full min-w-[720px] text-left text-sm">
            <thead className="bg-muted/60 text-xs text-muted-foreground">
              <tr>
                {columns.map((c) => (
                  <th key={c.header} className={`px-4 py-2.5 font-medium ${c.className ?? ""}`}>
                    {c.header}
                  </th>
                ))}
                <th className="px-4 py-2.5 font-medium">Payment Link</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border/60">
              {rows.map((r) => (
                <tr key={r.rowNumber}>
                  {columns.map((c) => (
                    <td key={c.header} className={`px-4 py-2.5 ${c.className ?? ""}`}>
                      {c.cell(r)}
                    </td>
                  ))}
                  <td className="px-4 py-2.5">{r.shortUrl ? <CopyLinkButton url={r.shortUrl} /> : <span className="text-xs text-muted-foreground">—</span>}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </Card>

      <div className="flex flex-wrap justify-end gap-3">
        <Button asChild variant="outline">
          <Link href={addHref}>Upload More</Link>
        </Button>
        <Button asChild>
          <Link href={listHref}>{listLabel}</Link>
        </Button>
      </div>
    </div>
  );
}

/** A row counts as created when it has an id, even if only its link failed. */
function isCreated(r: object): boolean {
  const x = r as { membershipId?: string | null; enrollmentId?: string | null };
  return Boolean(x.membershipId || x.enrollmentId);
}
