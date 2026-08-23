"use client";

const CURRENCY_SYMBOL: Record<string, string> = { INR: "₹", USD: "$", GBP: "£" };

export function AmountInput({
  value,
  onChange,
  currency,
  unitLabel,
  "aria-label": ariaLabel,
}: {
  value: string;
  onChange: (value: string) => void;
  currency: string;
  unitLabel: string;
  "aria-label": string;
}) {
  return (
    <div className="flex h-12 min-h-[44px] items-center rounded-md border border-input bg-secondary/60 pl-3 shadow-sm focus-within:ring-1 focus-within:ring-ring">
      <span className="text-base text-muted-foreground sm:text-sm">{CURRENCY_SYMBOL[currency] ?? currency}</span>
      <input
        aria-label={ariaLabel}
        inputMode="decimal"
        value={value}
        onChange={(e) => onChange(e.target.value.replace(/[^0-9.]/g, ""))}
        className="h-full w-full bg-transparent px-2 text-base outline-none sm:text-sm"
        placeholder="0"
      />
      <span className="pr-3 text-xs whitespace-nowrap text-muted-foreground">{unitLabel}</span>
    </div>
  );
}