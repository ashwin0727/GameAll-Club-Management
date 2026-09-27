"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { Camera, ChevronRight, Pencil, Power, ShieldCheck, UserCog } from "lucide-react";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { Skeleton } from "@/components/ui/skeleton";
import { cn } from "@/lib/utils";
import { ServiceError } from "@/services/shared/service-error";
import { getStaffService } from "@/services/staff";
import { usePermissionContext } from "@/features/auth/context/permission-provider";
import { PermissionDenied } from "@/features/staff/components/permission-denied";
import { fmtDate, initials, statusBadge } from "@/features/staff/components/staff-page";
import { AVATAR_ACCEPT, AVATAR_MAX_BYTES } from "@/features/coaching/components/use-add-coach-form";
import type { Permission, RoleRow, StaffDetail } from "@/features/staff/types";

const TABS = ["Overview", "Access & Permissions", "Activity", "Notes"] as const;

export function StaffDetailsPage({ userId }: { userId: string }) {
  const perms = usePermissionContext();
  const facilityId = perms?.facilityId ?? null;

  const [tab, setTab] = useState<(typeof TABS)[number]>("Overview");
  const [detail, setDetail] = useState<StaffDetail | null>(null);
  const [roles, setRoles] = useState<RoleRow[]>([]);
  const [permCatalog, setPermCatalog] = useState<Permission[]>([]);
  const [state, setState] = useState<"loading" | "ready" | "error">("loading");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [changeRole, setChangeRole] = useState(false);
  const [nextRoleId, setNextRoleId] = useState("");
  const [notesDraft, setNotesDraft] = useState("");
  const [editingProfile, setEditingProfile] = useState(false);

  const load = useCallback(async () => {
    if (!facilityId) return;
    setError(null);
    try {
      const [d, r, p] = await Promise.all([
        getStaffService().getStaff(facilityId, userId),
        getStaffService().listRoles(facilityId),
        getStaffService().listPermissions(),
      ]);
      setDetail(d);
      setRoles(r);
      setPermCatalog(p);
      setNotesDraft(d.assignment?.notes ?? "");
      setState("ready");
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Unable to load this staff member.");
      setState("error");
    }
  }, [facilityId, userId]);

  useEffect(() => {
    void load();
  }, [load]);

  const permsByModule = useMemo(() => {
    const held = new Set(detail?.permissions ?? []);
    const groups = new Map<string, { held: Permission[]; missing: Permission[] }>();
    for (const p of permCatalog) {
      const g = groups.get(p.module) ?? { held: [], missing: [] };
      (held.has(p.key) ? g.held : g.missing).push(p);
      groups.set(p.module, g);
    }
    return [...groups.entries()];
  }, [permCatalog, detail]);

  if (!perms?.can("USERS_VIEW")) return <PermissionDenied message="You don't have permission to view staff." />;
  if (state === "loading") return <Skeleton className="h-96 w-full rounded-xl" />;
  if (state === "error" || !detail)
    return (
      <div className="space-y-3">
        <p className="text-sm text-destructive">{error ?? "Unable to load this staff member."}</p>
        <Button variant="outline" onClick={() => void load()}>
          Try again
        </Button>
      </div>
    );

  const a = detail.assignment;
  const canManageRoles = perms.can("USERS_MANAGE_ROLES");
  const canDeactivate = perms.can("USERS_DEACTIVATE");
  const canManageAccess = perms.can("USERS_MANAGE_FACILITY_ACCESS");

  async function run(fn: () => Promise<void>) {
    setBusy(true);
    setError(null);
    try {
      await fn();
      await load();
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Something went wrong.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="space-y-4">
      <nav aria-label="Breadcrumb" className="flex items-center gap-1 text-xs text-muted-foreground">
        <Link href="/users-roles/staff" className="hover:text-foreground">
          Users &amp; Roles
        </Link>
        <ChevronRight className="h-3 w-3" aria-hidden />
        <Link href="/users-roles/staff" className="hover:text-foreground">
          Staff
        </Link>
        <ChevronRight className="h-3 w-3" aria-hidden />
        <span className="text-foreground">{detail.fullName}</span>
      </nav>

      <Card className="p-5">
        <div className="flex flex-wrap items-start gap-4">
          <Avatar className="h-16 w-16">
            {detail.avatarUrl && <AvatarImage src={detail.avatarUrl} alt="" />}
            <AvatarFallback>{initials(detail.fullName)}</AvatarFallback>
          </Avatar>
          <div className="min-w-0 flex-1">
            <div className="flex flex-wrap items-center gap-2">
              <h1 className="text-xl font-semibold">{detail.fullName}</h1>
              {a && statusBadge(a.status)}
            </div>
            <p className="text-sm text-muted-foreground">{a?.roleName ?? "—"}</p>
            <dl className="mt-2 grid gap-x-6 gap-y-1 text-sm sm:grid-cols-2">
              <Row label="Email" value={detail.email} />
              <Row label="Phone" value={detail.phone ?? "—"} />
              <Row label="Joined" value={fmtDate(a?.joinedAt ?? null)} />
              <Row label="Last active" value={fmtDate(a?.lastLoginAt ?? null)} />
            </dl>
          </div>
        </div>
      </Card>

      <div className="flex flex-wrap gap-3">
        {perms.can("USERS_EDIT") && (
          <QuickAction icon={Pencil} label="Edit Profile" onClick={() => setEditingProfile(true)} />
        )}
        {canManageRoles && (
          <QuickAction icon={UserCog} label="Change Role" onClick={() => (setNextRoleId(a?.roleId ?? roles.find((r) => r.key === a?.baseRole)?.id ?? ""), setChangeRole(true))} />
        )}
        {canManageAccess && (
          <QuickAction icon={ShieldCheck} label="Manage Access" onClick={() => setTab("Access & Permissions")} />
        )}
        {canDeactivate && a && (
          <QuickAction
            icon={Power}
            label={a.status === "INACTIVE" ? "Reactivate" : "Deactivate"}
            danger={a.status !== "INACTIVE"}
            onClick={() =>
              run(() => getStaffService().setStatus(facilityId!, userId, a.status === "INACTIVE" ? "ACTIVE" : "INACTIVE"))
            }
          />
        )}
      </div>

      {error && <p className="text-sm text-destructive">{error}</p>}

      <div className="flex gap-1 border-b border-border text-sm">
        {TABS.map((t) => (
          <button
            key={t}
            type="button"
            onClick={() => setTab(t)}
            className={cn(
              "border-b-2 px-3 py-2 font-medium transition-colors",
              tab === t ? "border-primary text-foreground" : "border-transparent text-muted-foreground hover:text-foreground",
            )}
          >
            {t}
          </button>
        ))}
      </div>

      {tab === "Overview" && (
        <div className="grid gap-4 lg:grid-cols-3">
          <Card className="space-y-3 p-4 lg:col-span-2">
            <h2 className="text-sm font-semibold">About</h2>
            <dl className="grid grid-cols-2 gap-x-4 gap-y-3 text-sm">
              <Row label="Full name" value={detail.fullName} />
              <Row label="Email" value={detail.email} />
              <Row label="Phone" value={detail.phone ?? "—"} />
              <Row label="Role" value={a?.roleName ?? "—"} />
              <Row label="Status" value={a?.status ?? "—"} />
              <Row label="Joined" value={fmtDate(a?.joinedAt ?? null)} />
            </dl>
          </Card>
          <Card className="space-y-3 p-4">
            <h2 className="text-sm font-semibold">Facility Access</h2>
            {detail.facilityAccess.map((f) => (
              <div key={f.facilityId} className="rounded-md border border-border p-3">
                <div className="flex items-center justify-between">
                  <span className="text-sm font-medium">{f.facilityName}</span>
                  {f.isPrimary && <Badge variant="secondary">Primary</Badge>}
                </div>
                <p className="text-xs text-muted-foreground">{f.roleName}</p>
                {canManageAccess && f.facilityId === facilityId && detail.facilityAccess.length > 1 && (
                  <Button
                    type="button"
                    size="sm"
                    variant="outline"
                    className="mt-2"
                    disabled={busy}
                    onClick={() => run(() => getStaffService().removeFacilityAccess(f.facilityId, userId))}
                  >
                    Remove access
                  </Button>
                )}
              </div>
            ))}
          </Card>
        </div>
      )}

      {tab === "Access & Permissions" && (
        <Card className="space-y-4 p-4">
          <h2 className="text-sm font-semibold">Effective permissions — {a?.roleName}</h2>
          {permsByModule.map(([mod, g]) => (
            <div key={mod}>
              <p className="text-xs font-semibold text-muted-foreground">{mod}</p>
              <div className="mt-1 flex flex-wrap gap-1.5">
                {g.held.map((p) => (
                  <Badge key={p.key} variant={p.isDangerous ? "warning" : "secondary"}>
                    {p.label}
                  </Badge>
                ))}
                {g.held.length === 0 && <span className="text-xs text-muted-foreground">No access</span>}
              </div>
            </div>
          ))}
        </Card>
      )}

      {tab === "Activity" && (
        <Card className="p-0">
          {detail.recentActivity.length === 0 ? (
            <p className="p-6 text-center text-sm text-muted-foreground">No recorded activity yet.</p>
          ) : (
            <ul className="divide-y divide-border">
              {detail.recentActivity.map((e) => (
                <li key={e.id} className="flex items-center justify-between p-3 text-sm">
                  <div>
                    <span className="font-medium">{e.summary}</span>
                    <span className="block text-xs text-muted-foreground">
                      {e.actorName ?? "System"} · {new Date(e.createdAt).toLocaleString("en-IN")}
                    </span>
                  </div>
                </li>
              ))}
            </ul>
          )}
        </Card>
      )}

      {tab === "Notes" && (
        <Card className="space-y-3 p-4">
          <h2 className="text-sm font-semibold">Notes</h2>
          <Textarea
            rows={5}
            value={notesDraft}
            onChange={(e) => setNotesDraft(e.target.value)}
            disabled={!perms.can("USERS_EDIT")}
            placeholder="Internal notes about this staff member…"
          />
          {perms.can("USERS_EDIT") && (
            <Button
              type="button"
              size="sm"
              disabled={busy || notesDraft === (a?.notes ?? "")}
              onClick={() => run(() => getStaffService().updateProfile(facilityId!, userId, { notes: notesDraft.trim() || null }))}
            >
              Save notes
            </Button>
          )}
        </Card>
      )}

      <Dialog open={changeRole} onOpenChange={setChangeRole}>
        <DialogContent className="sm:max-w-sm">
          <DialogHeader>
            <DialogTitle>Change role</DialogTitle>
            <DialogDescription>
              Permissions are recalculated immediately. You can only assign a role whose permissions you hold yourself.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-1.5">
            <Label className="text-xs font-medium">Role</Label>
            <Select value={nextRoleId} onValueChange={setNextRoleId}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {roles
                  .filter((r) => r.isActive)
                  .map((r) => (
                    <SelectItem key={r.id} value={r.id}>
                      {r.name}
                    </SelectItem>
                  ))}
              </SelectContent>
            </Select>
          </div>
          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => setChangeRole(false)} disabled={busy}>
              Cancel
            </Button>
            <Button
              type="button"
              disabled={busy || !nextRoleId}
              onClick={() =>
                run(async () => {
                  await getStaffService().assignRole(facilityId!, userId, nextRoleId);
                  setChangeRole(false);
                })
              }
            >
              {busy ? "Saving…" : "Change role"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {editingProfile && (
        <EditProfileDialog
          facilityId={facilityId!}
          detail={detail}
          onClose={() => setEditingProfile(false)}
          onSaved={() => {
            setEditingProfile(false);
            void load();
          }}
        />
      )}
    </div>
  );
}

/** Full Name / Phone / Photo only — email is the Supabase Auth login credential and isn't
 *  editable from a plain profile patch. */
function EditProfileDialog({
  facilityId,
  detail,
  onClose,
  onSaved,
}: {
  facilityId: string;
  detail: StaffDetail;
  onClose: () => void;
  onSaved: () => void;
}) {
  const avatarInputRef = useRef<HTMLInputElement>(null);
  const [fullName, setFullName] = useState(detail.fullName);
  const [phone, setPhone] = useState(detail.phone ?? "");
  const [avatarFile, setAvatarFile] = useState<File | null>(null);
  const [avatarPreview, setAvatarPreview] = useState<string | null>(detail.avatarUrl);
  const [avatarError, setAvatarError] = useState<string | null>(null);
  const [uploadingAvatar, setUploadingAvatar] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  function pickAvatar(file: File | undefined) {
    if (!file) return;
    setAvatarError(null);
    if (!AVATAR_ACCEPT.includes(file.type)) {
      setAvatarError("Please choose a JPG, PNG or WEBP image.");
      return;
    }
    if (file.size > AVATAR_MAX_BYTES) {
      setAvatarError("That photo is larger than 2MB.");
      return;
    }
    setAvatarFile(file);
    setAvatarPreview((prev) => {
      if (prev && prev.startsWith("blob:")) URL.revokeObjectURL(prev);
      return URL.createObjectURL(file);
    });
  }

  async function save() {
    setBusy(true);
    setError(null);
    try {
      let avatarUrl: string | null = null;
      if (avatarFile) {
        setUploadingAvatar(true);
        try {
          avatarUrl = await getStaffService().uploadAvatar(avatarFile);
        } finally {
          setUploadingAvatar(false);
        }
      }
      await getStaffService().updateProfile(facilityId, detail.userId, {
        fullName: fullName.trim() || null,
        phone: phone.trim() || null,
        avatarUrl,
      });
      onSaved();
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Could not save changes.");
      setBusy(false);
    }
  }

  return (
    <Dialog open onOpenChange={(v) => !v && !busy && onClose()}>
      <DialogContent className="sm:max-w-sm">
        <DialogHeader>
          <DialogTitle>Edit profile</DialogTitle>
        </DialogHeader>
        <div className="space-y-3">
          <div className="flex items-center gap-3">
            <Avatar className="h-14 w-14">
              {avatarPreview && <AvatarImage src={avatarPreview} alt="" />}
              <AvatarFallback>
                <Camera className="h-5 w-5 text-muted-foreground" aria-hidden />
              </AvatarFallback>
            </Avatar>
            <div>
              <input ref={avatarInputRef} type="file" accept={AVATAR_ACCEPT.join(",")} className="hidden" onChange={(e) => pickAvatar(e.target.files?.[0])} />
              <Button type="button" size="sm" variant="outline" onClick={() => avatarInputRef.current?.click()}>
                Change Photo
              </Button>
              <p className="mt-1 text-xs text-muted-foreground">JPG, PNG (Max 2MB)</p>
              {avatarError && <p className="mt-1 text-xs text-destructive">{avatarError}</p>}
            </div>
          </div>
          <div className="space-y-1.5">
            <Label className="text-xs font-medium">Full Name</Label>
            <Input value={fullName} onChange={(e) => setFullName(e.target.value)} />
          </div>
          <div className="space-y-1.5">
            <Label className="text-xs font-medium">Phone</Label>
            <Input value={phone} onChange={(e) => setPhone(e.target.value)} />
          </div>
          {error && <p className="text-sm text-destructive">{error}</p>}
        </div>
        <DialogFooter>
          <Button type="button" variant="outline" disabled={busy} onClick={onClose}>
            Cancel
          </Button>
          <Button type="button" disabled={busy} onClick={() => void save()}>
            {busy ? (uploadingAvatar ? "Uploading photo…" : "Saving…") : "Save"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <dt className="text-xs text-muted-foreground">{label}</dt>
      <dd className="mt-0.5 font-medium">{value}</dd>
    </div>
  );
}

function QuickAction({
  icon: Icon,
  label,
  onClick,
  danger,
}: {
  icon: React.ComponentType<{ className?: string }>;
  label: string;
  onClick: () => void;
  danger?: boolean;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        "flex items-center gap-2 rounded-md border border-border px-3 py-2 text-sm font-medium transition-colors hover:bg-accent",
        danger && "text-destructive hover:bg-destructive/10",
      )}
    >
      <Icon className="h-4 w-4" aria-hidden />
      {label}
    </button>
  );
}
