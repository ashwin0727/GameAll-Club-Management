"use client";

import { useState } from "react";
import { SlidersHorizontal } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { AnalyticsFilterBar } from "./analytics-filter-bar";
import type { AnalyticsFilter } from "../types";

/** Mobile filter entry point — the same controls in a sheet (spec §38). */
export function AnalyticsFilterSheet({
  filter,
  onChange,
}: {
  filter: AnalyticsFilter;
  onChange: (next: AnalyticsFilter) => void;
}) {
  const [open, setOpen] = useState(false);
  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button variant="outline" size="sm" className="min-h-9">
          <SlidersHorizontal className="h-4 w-4" aria-hidden /> Filters
        </Button>
      </DialogTrigger>
      <DialogContent className="max-w-sm">
        <DialogHeader>
          <DialogTitle>Filters</DialogTitle>
          <DialogDescription>Facility, date range, sport and court for this report.</DialogDescription>
        </DialogHeader>
        <AnalyticsFilterBar filter={filter} onChange={onChange} layout="stack" />
        <Button onClick={() => setOpen(false)}>Apply</Button>
      </DialogContent>
    </Dialog>
  );
}
