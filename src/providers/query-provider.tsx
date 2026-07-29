"use client";

import * as React from "react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { QUERY_STALE_TIME_MS } from "@/lib/constants";

export function QueryProvider({ children }: { children: React.ReactNode }) {
  const [queryClient] = React.useState(
    () =>
      new QueryClient({
        defaultOptions: {
          queries: {
            staleTime: QUERY_STALE_TIME_MS,
            refetchOnWindowFocus: false,
            retry: 1,
          },
        },
      }),
  );

  return <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>;
}