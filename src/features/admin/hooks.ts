"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { adminApi, type PayoutVerification, type TransactionView } from "@/features/admin/service";

export const adminKeys = {
  all: ["admin"] as const,
  overview: () => [...adminKeys.all, "overview"] as const,
  facilities: (search: string, offset: number) => [...adminKeys.all, "facilities", search, offset] as const,
  facility: (id: string) => [...adminKeys.all, "facility", id] as const,
  payoutFacilities: () => [...adminKeys.all, "payout-facilities"] as const,
  payoutMethods: (id: string) => [...adminKeys.all, "payout-methods", id] as const,
  txFacilities: () => [...adminKeys.all, "tx-facilities"] as const,
  transactions: (id: string, view: TransactionView, offset: number) => [...adminKeys.all, "transactions", id, view, offset] as const,
};

export const PAGE_SIZE = 25;

export const useAdminOverview = () => useQuery({ queryKey: adminKeys.overview(), queryFn: adminApi.overview });

export const useAdminFacilities = (search: string, offset: number) =>
  useQuery({
    queryKey: adminKeys.facilities(search, offset),
    queryFn: () => adminApi.facilities(search, PAGE_SIZE, offset),
    placeholderData: (prev) => prev,
  });

export const useAdminFacility = (id: string) => useQuery({ queryKey: adminKeys.facility(id), queryFn: () => adminApi.facility(id) });

export const usePayoutFacilities = () => useQuery({ queryKey: adminKeys.payoutFacilities(), queryFn: adminApi.payoutFacilities });

export const usePayoutMethods = (facilityId: string) =>
  useQuery({ queryKey: adminKeys.payoutMethods(facilityId), queryFn: () => adminApi.payoutMethods(facilityId) });

export function useReviewPayout() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (v: { methodId: string; status: PayoutVerification; note: string | null }) => adminApi.reviewPayout(v.methodId, v.status, v.note),
    onSuccess: () => qc.invalidateQueries({ queryKey: adminKeys.all }),
  });
}

export const useTransactionFacilities = () => useQuery({ queryKey: adminKeys.txFacilities(), queryFn: adminApi.transactionFacilities });

export const useTransactions = (facilityId: string, view: TransactionView, offset: number) =>
  useQuery({
    queryKey: adminKeys.transactions(facilityId, view, offset),
    queryFn: () => adminApi.transactions(facilityId, view, PAGE_SIZE, offset),
    placeholderData: (prev) => prev,
  });

export function useSettle() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (v: { ids: string[]; note: string | null }) => adminApi.markSettled(v.ids, v.note),
    onSuccess: () => qc.invalidateQueries({ queryKey: adminKeys.all }),
  });
}

export function useUnsettle() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (id: string) => adminApi.unsettle(id),
    onSuccess: () => qc.invalidateQueries({ queryKey: adminKeys.all }),
  });
}
