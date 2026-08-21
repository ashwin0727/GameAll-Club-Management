export function PlayingAreaSummary({
  sportCount,
  playingAreaCount,
}: {
  sportCount: number;
  playingAreaCount: number;
}) {
  return (
    <p className="text-sm text-muted-foreground" role="status">
      {sportCount} {sportCount === 1 ? "Sport" : "Sports"} · {playingAreaCount}{" "}
      {playingAreaCount === 1 ? "Playing Area" : "Playing Areas"}
    </p>
  );
}