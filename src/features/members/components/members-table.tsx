"use client";

import { useState } from "react";
import { useDebouncedValue } from "@/hooks/use-debounced-value";
import { Users, Search } from "lucide-react";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Button } from "@/components/ui/button";
import { TableSkeleton } from "@/components/shared/loading-state";
import { EmptyState } from "@/components/shared/empty-state";
import { ErrorState } from "@/components/shared/error-state";
import { MemberFormDialog } from "@/features/members/components/member-form-dialog";
import { useMembers } from "@/features/members/hooks/use-members";
import { formatDate, getInitials } from "@/lib/utils";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";

const PAGE_SIZE = 10;

export function MembersTable() {
  const [search, setSearch] = useState("");
  const [page, setPage] = useState(0);
  const debouncedSearch = useDebouncedValue(search, 300);

  const { data, isLoading, isError, refetch, isPlaceholderData } = useMembers({
    search: debouncedSearch,
    page,
    pageSize: PAGE_SIZE,
  });

  const totalPages = data ? Math.max(1, Math.ceil(data.totalCount / PAGE_SIZE)) : 1;

  return (
    <div className="space-y-4">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div className="relative w-full sm:max-w-xs">
          <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            placeholder="Search members..."
            value={search}
            onChange={(e) => {
              setSearch(e.target.value);
              setPage(0);
            }}
            className="pl-9"
          />
        </div>
        <MemberFormDialog />
      </div>

      {isLoading ? (
        <TableSkeleton rows={PAGE_SIZE} columns={4} />
      ) : isError ? (
        <ErrorState message="Couldn't load members." onRetry={() => refetch()} />
      ) : !data || data.members.length === 0 ? (
        <EmptyState
          icon={Users}
          title={search ? "No members match your search" : "No members yet"}
          description={
            search
              ? "Try a different name."
              : "Add your first member to start tracking memberships."
          }
        />
      ) : (
        <>
          <div className="rounded-xl border border-border bg-card">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Member</TableHead>
                  <TableHead>Phone</TableHead>
                  <TableHead>Role</TableHead>
                  <TableHead>Joined</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody className={isPlaceholderData ? "opacity-60" : undefined}>
                {data.members.map((member) => (
                  <TableRow key={member.id}>
                    <TableCell>
                      <div className="flex items-center gap-3">
                        <Avatar className="h-8 w-8">
                          <AvatarFallback>{getInitials(member.full_name)}</AvatarFallback>
                        </Avatar>
                        <span className="font-medium">{member.full_name}</span>
                      </div>
                    </TableCell>
                    <TableCell className="text-muted-foreground">
                      {member.phone ?? "—"}
                    </TableCell>
                    <TableCell>
                      <Badge variant="secondary" className="capitalize">
                        {member.role}
                      </Badge>
                    </TableCell>
                    <TableCell className="text-muted-foreground">
                      {formatDate(member.created_at)}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>

          <div className="flex items-center justify-between text-sm text-muted-foreground">
            <span>
              Page {page + 1} of {totalPages} · {data.totalCount} members
            </span>
            <div className="flex gap-2">
              <Button
                variant="outline"
                size="sm"
                disabled={page === 0}
                onClick={() => setPage((p) => Math.max(0, p - 1))}
              >
                Previous
              </Button>
              <Button
                variant="outline"
                size="sm"
                disabled={page + 1 >= totalPages}
                onClick={() => setPage((p) => p + 1)}
              >
                Next
              </Button>
            </div>
          </div>
        </>
      )}
    </div>
  );
}