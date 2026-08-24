"use client";

import { useEffect, useState } from "react";
import { Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from "@/components/ui/dialog";
import { validateMemberName, validateMemberPhone } from "@/features/members/validation";
import { getMembershipService } from "@/services/memberships";
import { MemberAlreadyExistsError } from "@/services/memberships/supabase-membership.service";

/**
 * Creates a facility CUSTOMER/PLAYER record — never a Supabase Auth account.
 * A Member has no login, no password, and needs no email verification.
 */
export function MemberFormDialog({
  open,
  onOpenChange,
  facilityId,
  onCreated,
  onViewExisting,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  facilityId: string;
  /** A new member record was created — id is the new member's id. */
  onCreated: (memberId: string) => void;
  /** This phone number already belongs to a member — caller should assign a membership to that member instead. */
  onViewExisting: (memberId: string) => void;
}) {
  const [fullName, setFullName] = useState("");
  const [phone, setPhone] = useState("");
  const [email, setEmail] = useState("");
  const [dateOfBirth, setDateOfBirth] = useState("");
  const [gender, setGender] = useState("");
  const [notes, setNotes] = useState("");
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [duplicateId, setDuplicateId] = useState<string | null>(null);

  useEffect(() => {
    if (!open) return;
    setFullName("");
    setPhone("");
    setEmail("");
    setDateOfBirth("");
    setGender("");
    setNotes("");
    setError(null);
    setDuplicateId(null);
  }, [open]);

  async function save() {
    const nameError = validateMemberName(fullName);
    if (nameError) {
      setError(nameError);
      return;
    }
    const phoneError = validateMemberPhone(phone);
    if (phoneError) {
      setError(phoneError);
      return;
    }

    setIsSaving(true);
    setError(null);
    setDuplicateId(null);
    try {
      const member = await getMembershipService().createMember({
        facilityId,
        fullName,
        phone,
        email: email.trim() || null,
        dateOfBirth: dateOfBirth || null,
        gender: gender.trim() || null,
        notes: notes.trim() || null,
      });
      onOpenChange(false);
      onCreated(member.id);
    } catch (err) {
      if (err instanceof MemberAlreadyExistsError) {
        setDuplicateId(err.existingMemberId);
      } else {
        setError(err instanceof Error ? err.message : "Unable to save this member.");
      }
    } finally {
      setIsSaving(false);
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Add Member</DialogTitle>
          <DialogDescription>Creates a facility customer profile — no login or password is created.</DialogDescription>
        </DialogHeader>
        <div className="space-y-3">
          <div className="space-y-2">
            <Label htmlFor="member_full_name">Full name</Label>
            <Input id="member_full_name" placeholder="Jane Doe" value={fullName} onChange={(e) => setFullName(e.target.value)} />
          </div>
          <div className="space-y-2">
            <Label htmlFor="member_phone">Mobile number</Label>
            <Input id="member_phone" placeholder="9876543210" value={phone} onChange={(e) => setPhone(e.target.value)} />
          </div>
          <div className="space-y-2">
            <Label htmlFor="member_email">Email (optional)</Label>
            <Input id="member_email" type="email" placeholder="jane@example.com" value={email} onChange={(e) => setEmail(e.target.value)} />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-2">
              <Label htmlFor="member_dob">Date of birth (optional)</Label>
              <Input id="member_dob" type="date" value={dateOfBirth} onChange={(e) => setDateOfBirth(e.target.value)} />
            </div>
            <div className="space-y-2">
              <Label htmlFor="member_gender">Gender (optional)</Label>
              <Input id="member_gender" placeholder="e.g. Male" value={gender} onChange={(e) => setGender(e.target.value)} />
            </div>
          </div>
          <div className="space-y-2">
            <Label htmlFor="member_notes">Notes (optional)</Label>
            <Input id="member_notes" placeholder="Notes" value={notes} onChange={(e) => setNotes(e.target.value)} />
          </div>

          {duplicateId && (
            <div className="flex items-center justify-between rounded-md border border-amber-300 bg-amber-50 px-3 py-2 text-sm text-amber-900 dark:border-amber-900 dark:bg-amber-950 dark:text-amber-200">
              <span>Member already exists.</span>
              <Button
                type="button"
                variant="link"
                size="sm"
                className="h-auto p-0"
                onClick={() => {
                  onOpenChange(false);
                  onViewExisting(duplicateId);
                }}
              >
                View Existing Member
              </Button>
            </div>
          )}
          {error && <p className="text-sm text-destructive">{error}</p>}
        </div>
        <DialogFooter>
          <Button type="button" onClick={save} disabled={isSaving} className="gap-2">
            {isSaving && <Loader2 className="h-4 w-4 animate-spin" />}
            Create Member
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}