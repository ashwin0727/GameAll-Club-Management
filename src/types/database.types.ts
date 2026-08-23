/**
 * Hand-written to match supabase/migrations/0001_init.sql and 0002_onboarding_backend.sql.
 * Regenerate with `supabase gen types typescript --linked` once the project is linked,
 * and diff against this file to catch drift.
 */

export type Role = "admin" | "staff" | "member";
export type FacilityRole = "owner" | "manager" | "staff";
export type MembershipStatus = "active" | "expired" | "cancelled" | "pending";
export type PaymentStatus = "created" | "paid" | "failed" | "refunded";
export type BookingStatus = "pending" | "confirmed" | "cancelled" | "completed";
export type InventoryTxnType = "checkout" | "return" | "restock" | "damage";
export type DbFacilityType =
  | "BADMINTON"
  | "PICKLEBALL"
  | "CRICKET"
  | "FOOTBALL"
  | "TENNIS"
  | "MULTI_SPORT"
  | "OTHER";
export type DbEntityStatus = "ACTIVE" | "INACTIVE";
export type DbOnboardingStep =
  | "FACILITY_DETAILS"
  | "SPORTS"
  | "COURTS"
  | "OPERATING_HOURS"
  | "PRICING"
  | "COMPLETED";
export type DbAreaType = "INDOOR" | "OUTDOOR";

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
          facility_type: DbFacilityType;
          custom_facility_type: string | null;
          business_email: string;
          business_phone: string;
          address_line_1: string;
          address_line_2: string | null;
          area: string;
          state: string;
          country: string;
          postal_code: string;
          latitude: number | null;
          longitude: number | null;
          logo_url: string | null;
          description: string | null;
          status: DbEntityStatus;
          onboarding_step: DbOnboardingStep;
          updated_at: string;
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
          facility_type: DbFacilityType;
          custom_facility_type?: string | null;
          business_email: string;
          business_phone: string;
          address_line_1: string;
          address_line_2?: string | null;
          area: string;
          state: string;
          country?: string;
          postal_code: string;
          latitude?: number | null;
          longitude?: number | null;
          logo_url?: string | null;
          description?: string | null;
          status?: DbEntityStatus;
          onboarding_step?: DbOnboardingStep;
          updated_at?: string;
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
          category: string | null;
          default_playing_area_label: string | null;
          updated_at: string;
        };
        Insert: {
          id?: string;
          key: string;
          name: string;
          is_active?: boolean;
          sort_order?: number;
          category?: string | null;
          default_playing_area_label?: string | null;
          updated_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["sports"]["Insert"]>;
        Relationships: [];
      };
      facility_sports: {
        Row: {
          id: string;
          facility_id: string;
          sport_id: string;
          is_active: boolean;
          custom_sport_name: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          facility_id: string;
          sport_id: string;
          is_active?: boolean;
          custom_sport_name?: string | null;
          created_at?: string;
          updated_at?: string;
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
          facility_sport_id: string;
          sport_id: string;
          name: string;
          surface: string | null;
          hourly_rate_inr: number;
          area_type: DbAreaType;
          status: DbEntityStatus;
          booking_enabled: boolean;
          archived: boolean;
          display_order: number;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          facility_id: string;
          facility_sport_id: string;
          sport_id: string;
          name: string;
          surface?: string | null;
          hourly_rate_inr?: number;
          area_type?: DbAreaType;
          status?: DbEntityStatus;
          booking_enabled?: boolean;
          archived?: boolean;
          display_order?: number;
          created_at?: string;
          updated_at?: string;
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
            foreignKeyName: "courts_facility_sport_id_fkey";
            columns: ["facility_sport_id"];
            isOneToOne: false;
            referencedRelation: "facility_sports";
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
      operating_schedules: {
        Row: {
          id: string;
          facility_id: string;
          scope_type: "FACILITY" | "PLAYING_AREA";
          playing_area_id: string | null;
          timezone: string;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          facility_id: string;
          scope_type: "FACILITY" | "PLAYING_AREA";
          playing_area_id?: string | null;
          timezone?: string;
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["operating_schedules"]["Insert"]>;
        Relationships: [
          {
            foreignKeyName: "operating_schedules_facility_id_fkey";
            columns: ["facility_id"];
            isOneToOne: false;
            referencedRelation: "facilities";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "operating_schedules_playing_area_id_fkey";
            columns: ["playing_area_id"];
            isOneToOne: false;
            referencedRelation: "courts";
            referencedColumns: ["id"];
          },
        ];
      };
      operating_days: {
        Row: {
          id: string;
          schedule_id: string;
          facility_id: string;
          day_of_week: number;
          is_closed: boolean;
          is_24_hours: boolean;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          schedule_id: string;
          facility_id: string;
          day_of_week: number;
          is_closed?: boolean;
          is_24_hours?: boolean;
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["operating_days"]["Insert"]>;
        Relationships: [
          {
            foreignKeyName: "operating_days_schedule_id_fkey";
            columns: ["schedule_id"];
            isOneToOne: false;
            referencedRelation: "operating_schedules";
            referencedColumns: ["id"];
          },
        ];
      };
      operating_time_slots: {
        Row: {
          id: string;
          operating_day_id: string;
          facility_id: string;
          start_time: string;
          end_time: string;
          crosses_midnight: boolean;
          display_order: number;
          created_at: string;
        };
        Insert: {
          id?: string;
          operating_day_id: string;
          facility_id: string;
          start_time: string;
          end_time: string;
          crosses_midnight?: boolean;
          display_order?: number;
          created_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["operating_time_slots"]["Insert"]>;
        Relationships: [
          {
            foreignKeyName: "operating_time_slots_operating_day_id_fkey";
            columns: ["operating_day_id"];
            isOneToOne: false;
            referencedRelation: "operating_days";
            referencedColumns: ["id"];
          },
        ];
      };
      pricing_plans: {
        Row: {
          id: string;
          facility_id: string;
          name: string;
          currency: string;
          status: "ACTIVE" | "INACTIVE";
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          facility_id: string;
          name?: string;
          currency?: string;
          status?: "ACTIVE" | "INACTIVE";
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["pricing_plans"]["Insert"]>;
        Relationships: [
          {
            foreignKeyName: "pricing_plans_facility_id_fkey";
            columns: ["facility_id"];
            isOneToOne: false;
            referencedRelation: "facilities";
            referencedColumns: ["id"];
          },
        ];
      };
      pricing_rules: {
        Row: {
          id: string;
          pricing_plan_id: string;
          facility_id: string;
          facility_sport_id: string;
          playing_area_id: string | null;
          day_type: "ALL_DAYS" | "WEEKDAYS" | "WEEKENDS";
          covers_full_day: boolean;
          start_time: string | null;
          end_time: string | null;
          amount_minor: number;
          currency: string;
          pricing_unit: "PER_HOUR" | "PER_30_MINUTES" | "PER_SESSION" | "PER_MATCH";
          priority: number;
          is_active: boolean;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          pricing_plan_id: string;
          facility_id: string;
          facility_sport_id: string;
          playing_area_id?: string | null;
          day_type?: "ALL_DAYS" | "WEEKDAYS" | "WEEKENDS";
          covers_full_day?: boolean;
          start_time?: string | null;
          end_time?: string | null;
          amount_minor: number;
          currency?: string;
          pricing_unit?: "PER_HOUR" | "PER_30_MINUTES" | "PER_SESSION" | "PER_MATCH";
          priority?: number;
          is_active?: boolean;
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["pricing_rules"]["Insert"]>;
        Relationships: [
          {
            foreignKeyName: "pricing_rules_pricing_plan_id_fkey";
            columns: ["pricing_plan_id"];
            isOneToOne: false;
            referencedRelation: "pricing_plans";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "pricing_rules_facility_sport_id_fkey";
            columns: ["facility_sport_id"];
            isOneToOne: false;
            referencedRelation: "facility_sports";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "pricing_rules_playing_area_id_fkey";
            columns: ["playing_area_id"];
            isOneToOne: false;
            referencedRelation: "courts";
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
      create_facility_with_owner: {
        Args: {
          p_name: string;
          p_facility_type: DbFacilityType;
          p_custom_facility_type: string | null;
          p_business_email: string;
          p_business_phone: string;
          p_address_line_1: string;
          p_address_line_2: string | null;
          p_area: string;
          p_city: string;
          p_state: string;
          p_country: string;
          p_postal_code: string;
          p_latitude: number | null;
          p_longitude: number | null;
          p_timezone: string;
          p_logo_url: string | null;
          p_description: string | null;
        };
        Returns: Database["public"]["Tables"]["facilities"]["Row"];
      };
      sync_facility_sports: {
        Args: {
          p_facility_id: string;
          p_sport_ids: string[];
          p_custom_sport_name?: string | null;
        };
        Returns: Database["public"]["Tables"]["facility_sports"]["Row"][];
      };
      save_operating_schedule: {
        Args: {
          p_facility_id: string;
          p_scope_type: "FACILITY" | "PLAYING_AREA";
          p_playing_area_id: string | null;
          p_days: unknown;
        };
        Returns: Database["public"]["Tables"]["operating_schedules"]["Row"];
      };
      delete_playing_area_override: {
        Args: { p_playing_area_id: string };
        Returns: void;
      };
      save_pricing_rules: {
        Args: { p_facility_id: string; p_plan_name: string; p_rules: unknown };
        Returns: Database["public"]["Tables"]["pricing_plans"]["Row"];
      };
    };
    Enums: {
      role: Role;
      facility_role: FacilityRole;
      membership_status: MembershipStatus;
      payment_status: PaymentStatus;
      booking_status: BookingStatus;
      inventory_txn_type: InventoryTxnType;
      facility_type: DbFacilityType;
      entity_status: DbEntityStatus;
      onboarding_step: DbOnboardingStep;
      area_type: DbAreaType;
    };
    CompositeTypes: Record<string, never>;
  };
}