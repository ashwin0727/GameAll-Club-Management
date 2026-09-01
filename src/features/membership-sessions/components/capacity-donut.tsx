/** A tiny SVG donut for the session Capacity Overview — no charting lib. */
export function CapacityDonut({
  capacity,
  members,
  guestsBooked,
  availableToRelease,
  size = 120,
}: {
  capacity: number;
  members: number;
  guestsBooked: number;
  availableToRelease: number;
  size?: number;
}) {
  const total = Math.max(capacity, 1);
  const segments = [
    { value: members, color: "#00D084", label: "Members" },
    { value: guestsBooked, color: "#5B6CFF", label: "Guests Booked" },
    { value: availableToRelease, color: "#94a3b8", label: "Available to Release" },
  ];
  const stroke = 14;
  const r = (size - stroke) / 2;
  const circ = 2 * Math.PI * r;
  let offset = 0;

  return (
    <div className="flex items-center gap-4">
      <div className="relative shrink-0" style={{ width: size, height: size }}>
        <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} className="-rotate-90">
          <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="var(--border, #e5e7eb)" strokeWidth={stroke} />
          {segments.map((s, i) => {
            const len = (Math.min(s.value, total) / total) * circ;
            const dash = `${len} ${circ - len}`;
            const el = (
              <circle
                key={i}
                cx={size / 2}
                cy={size / 2}
                r={r}
                fill="none"
                stroke={s.color}
                strokeWidth={stroke}
                strokeDasharray={dash}
                strokeDashoffset={-offset}
              />
            );
            offset += len;
            return el;
          })}
        </svg>
        <span className="absolute inset-0 flex items-center justify-center text-lg font-semibold text-foreground">
          {capacity}
        </span>
      </div>
      <ul className="space-y-1.5 text-sm">
        {segments.map((s) => (
          <li key={s.label} className="flex items-center gap-2">
            <span className="h-2.5 w-2.5 rounded-full" style={{ backgroundColor: s.color }} />
            <span className="text-muted-foreground">{s.label}</span>
            <span className="ml-auto font-medium text-foreground">
              {s.value} <span className="text-muted-foreground">({Math.round((Math.min(s.value, total) / total) * 100)}%)</span>
            </span>
          </li>
        ))}
      </ul>
    </div>
  );
}