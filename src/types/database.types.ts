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
          onboarding_completed_at: string | null;
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
          onboarding_completed_at?: string | null;
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
          facility_sport_id: string | null;
          member_id: string | null;
          customer_type: "MEMBER" | "GUEST";
          guest_name: string | null;
          guest_phone: string | null;
          start_time: string;
          end_time: string;
          status: BookingStatus;
          amount_minor: number | null;
          currency: string;
          payment_status: "PENDING" | "PAID" | "REFUNDED";
          cancellation_reason: string | null;
          guest_player_id: string | null;
          notes: string | null;
          created_by: string;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          facility_id: string;
          court_id: string;
          facility_sport_id?: string | null;
          member_id?: string | null;
          customer_type?: "MEMBER" | "GUEST";
          guest_name?: string | null;
          guest_phone?: string | null;
          start_time: string;
          end_time: string;
          status?: BookingStatus;
          amount_minor?: number | null;
          currency?: string;
          payment_status?: "PENDING" | "PAID" | "REFUNDED";
          cancellation_reason?: string | null;
          guest_player_id?: string | null;
          notes?: string | null;
          created_by: string;
          created_at?: string;
          updated_at?: string;
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
      guest_players: {
        Row: {
          id: string;
          facility_id: string;
          name: string;
          phone: string | null;
          email: string | null;
          notes: string | null;
          status: "ACTIVE" | "INACTIVE";
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          facility_id: string;
          name: string;
          phone?: string | null;
          email?: string | null;
          notes?: string | null;
          status?: "ACTIVE" | "INACTIVE";
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["guest_players"]["Insert"]>;
        Relationships: [
          {
            foreignKeyName: "guest_players_facility_id_fkey";
            columns: ["facility_id"];
            isOneToOne: false;
            referencedRelation: "facilities";
            referencedColumns: ["id"];
          },
        ];
      };
      members: {
        Row: {
          id: string;
          facility_id: string;
          full_name: string;
          phone: string;
          email: string | null;
          date_of_birth: string | null;
          gender: string | null;
          notes: string | null;
          status: "ACTIVE" | "INACTIVE";
          user_id: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          facility_id: string;
          full_name: string;
          phone: string;
          email?: string | null;
          date_of_birth?: string | null;
          gender?: string | null;
          notes?: string | null;
          status?: "ACTIVE" | "INACTIVE";
          user_id?: string | null;
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["members"]["Insert"]>;
        Relationships: [
          {
            foreignKeyName: "members_facility_id_fkey";
            columns: ["facility_id"];
            isOneToOne: false;
            referencedRelation: "facilities";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "members_user_id_fkey";
            columns: ["user_id"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      membership_batches: {
        Row: {
          id: string;
          facility_id: string;
          plan_id: string;
          facility_sport_id: string;
          court_id: string;
          name: string;
          days_of_week: number[];
          start_time: string;
          end_time: string;
          capacity: number;
          is_active: boolean;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          facility_id: string;
          plan_id: string;
          facility_sport_id: string;
          court_id: string;
          name: string;
          days_of_week: number[];
          start_time: string;
          end_time: string;
          capacity: number;
          is_active?: boolean;
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["membership_batches"]["Insert"]>;
        Relationships: [
          {
            foreignKeyName: "membership_batches_facility_id_fkey";
            columns: ["facility_id"];
            isOneToOne: false;
            referencedRelation: "facilities";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "membership_batches_court_id_fkey";
            columns: ["court_id"];
            isOneToOne: false;
            referencedRelation: "courts";
            referencedColumns: ["id"];
          },
        ];
      };
      membership_batch_members: {
        Row: {
          id: string;
          batch_id: string;
          member_id: string;
          membership_id: string | null;
          created_at: string;
        };
        Insert: {
          id?: string;
          batch_id: string;
          member_id: string;
          membership_id?: string | null;
          created_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["membership_batch_members"]["Insert"]>;
        Relationships: [
          {
            foreignKeyName: "membership_batch_members_batch_id_fkey";
            columns: ["batch_id"];
            isOneToOne: false;
            referencedRelation: "membership_batches";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "membership_batch_members_member_id_fkey";
            columns: ["member_id"];
            isOneToOne: false;
            referencedRelation: "members";
            referencedColumns: ["id"];
          },
        ];
      };
      membership_sessions: {
        Row: {
          id: string;
          batch_id: string;
          facility_id: string;
          court_id: string;
          facility_sport_id: string;
          session_date: string;
          start_time: string;
          end_time: string;
          capacity: number;
          released_capacity: number;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          batch_id: string;
          facility_id: string;
          court_id: string;
          facility_sport_id: string;
          session_date: string;
          start_time: string;
          end_time: string;
          capacity: number;
          released_capacity?: number;
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["membership_sessions"]["Insert"]>;
        Relationships: [
          {
            foreignKeyName: "membership_sessions_batch_id_fkey";
            columns: ["batch_id"];
            isOneToOne: false;
            referencedRelation: "membership_batches";
            referencedColumns: ["id"];
          },
        ];
      };
      membership_session_bookings: {
        Row: {
          id: string;
          session_id: string;
          facility_id: string;
          participant_type: "MEMBER" | "GUEST";
          member_id: string | null;
          guest_player_id: string | null;
          status: "CONFIRMED" | "CANCELLED";
          slot_source: "MEMBERSHIP" | "RELEASED";
          amount_minor: number | null;
          currency: string;
          created_by: string;
          created_at: string;
        };
        Insert: {
          id?: string;
          session_id: string;
          facility_id: string;
          participant_type: "MEMBER" | "GUEST";
          member_id?: string | null;
          guest_player_id?: string | null;
          status?: "CONFIRMED" | "CANCELLED";
          slot_source: "MEMBERSHIP" | "RELEASED";
          amount_minor?: number | null;
          currency?: string;
          created_by: string;
          created_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["membership_session_bookings"]["Insert"]>;
        Relationships: [
          {
            foreignKeyName: "membership_session_bookings_session_id_fkey";
            columns: ["session_id"];
            isOneToOne: false;
            referencedRelation: "membership_sessions";
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
      complete_facility_setup: {
        Args: { p_facility_id: string };
        Returns: Database["public"]["Tables"]["facilities"]["Row"];
      };
      create_booking: {
        Args: {
          p_facility_id: string;
          p_court_id: string;
          p_start_time: string;
          p_end_time: string;
          p_customer_type: "MEMBER" | "GUEST";
          p_member_id: string | null;
          p_guest_name: string | null;
          p_guest_phone: string | null;
          p_notes: string | null;
          p_payment_status?: "PENDING" | "PAID" | "REFUNDED";
          p_guest_player_id?: string | null;
        };
        Returns: Database["public"]["Tables"]["bookings"]["Row"];
      };
      find_or_create_guest: {
        Args: {
          p_facility_id: string;
          p_name: string;
          p_phone: string | null;
          p_email?: string | null;
          p_notes?: string | null;
        };
        Returns: Database["public"]["Tables"]["guest_players"]["Row"];
      };
      update_guest: {
        Args: {
          p_guest_id: string;
          p_name: string;
          p_phone: string | null;
          p_email: string | null;
          p_notes: string | null;
          p_status: "ACTIVE" | "INACTIVE" | null;
        };
        Returns: Database["public"]["Tables"]["guest_players"]["Row"];
      };
      get_guest_stats: {
        Args: { p_guest_id: string };
        Returns: {
          total_visits: number;
          total_bookings: number;
          last_visit: string | null;
          total_amount_minor: number;
          pending_amount_minor: number;
          sports: { sportId: string; sportName: string }[];
        }[];
      };
      create_membership: {
        Args: {
          p_member_id: string;
          p_facility_id: string;
          p_plan_id: string;
          p_start_date: string;
          p_payment_status?: PaymentStatus;
        };
        Returns: Database["public"]["Tables"]["memberships"]["Row"];
      };
      cancel_membership: {
        Args: { p_membership_id: string };
        Returns: Database["public"]["Tables"]["memberships"]["Row"];
      };
      search_facility_members: {
        Args: {
          p_facility_id: string;
          p_query?: string | null;
          p_limit?: number;
          p_offset?: number;
        };
        Returns: {
          member_id: string;
          full_name: string;
          phone: string;
          email: string | null;
          membership_id: string | null;
          plan_id: string | null;
          plan_name: string | null;
          start_date: string | null;
          end_date: string | null;
          status: MembershipStatus | null;
        }[];
      };
      get_member_stats: {
        Args: { p_member_id: string; p_facility_id: string };
        Returns: {
          total_visits: number;
          total_bookings: number;
          last_visit: string | null;
          total_amount_minor: number;
          pending_amount_minor: number;
          sports: { sportId: string; sportName: string }[];
        }[];
      };
      create_member: {
        Args: {
          p_facility_id: string;
          p_full_name: string;
          p_phone: string;
          p_email?: string | null;
          p_date_of_birth?: string | null;
          p_gender?: string | null;
          p_notes?: string | null;
        };
        Returns: Database["public"]["Tables"]["members"]["Row"];
      };
      update_member: {
        Args: {
          p_member_id: string;
          p_full_name: string;
          p_phone: string;
          p_email: string | null;
          p_date_of_birth: string | null;
          p_gender: string | null;
          p_notes: string | null;
          p_status?: "ACTIVE" | "INACTIVE" | null;
        };
        Returns: Database["public"]["Tables"]["members"]["Row"];
      };
      search_members: {
        Args: { p_facility_id: string; p_query: string };
        Returns: {
          id: string;
          full_name: string;
          phone: string;
          email: string | null;
        }[];
      };
      reschedule_booking: {
        Args: {
          p_booking_id: string;
          p_new_court_id: string;
          p_new_start_time: string;
          p_new_end_time: string;
        };
        Returns: Database["public"]["Tables"]["bookings"]["Row"];
      };
      create_membership_batch: {
        Args: {
          p_facility_id: string;
          p_plan_id: string;
          p_facility_sport_id: string;
          p_court_id: string;
          p_name: string;
          p_days_of_week: number[];
          p_start_time: string;
          p_end_time: string;
          p_capacity: number;
        };
        Returns: Database["public"]["Tables"]["membership_batches"]["Row"];
      };
      update_membership_batch: {
        Args: {
          p_batch_id: string;
          p_name: string;
          p_court_id: string;
          p_days_of_week: number[];
          p_start_time: string;
          p_end_time: string;
          p_capacity: number;
          p_is_active?: boolean | null;
        };
        Returns: Database["public"]["Tables"]["membership_batches"]["Row"];
      };
      assign_batch_member: {
        Args: { p_batch_id: string; p_member_id: string; p_membership_id?: string | null };
        Returns: Database["public"]["Tables"]["membership_batch_members"]["Row"];
      };
      remove_batch_member: {
        Args: { p_batch_id: string; p_member_id: string };
        Returns: undefined;
      };
      get_or_create_membership_session: {
        Args: { p_batch_id: string; p_session_date: string };
        Returns: Database["public"]["Tables"]["membership_sessions"]["Row"];
      };
      get_membership_session_capacity: {
        Args: { p_session_id: string };
        Returns: {
          capacity: number;
          released_capacity: number;
          member_booked_count: number;
          guest_booked_count: number;
          unused_capacity: number;
          guest_available_capacity: number;
        }[];
      };
      book_membership_slot: {
        Args: { p_batch_id: string; p_session_date: string; p_member_id: string };
        Returns: Database["public"]["Tables"]["membership_session_bookings"]["Row"];
      };
      release_membership_capacity: {
        Args: { p_session_id: string; p_count: number };
        Returns: Database["public"]["Tables"]["membership_sessions"]["Row"];
      };
      restore_membership_capacity: {
        Args: { p_session_id: string; p_count: number };
        Returns: Database["public"]["Tables"]["membership_sessions"]["Row"];
      };
      book_guest_slot: {
        Args: { p_batch_id: string; p_session_date: string; p_guest_player_id: string };
        Returns: Database["public"]["Tables"]["membership_session_bookings"]["Row"];
      };
      cancel_membership_slot_booking: {
        Args: { p_booking_id: string };
        Returns: Database["public"]["Tables"]["membership_session_bookings"]["Row"];
      };
      list_membership_sessions_for_date: {
        Args: { p_facility_id: string; p_date: string };
        Returns: {
          batch_id: string;
          session_id: string | null;
          batch_name: string;
          court_id: string;
          court_name: string;
          facility_sport_id: string;
          sport_name: string;
          session_date: string;
          start_time: string;
          end_time: string;
          capacity: number;
          released_capacity: number;
          member_booked_count: number;
          guest_booked_count: number;
        }[];
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