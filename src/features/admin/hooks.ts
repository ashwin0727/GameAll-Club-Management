"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { adminApi, type PayoutVerification, type SetupReviewStatus, type TransactionView } from "@/features/admin/service";

export const adminKeys = {
  all: ["admin"] as const,
  overview: () => [...adminKeys.all, "overview"] as const,
  facilities: (search: string, offset: number) => [...adminKeys.all, "facilities", search, offset] as const,
  facility: (id: string) => [...adminKeys.all, "facility", id] as const,
  payoutFacilities: () => [...adminKeys.all, "payout-facilities"] as const,
  payoutMethods: (id: string) => [...adminKeys.all, "payout-methods", id] as const,
  venueVerifications: () => [...adminKeys.all, "venue-verifications"] as const,
  venueVerification: (id: string) => [...adminKeys.all, "venue-verification", id] as const,
  setupReviews: (status: SetupReviewStatus | null) => [...adminKeys.all, "setup-reviews", status] as const,
  setupReview: (id: string) => [...adminKeys.all, "setup-review", id] as const,
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

export const useVenueVerifications = () => useQuery({ queryKey: adminKeys.venueVerifications(), queryFn: adminApi.venueVerifications });

export const useVenueVerification = (facilityId: string) =>
  useQuery({ queryKey: adminKeys.venueVerification(facilityId), queryFn: () => adminApi.venueVerification(facilityId) });

export function useReviewLocation() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (v: { facilityId: string; status: PayoutVerification; note: string | null }) => adminApi.reviewLocation(v.facilityId, v.status, v.note),
    onSuccess: () => qc.invalidateQueries({ queryKey: adminKeys.all }),
  });
}

export function useReviewImage() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (v: { imageId: string; status: PayoutVerification; note: string | null }) => adminApi.reviewImage(v.imageId, v.status, v.note),
    onSuccess: () => qc.invalidateQueries({ queryKey: adminKeys.all }),
  });
}

export const useSetupReviews = (status: SetupReviewStatus | null) => useQuery({ queryKey: adminKeys.setupReviews(status), queryFn: () => adminApi.setupReviews(status) });

export const useSetupReview = (facilityId: string) => useQuery({ queryKey: adminKeys.setupReview(facilityId), queryFn: () => adminApi.setupReview(facilityId) });

export function useDecideSetup() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (v: { facilityId: string; decision: "APPROVED" | "REJECTED"; note: string | null }) => adminApi.decideSetup(v.facilityId, v.decision, v.note),
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
