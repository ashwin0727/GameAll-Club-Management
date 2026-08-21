export function SelectedSportsSummary({ count }: { count: number }) {
  const label = count === 0 ? "No sports selected" : count === 1 ? "1 sport selected" : `${count} sports selected`;

  return (
    <p className="text-sm text-muted-foreground" role="status">
      {label}
    </p>
  );
}