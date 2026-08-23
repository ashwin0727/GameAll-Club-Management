"use client";

const OPTIONS: { value: string; label: string }[] = Array.from({ length: 48 }, (_, i) => {
  const hour24 = Math.floor(i / 2);
  const minute = i % 2 === 0 ? "00" : "30";
  const value = `${String(hour24).padStart(2, "0")}:${minute}`;
  const hour12 = hour24 % 12 === 0 ? 12 : hour24 % 12;
  const meridiem = hour24 < 12 ? "AM" : "PM";
  return { value, label: `${hour12}:${minute} ${meridiem}` };
});

export function TimeSelect({
  value,
  onChange,
  "aria-label": ariaLabel,
}: {
  value: string;
  onChange: (value: string) => void;
  "aria-label": string;
}) {
  return (
    <select
      aria-label={ariaLabel}
      value={value}
      onChange={(e) => onChange(e.target.value)}
      className="h-12 min-h-[44px] w-full rounded-md border border-input bg-secondary/60 px-3 text-base shadow-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring sm:text-sm"
    >
      {!OPTIONS.some((o) => o.value === value) && <option value={value}>{value}</option>}
      {OPTIONS.map((option) => (
        <option key={option.value} value={option.value}>
          {option.label}
        </option>
      ))}
    </select>
  );
}