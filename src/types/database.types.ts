/**
 * Hand-written to match supabase/migrations/0001_init.sql.
 * Regenerate with `supabase gen types typescript --linked` once the project is linked,
 * and diff against this file to catch drift.
 */

export type Role = "admin" | "staff" | "member";
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
          avatar_url: string | null;
          role: Role;
          phone: string | null;
          created_at: string;
        };
        Insert: {
          id: string;
          full_name: string;
          avatar_url?: string | null;
          role?: Role;
          phone?: string | null;
          created_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["profiles"]["Insert"]>;
        Relationships: [];
      };
      membership_plans: {
        Row: {
          id: string;
          name: string;
          price_inr: number;
          duration_days: number;
          features: string[];
          is_active: boolean;
          created_at: string;
        };
        Insert: {
          id?: string;
          name: string;
          price_inr: number;
          duration_days: number;
          features?: string[];
          is_active?: boolean;
          created_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["membership_plans"]["Insert"]>;
        Relationships: [];
      };
      memberships: {
        Row: {
          id: string;
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
      stations: {
        Row: {
          id: string;
          name: string;
          type: string;
          hourly_rate_inr: number;
          is_active: boolean;
          created_at: string;
        };
        Insert: {
          id?: string;
          name: string;
          type: string;
          hourly_rate_inr: number;
          is_active?: boolean;
          created_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["stations"]["Insert"]>;
        Relationships: [];
      };
      bookings: {
        Row: {
          id: string;
          member_id: string;
          station_id: string;
          start_time: string;
          end_time: string;
          status: BookingStatus;
          created_by: string;
          created_at: string;
        };
        Insert: {
          id?: string;
          member_id: string;
          station_id: string;
          start_time: string;
          end_time: string;
          status?: BookingStatus;
          created_by: string;
          created_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["bookings"]["Insert"]>;
        Relationships: [
          {
            foreignKeyName: "bookings_member_id_fkey";
            columns: ["member_id"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "bookings_station_id_fkey";
            columns: ["station_id"];
            isOneToOne: false;
            referencedRelation: "stations";
            referencedColumns: ["id"];
          },
        ];
      };
      inventory_items: {
        Row: {
          id: string;
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
          name: string;
          category: string;
          sku: string;
          total_quantity: number;
          available_quantity: number;
          condition?: string;
          created_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["inventory_items"]["Insert"]>;
        Relationships: [];
      };
      inventory_transactions: {
        Row: {
          id: string;
          item_id: string;
          member_id: string | null;
          quantity: number;
          type: InventoryTxnType;
          staff_id: string;
          created_at: string;
        };
        Insert: {
          id?: string;
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
    Functions: Record<string, never>;
    Enums: {
      role: Role;
      membership_status: MembershipStatus;
      payment_status: PaymentStatus;
      booking_status: BookingStatus;
      inventory_txn_type: InventoryTxnType;
    };
    CompositeTypes: Record<string, never>;
  };
}