/**
 * Hand-written to match supabase/migrations/0001_init.sql.
 * Regenerate with `supabase gen types typescript --linked` once the project is linked,
 * and diff against this file to catch drift.
 */

export type Role = "admin" | "staff" | "member";
export type FacilityRole = "owner" | "manager" | "staff";
export type MembershipStatus = "active" | "expired" | "cancelled" | "pending";
export type PaymentStatus = "created" | "paid" | "failed" | "refunded";
export type BookingStatus = "pending" | "confirmed" | "cancelled" | "completed";
export type InventoryTxnType = "checkout" | "return" | "restock" | "damage";

export interface Database {
  __InternalSupabase: {
    PostgrestVersion: "12";
  };
  public: {
    Tables: {
      profiles: {
        Row: {
          id: string;
          full_name: string;
          email: string;
          avatar_url: string | null;
          role: Role;
          phone: string | null;
          onboarding_completed: boolean;
          created_at: string;
        };
        Insert: {
          id: string;
          full_name: string;
          email: string;
          avatar_url?: string | null;
          role?: Role;
          phone?: string | null;
          onboarding_completed?: boolean;
          created_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["profiles"]["Insert"]>;
        Relationships: [];
      };
      facilities: {
        Row: {
          id: string;
          name: string;
          slug: string;
          owner_id: string;
          city: string | null;
          address: string | null;
          timezone: string;
          currency: string;
          created_at: string;
        };
        Insert: {
          id?: string;
          name: string;
          slug: string;
          owner_id: string;
          city?: string | null;
          address?: string | null;
          timezone?: string;
          currency?: string;
          created_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["facilities"]["Insert"]>;
        Relationships: [
          {
            foreignKeyName: "facilities_owner_id_fkey";
            columns: ["owner_id"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      facility_users: {
        Row: {
          facility_id: string;
          user_id: string;
          role: FacilityRole;
          created_at: string;
        };
        Insert: {
          facility_id: string;
          user_id: string;
          role?: FacilityRole;
          created_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["facility_users"]["Insert"]>;
        Relationships: [
          {
            foreignKeyName: "facility_users_facility_id_fkey";
            columns: ["facility_id"];
            isOneToOne: false;
            referencedRelation: "facilities";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "facility_users_user_id_fkey";
            columns: ["user_id"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      sports: {
        Row: {
          id: string;
          key: string;
          name: string;
          is_active: boolean;
          sort_order: number;
        };
        Insert: {
          id?: string;
          key: string;
          name: string;
          is_active?: boolean;
          sort_order?: number;
        };
        Update: Partial<Database["public"]["Tables"]["sports"]["Insert"]>;
        Relationships: [];
      };
      facility_sports: {
        Row: {
          facility_id: string;
          sport_id: string;
          created_at: string;
        };
        Insert: {
          facility_id: string;
          sport_id: string;
          created_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["facility_sports"]["Insert"]>;
        Relationships: [
          {
            foreignKeyName: "facility_sports_facility_id_fkey";
            columns: ["facility_id"];
            isOneToOne: false;
            referencedRelation: "facilities";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "facility_sports_sport_id_fkey";
            columns: ["sport_id"];
            isOneToOne: false;
            referencedRelation: "sports";
            referencedColumns: ["id"];
          },
        ];
      };
      courts: {
        Row: {
          id: string;
          facility_id: string;
          sport_id: string;
          name: string;
          surface: string | null;
          hourly_rate_inr: number;
          is_active: boolean;
          created_at: string;
        };
        Insert: {
          id?: string;
          facility_id: string;
          sport_id: string;
          name: string;
          surface?: string | null;
          hourly_rate_inr?: number;
          is_active?: boolean;
          created_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["courts"]["Insert"]>;
        Relationships: [
          {
            foreignKeyName: "courts_facility_id_fkey";
            columns: ["facility_id"];
            isOneToOne: false;
            referencedRelation: "facilities";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "courts_sport_id_fkey";
            columns: ["sport_id"];
            isOneToOne: false;
            referencedRelation: "sports";
            referencedColumns: ["id"];
          },
        ];
      };
      membership_plans: {
        Row: {
          id: string;
          facility_id: string;
          name: string;
          price_inr: number;
          duration_days: number;
          features: string[];
          is_active: boolean;
          created_at: string;
        };
        Insert: {
          id?: string;
          facility_id: string;
          name: string;
          price_inr: number;
          duration_days: number;
          features?: string[];
          is_active?: boolean;
          created_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["membership_plans"]["Insert"]>;
        Relationships: [
          {
            foreignKeyName: "membership_plans_facility_id_fkey";
            columns: ["facility_id"];
            isOneToOne: false;
            referencedRelation: "facilities";
            referencedColumns: ["id"];
          },
        ];
      };
      memberships: {
        Row: {
          id: string;
          facility_id: string;
          member_id: string;
          plan_id: string;
          status: MembershipStatus;
          start_date: string;
          end_date: string;
          auto_renew: boolean;
          created_at: string;
        };
        Insert: {
          id?: string;
          facility_id: string;
          member_id: string;
          plan_id: string;
          status?: MembershipStatus;
          start_date: string;
          end_date: string;
          auto_renew?: boolean;
          created_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["memberships"]["Insert"]>;
        Relationships: [
          {
            foreignKeyName: "memberships_facility_id_fkey";
            columns: ["facility_id"];
            isOneToOne: false;
            referencedRelation: "facilities";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "memberships_member_id_fkey";
            columns: ["member_id"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "memberships_plan_id_fkey";
            columns: ["plan_id"];
            isOneToOne: false;
            referencedRelation: "membership_plans";
            referencedColumns: ["id"];
          },
        ];
      };
      payments: {
        Row: {
          id: string;
          facility_id: string;
          member_id: string;
          membership_id: string | null;
          razorpay_order_id: string | null;
          razorpay_payment_id: string | null;
          amount_inr: number;
          status: PaymentStatus;
          created_at: string;
        };
        Insert: {
          id?: string;
          facility_id: string;
          member_id: string;
          membership_id?: string | null;
          razorpay_order_id?: string | null;
          razorpay_payment_id?: string | null;
          amount_inr: number;
          status?: PaymentStatus;
          created_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["payments"]["Insert"]>;
        Relationships: [
          {
            foreignKeyName: "payments_facility_id_fkey";
            columns: ["facility_id"];
            isOneToOne: false;
            referencedRelation: "facilities";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "payments_member_id_fkey";
            columns: ["member_id"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "payments_membership_id_fkey";
            columns: ["membership_id"];
            isOneToOne: false;
            referencedRelation: "memberships";
            referencedColumns: ["id"];
          },
        ];
      };
      bookings: {
        Row: {
          id: string;
          facility_id: string;
          court_id: string;
          member_id: string;
          start_time: string;
          end_time: string;
          status: BookingStatus;
          created_by: string;
          created_at: string;
        };
        Insert: {
          id?: string;
          facility_id: string;
          court_id: string;
          member_id: string;
          start_time: string;
          end_time: string;
          status?: BookingStatus;
          created_by: string;
          created_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["bookings"]["Insert"]>;
        Relationships: [
          {
            foreignKeyName: "bookings_facility_id_fkey";
            columns: ["facility_id"];
            isOneToOne: false;
            referencedRelation: "facilities";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "bookings_court_id_fkey";
            columns: ["court_id"];
            isOneToOne: false;
            referencedRelation: "courts";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "bookings_member_id_fkey";
            columns: ["member_id"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      inventory_items: {
        Row: {
          id: string;
          facility_id: string;
          name: string;
          category: string;
          sku: string;
          total_quantity: number;
          available_quantity: number;
          condition: string;
          created_at: string;
        };
        Insert: {
          id?: string;
          facility_id: string;
          name: string;
          category: string;
          sku: string;
          total_quantity?: number;
          available_quantity?: number;
          condition?: string;
          created_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["inventory_items"]["Insert"]>;
        Relationships: [
          {
            foreignKeyName: "inventory_items_facility_id_fkey";
            columns: ["facility_id"];
            isOneToOne: false;
            referencedRelation: "facilities";
            referencedColumns: ["id"];
          },
        ];
      };
      inventory_transactions: {
        Row: {
          id: string;
          facility_id: string;
          item_id: string;
          member_id: string | null;
          quantity: number;
          type: InventoryTxnType;
          staff_id: string;
          created_at: string;
        };
        Insert: {
          id?: string;
          facility_id: string;
          item_id: string;
          member_id?: string | null;
          quantity: number;
          type: InventoryTxnType;
          staff_id: string;
          created_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["inventory_transactions"]["Insert"]>;
        Relationships: [
          {
            foreignKeyName: "inventory_transactions_facility_id_fkey";
            columns: ["facility_id"];
            isOneToOne: false;
            referencedRelation: "facilities";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "inventory_transactions_item_id_fkey";
            columns: ["item_id"];
            isOneToOne: false;
            referencedRelation: "inventory_items";
            referencedColumns: ["id"];
          },
        ];
      };
    };
    Views: Record<string, never>;
    Functions: {
      role: {
        Args: Record<string, never>;
        Returns: Role;
      };
      is_facility_member: {
        Args: { target_facility: string };
        Returns: boolean;
      };
      has_facility_role: {
        Args: { target_facility: string; allowed: FacilityRole[] };
        Returns: boolean;
      };
    };
    Enums: {
      role: Role;
      facility_role: FacilityRole;
      membership_status: MembershipStatus;
      payment_status: PaymentStatus;
      booking_status: BookingStatus;
      inventory_txn_type: InventoryTxnType;
    };
    CompositeTypes: Record<string, never>;
  };
}