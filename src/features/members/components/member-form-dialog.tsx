"use client";

import { useState } from "react";
import { zodResolver } from "@hookform/resolvers/zod";
import { useForm } from "react-hook-form";
import { Loader2, Plus } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
  DialogDescription,
} from "@/components/ui/dialog";
import { createMemberSchema, type CreateMemberInput } from "@/features/members/validation";
import { useCreateMember } from "@/features/members/hooks/use-members";

export function MemberFormDialog() {
  const [open, setOpen] = useState(false);
  const createMember = useCreateMember();
  const {
    register,
    handleSubmit,
    reset,
    formState: { errors },
  } = useForm<CreateMemberInput>({
    resolver: zodResolver(createMemberSchema),
    defaultValues: { full_name: "", email: "", phone: "" },
  });

  const onSubmit = (values: CreateMemberInput) => {
    createMember.mutate(values, {
      onSuccess: () => {
        toast.success("Member added — a set-password email has been sent");
        reset();
        setOpen(false);
      },
      onError: (error) => {
        toast.error(error.message);
      },
    });
  };

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button size="sm" className="gap-2">
          <Plus className="h-4 w-4" />
          Add Member
        </Button>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Add a new member</DialogTitle>
          <DialogDescription>
            Creates a login account for the member and emails them a link to set their password.
          </DialogDescription>
        </DialogHeader>
        <form onSubmit={handleSubmit(onSubmit)} className="space-y-4" noValidate>
          <div className="space-y-2">
            <Label htmlFor="full_name">Full name</Label>
            <Input id="full_name" placeholder="Jane Doe" {...register("full_name")} />
            {errors.full_name && (
              <p className="text-xs text-destructive">{errors.full_name.message}</p>
            )}
          </div>
          <div className="space-y-2">
            <Label htmlFor="email">Email</Label>
            <Input id="email" type="email" placeholder="jane@example.com" {...register("email")} />
            {errors.email && <p className="text-xs text-destructive">{errors.email.message}</p>}
          </div>
          <div className="space-y-2">
            <Label htmlFor="phone">Phone (optional)</Label>
            <Input id="phone" placeholder="9876543210" {...register("phone")} />
            {errors.phone && <p className="text-xs text-destructive">{errors.phone.message}</p>}
          </div>
          <DialogFooter>
            <Button type="submit" disabled={createMember.isPending} className="gap-2">
              {createMember.isPending && <Loader2 className="h-4 w-4 animate-spin" />}
              Add Member
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}