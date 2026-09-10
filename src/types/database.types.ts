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
export type MembershipSubscriptionStatus =
  | "created"
  | "authenticated"
  | "active"
  | "pending"
  | "halted"
  | "cancelled"
  | "completed";
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
          must_reset_password: boolean;
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
          must_reset_password?: boolean;
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
          membership_access_days: number[];
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
          membership_access_days?: number[];
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
          id: string;
          facility_id: string;
          user_id: string;
          role: FacilityRole;
          role_id: string | null;
          status: "ACTIVE" | "INACTIVE" | "INVITED";
          is_primary: boolean;
          title: string | null;
          notes: string | null;
          invited_by: string | null;
          invited_at: string | null;
          activated_at: string | null;
          last_login_at: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          facility_id: string;
          user_id: string;
          role?: FacilityRole;
          role_id?: string | null;
          status?: "ACTIVE" | "INACTIVE" | "INVITED";
          is_primary?: boolean;
          title?: string | null;
          notes?: string | null;
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
      permissions: {
        Row: {
          key: string;
          module: string;
          action: string;
          label: string;
          description: string | null;
          is_dangerous: boolean;
          sort_order: number;
        };
        Insert: {
          key: string;
          module: string;
          action: string;
          label: string;
          description?: string | null;
          is_dangerous?: boolean;
          sort_order?: number;
        };
        Update: Partial<Database["public"]["Tables"]["permissions"]["Insert"]>;
        Relationships: [];
      };
      roles: {
        Row: {
          id: string;
          facility_id: string | null;
          key: string | null;
          base_role: FacilityRole | null;
          name: string;
          description: string | null;
          is_system: boolean;
          is_template: boolean;
          is_active: boolean;
          version: number;
          created_by: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          facility_id?: string | null;
          key?: string | null;
          base_role?: FacilityRole | null;
          name: string;
          description?: string | null;
          is_system?: boolean;
          is_template?: boolean;
          is_active?: boolean;
        };
        Update: Partial<Database["public"]["Tables"]["roles"]["Insert"]>;
        Relationships: [];
      };
      role_permissions: {
        Row: { role_id: string; permission_key: string };
        Insert: { role_id: string; permission_key: string };
        Update: Partial<Database["public"]["Tables"]["role_permissions"]["Insert"]>;
        Relationships: [];
      };
      security_events: {
        Row: {
          id: string;
          facility_id: string;
          event: string;
          actor: string | null;
          target_user_id: string | null;
          target_role_id: string | null;
          summary: string;
          detail: Record<string, unknown>;
          created_at: string;
        };
        Insert: {
          facility_id: string;
          event: string;
          actor?: string | null;
          target_user_id?: string | null;
          target_role_id?: string | null;
          summary: string;
          detail?: Record<string, unknown>;
        };
        Update: Partial<Database["public"]["Tables"]["security_events"]["Insert"]>;
        Relationships: [];
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
          plan_id: string | null;
          status: MembershipStatus;
          start_date: string;
          end_date: string;
          auto_renew: boolean;
          created_by: string | null;
          monthly_price_inr: number | null;
          name: string | null;
          membership_type: "INDIVIDUAL" | "FAMILY" | "CORPORATE";
          max_family_members: number;
          duration_days: number | null;
          time_slot_start: string | null;
          time_slot_end: string | null;
          description: string | null;
          membership_fee_inr: number | null;
          registration_fee_inr: number;
          gst_percent: number;
          total_amount_inr: number | null;
          payment_reference: string | null;
          referral_member_id: string | null;
          discovery_source: string | null;
          notes: string | null;
          created_at: string;
        };
        Insert: {
          id?: string;
          facility_id: string;
          member_id: string;
          plan_id?: string | null;
          status?: MembershipStatus;
          start_date: string;
          end_date: string;
          auto_renew?: boolean;
          created_by?: string | null;
          monthly_price_inr?: number | null;
          name?: string | null;
          membership_type?: "INDIVIDUAL" | "FAMILY" | "CORPORATE";
          max_family_members?: number;
          duration_days?: number | null;
          time_slot_start?: string | null;
          time_slot_end?: string | null;
          description?: string | null;
          membership_fee_inr?: number | null;
          registration_fee_inr?: number;
          gst_percent?: number;
          total_amount_inr?: number | null;
          payment_reference?: string | null;
          referral_member_id?: string | null;
          discovery_source?: string | null;
          notes?: string | null;
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
      membership_subscriptions: {
        Row: {
          id: string;
          membership_id: string;
          facility_id: string;
          member_id: string;
          razorpay_plan_id: string;
          razorpay_subscription_id: string;
          razorpay_customer_id: string | null;
          status: MembershipSubscriptionStatus;
          amount_inr: number;
          short_url: string | null;
          charge_count: number;
          current_start: string | null;
          current_end: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          membership_id: string;
          facility_id: string;
          member_id: string;
          razorpay_plan_id: string;
          razorpay_subscription_id: string;
          razorpay_customer_id?: string | null;
          status?: MembershipSubscriptionStatus;
          amount_inr: number;
          short_url?: string | null;
          charge_count?: number;
          current_start?: string | null;
          current_end?: string | null;
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["membership_subscriptions"]["Insert"]>;
        Relationships: [
          {
            foreignKeyName: "membership_subscriptions_membership_id_fkey";
            columns: ["membership_id"];
            isOneToOne: true;
            referencedRelation: "memberships";
            referencedColumns: ["id"];
          },
        ];
      };
      payments: {
        Row: {
          id: string;
          facility_id: string;
          member_id: string | null;
          membership_id: string | null;
          payment_order_id: string | null;
          booking_id: string | null;
          guest_player_id: string | null;
          razorpay_order_id: string | null;
          razorpay_payment_id: string | null;
          amount_inr: number;
          status: PaymentStatus;
          payment_method: string | null;
          paid_at: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          facility_id: string;
          member_id?: string | null;
          membership_id?: string | null;
          payment_order_id?: string | null;
          booking_id?: string | null;
          guest_player_id?: string | null;
          razorpay_order_id?: string | null;
          razorpay_payment_id?: string | null;
          amount_inr: number;
          status?: PaymentStatus;
          payment_method?: string | null;
          paid_at?: string | null;
          created_at?: string;
          updated_at?: string;
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
            referencedRelation: "members";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "payments_membership_id_fkey";
            columns: ["membership_id"];
            isOneToOne: false;
            referencedRelation: "memberships";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "payments_payment_order_id_fkey";
            columns: ["payment_order_id"];
            isOneToOne: false;
            referencedRelation: "payment_orders";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "payments_booking_id_fkey";
            columns: ["booking_id"];
            isOneToOne: false;
            referencedRelation: "bookings";
            referencedColumns: ["id"];
          },
        ];
      };
      payment_orders: {
        Row: {
          id: string;
          facility_id: string;
          source_type: "MEMBERSHIP" | "MEMBER_BOOKING" | "GUEST_BOOKING";
          booking_id: string | null;
          membership_session_booking_id: string | null;
          member_id: string | null;
          plan_id: string | null;
          amount_minor: number;
          currency: string;
          status:
            | "CREATED"
            | "ORDER_CREATED"
            | "PAYMENT_ATTEMPTED"
            | "PAYMENT_VERIFICATION_PENDING"
            | "PAYMENT_VERIFIED"
            | "AUTHORIZED"
            | "CAPTURED"
            | "COMPLETED"
            | "SETTLEMENT_EXCEPTION"
            | "FAILED"
            | "CANCELLED"
            | "REFUND_REQUESTED"
            | "PARTIALLY_REFUNDED"
            | "REFUNDED";
          razorpay_order_id: string | null;
          razorpay_payment_id: string | null;
          razorpay_signature: string | null;
          receipt: string;
          expires_at: string;
          created_by: string;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          facility_id: string;
          source_type: "MEMBERSHIP" | "MEMBER_BOOKING" | "GUEST_BOOKING";
          booking_id?: string | null;
          membership_session_booking_id?: string | null;
          member_id?: string | null;
          plan_id?: string | null;
          amount_minor: number;
          currency?: string;
          status?:
            | "CREATED"
            | "ORDER_CREATED"
            | "PAYMENT_ATTEMPTED"
            | "AUTHORIZED"
            | "CAPTURED"
            | "COMPLETED"
            | "SETTLEMENT_EXCEPTION"
            | "FAILED"
            | "CANCELLED"
            | "REFUND_REQUESTED"
            | "PARTIALLY_REFUNDED"
            | "REFUNDED";
          razorpay_order_id?: string | null;
          razorpay_payment_id?: string | null;
          razorpay_signature?: string | null;
          receipt: string;
          expires_at: string;
          created_by: string;
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["payment_orders"]["Insert"]>;
        Relationships: [
          {
            foreignKeyName: "payment_orders_facility_id_fkey";
            columns: ["facility_id"];
            isOneToOne: false;
            referencedRelation: "facilities";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "payment_orders_booking_id_fkey";
            columns: ["booking_id"];
            isOneToOne: false;
            referencedRelation: "bookings";
            referencedColumns: ["id"];
          },
        ];
      };
      razorpay_webhook_events: {
        Row: {
          id: string;
          event_id: string;
          event_type: string;
          payload: Record<string, unknown>;
          processed: boolean;
          processed_at: string | null;
          error: string | null;
          created_at: string;
        };
        Insert: {
          id?: string;
          event_id: string;
          event_type: string;
          payload: Record<string, unknown>;
          processed?: boolean;
          processed_at?: string | null;
          error?: string | null;
          created_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["razorpay_webhook_events"]["Insert"]>;
        Relationships: [];
      };
      settlement_exceptions: {
        Row: {
          id: string;
          facility_id: string;
          payment_order_id: string;
          transaction_id: string | null;
          source_type: "MEMBERSHIP" | "MEMBER_BOOKING" | "GUEST_BOOKING";
          source_id: string | null;
          reason: "BOOKING_NO_LONGER_AVAILABLE" | "GUEST_CAPACITY_EXHAUSTED" | "MEMBERSHIP_INVALID" | "BUSINESS_VALIDATION_FAILED" | "DATABASE_SETTLEMENT_FAILURE";
          status: "OPEN" | "RESOLVED";
          created_at: string;
          resolved_at: string | null;
        };
        Insert: {
          id?: string;
          facility_id: string;
          payment_order_id: string;
          transaction_id?: string | null;
          source_type: "MEMBERSHIP" | "MEMBER_BOOKING" | "GUEST_BOOKING";
          source_id?: string | null;
          reason: "BOOKING_NO_LONGER_AVAILABLE" | "GUEST_CAPACITY_EXHAUSTED" | "MEMBERSHIP_INVALID" | "BUSINESS_VALIDATION_FAILED" | "DATABASE_SETTLEMENT_FAILURE";
          status?: "OPEN" | "RESOLVED";
          created_at?: string;
          resolved_at?: string | null;
        };
        Update: Partial<Database["public"]["Tables"]["settlement_exceptions"]["Insert"]>;
        Relationships: [
          {
            foreignKeyName: "settlement_exceptions_payment_order_id_fkey";
            columns: ["payment_order_id"];
            isOneToOne: false;
            referencedRelation: "payment_orders";
            referencedColumns: ["id"];
          },
        ];
      };
      refunds: {
        Row: {
          id: string;
          facility_id: string;
          payment_order_id: string;
          transaction_id: string | null;
          source_type: "MEMBERSHIP" | "MEMBER_BOOKING" | "GUEST_BOOKING";
          source_id: string | null;
          razorpay_payment_id: string;
          razorpay_refund_id: string | null;
          amount_minor: number;
          currency: string;
          reason: "CUSTOMER_CANCELLATION" | "FACILITY_CANCELLATION" | "COURT_UNAVAILABLE" | "SETTLEMENT_EXCEPTION" | "DUPLICATE_PAYMENT" | "OWNER_OVERRIDE" | "OTHER";
          status: "REQUESTED" | "PROCESSING" | "PENDING" | "PROCESSED" | "FAILED" | "CANCELLED";
          is_override: boolean;
          override_reason: string | null;
          policy_percent_applied: number | null;
          failure_reason: string | null;
          initiated_by: string | null;
          created_at: string;
          updated_at: string;
          processed_at: string | null;
        };
        Insert: {
          id?: string;
          facility_id: string;
          payment_order_id: string;
          transaction_id?: string | null;
          source_type: "MEMBERSHIP" | "MEMBER_BOOKING" | "GUEST_BOOKING";
          source_id?: string | null;
          razorpay_payment_id: string;
          razorpay_refund_id?: string | null;
          amount_minor: number;
          currency?: string;
          reason: "CUSTOMER_CANCELLATION" | "FACILITY_CANCELLATION" | "COURT_UNAVAILABLE" | "SETTLEMENT_EXCEPTION" | "DUPLICATE_PAYMENT" | "OWNER_OVERRIDE" | "OTHER";
          status?: "REQUESTED" | "PROCESSING" | "PENDING" | "PROCESSED" | "FAILED" | "CANCELLED";
          is_override?: boolean;
          override_reason?: string | null;
          policy_percent_applied?: number | null;
          failure_reason?: string | null;
          initiated_by?: string | null;
          created_at?: string;
          updated_at?: string;
          processed_at?: string | null;
        };
        Update: Partial<Database["public"]["Tables"]["refunds"]["Insert"]>;
        Relationships: [
          {
            foreignKeyName: "refunds_payment_order_id_fkey";
            columns: ["payment_order_id"];
            isOneToOne: false;
            referencedRelation: "payment_orders";
            referencedColumns: ["id"];
          },
        ];
      };
      cancellation_policies: {
        Row: {
          id: string;
          facility_id: string;
          full_refund_hours: number;
          full_refund_percent: number;
          partial_refund_hours: number;
          partial_refund_percent: number;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          facility_id: string;
          full_refund_hours?: number;
          full_refund_percent?: number;
          partial_refund_hours?: number;
          partial_refund_percent?: number;
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["cancellation_policies"]["Insert"]>;
        Relationships: [];
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
          party_size: number;
          payment_method: string | null;
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
          party_size?: number;
          payment_method?: string | null;
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
          address: string | null;
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
          address?: string | null;
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
          plan_id: string | null;
          facility_sport_id: string;
          court_id: string;
          name: string;
          days_of_week: number[];
          start_time: string;
          end_time: string;
          capacity: number;
          is_active: boolean;
          notes: string | null;
          created_by: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          facility_id: string;
          plan_id?: string | null;
          facility_sport_id: string;
          court_id: string;
          name: string;
          days_of_week: number[];
          start_time: string;
          end_time: string;
          capacity: number;
          is_active?: boolean;
          notes?: string | null;
          created_by?: string | null;
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
          category_id: string | null;
          brand: string | null;
          description: string | null;
          unit: string;
          reorder_level: number;
          default_unit_cost_minor: number | null;
          unit_cost_minor: number;
          preferred_vendor_id: string | null;
          image_path: string | null;
          status: "ACTIVE" | "INACTIVE";
          current_stock: number;
          created_by: string | null;
          updated_by: string | null;
          updated_at: string | null;
        };
        Insert: {
          id?: string;
          facility_id: string;
          name: string;
          category?: string;
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
      inventory_categories: {
        Row: {
          id: string;
          facility_id: string;
          name: string;
          description: string | null;
          is_active: boolean;
          sort_order: number;
          created_by: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: { facility_id: string; name: string };
        Update: Partial<Database["public"]["Tables"]["inventory_categories"]["Insert"]>;
        Relationships: [];
      };
      vendors: {
        Row: {
          id: string;
          facility_id: string;
          name: string;
          contact_person: string | null;
          phone: string | null;
          email: string | null;
          address: string | null;
          gst_number: string | null;
          pan_number: string | null;
          notes: string | null;
          status: "ACTIVE" | "INACTIVE";
          created_by: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: { facility_id: string; name: string };
        Update: Partial<Database["public"]["Tables"]["vendors"]["Insert"]>;
        Relationships: [];
      };
      inventory_movements: {
        Row: {
          id: string;
          facility_id: string;
          item_id: string;
          movement_type: "STOCK_IN" | "STOCK_OUT" | "ADJUSTMENT" | "PURCHASE_RECEIVED" | "RETURN";
          quantity: number;
          balance_after: number;
          unit_cost_minor: number | null;
          reason: string | null;
          notes: string | null;
          reference_type: string | null;
          reference_id: string | null;
          performed_by: string | null;
          created_at: string;
        };
        Insert: {
          facility_id: string;
          item_id: string;
          movement_type: string;
          quantity: number;
          balance_after: number;
        };
        Update: Partial<Database["public"]["Tables"]["inventory_movements"]["Insert"]>;
        Relationships: [];
      };
      inventory_events: {
        Row: {
          id: string;
          facility_id: string;
          event: string;
          actor: string | null;
          item_id: string | null;
          vendor_id: string | null;
          purchase_order_id: string | null;
          summary: string;
          detail: Record<string, unknown> | null;
          created_at: string;
        };
        Insert: { facility_id: string; event: string; summary: string };
        Update: Partial<Database["public"]["Tables"]["inventory_events"]["Insert"]>;
        Relationships: [];
      };
      purchase_orders: {
        Row: {
          id: string;
          facility_id: string;
          vendor_id: string;
          po_number: string;
          order_date: string;
          expected_delivery: string | null;
          status: "DRAFT" | "ORDERED" | "PARTIALLY_RECEIVED" | "RECEIVED" | "CANCELLED";
          subtotal_minor: number;
          tax_minor: number;
          discount_minor: number;
          total_minor: number;
          reference: string | null;
          notes: string | null;
          invoice_path: string | null;
          expense_id: string | null;
          created_by: string | null;
          created_at: string;
          updated_at: string;
          cancelled_at: string | null;
          cancel_reason: string | null;
        };
        Insert: { facility_id: string; vendor_id: string; po_number: string };
        Update: Partial<Database["public"]["Tables"]["purchase_orders"]["Insert"]>;
        Relationships: [];
      };
      purchase_order_items: {
        Row: {
          id: string;
          purchase_order_id: string;
          item_id: string;
          quantity_ordered: number;
          quantity_received: number;
          unit_cost_minor: number;
          tax_minor: number;
          discount_minor: number;
          line_total_minor: number;
        };
        Insert: {
          purchase_order_id: string;
          item_id: string;
          quantity_ordered: number;
          unit_cost_minor: number;
          line_total_minor: number;
        };
        Update: Partial<Database["public"]["Tables"]["purchase_order_items"]["Insert"]>;
        Relationships: [];
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
      expense_categories: {
        Row: {
          id: string;
          facility_id: string | null;
          name: string;
          is_active: boolean;
          sort_order: number;
          created_at: string;
        };
        Insert: {
          id?: string;
          facility_id?: string | null;
          name: string;
          is_active?: boolean;
          sort_order?: number;
        };
        Update: Partial<Database['public']['Tables']['expense_categories']['Insert']>;
        Relationships: [];
      };
      expenses: {
        Row: {
          id: string;
          facility_id: string;
          category_id: string;
          amount_minor: number;
          amount_paid_minor: number;
          payment_status: "PAID" | "PARTIAL" | "PENDING";
          tax_minor: number | null;
          receipt_path: string | null;
          due_on: string | null;
          currency: string;
          payment_method: string | null;
          spent_on: string;
          vendor: string | null;
          reference: string | null;
          notes: string | null;
          status: string;
          created_by: string | null;
          created_at: string;
          updated_by: string | null;
          updated_at: string;
          voided_by: string | null;
          voided_at: string | null;
          void_reason: string | null;
        };
        Insert: {
          id?: string;
          facility_id: string;
          category_id: string;
          amount_minor: number;
          currency?: string;
          payment_method?: string | null;
          spent_on?: string;
          vendor?: string | null;
          reference?: string | null;
          notes?: string | null;
        };
        Update: Partial<Database['public']['Tables']['expenses']['Insert']>;
        Relationships: [];
      };
      expense_payments: {
        Row: {
          id: string;
          expense_id: string;
          facility_id: string;
          amount_minor: number;
          paid_on: string;
          payment_method: string | null;
          reference: string | null;
          note: string | null;
          created_by: string | null;
          created_at: string;
        };
        Insert: {
          id?: string;
          expense_id: string;
          facility_id: string;
          amount_minor: number;
          paid_on?: string;
          payment_method?: string | null;
          reference?: string | null;
          note?: string | null;
        };
        Update: Partial<Database['public']['Tables']['expense_payments']['Insert']>;
        Relationships: [];
      };
      daily_closings: {
        Row: {
          id: string;
          facility_id: string;
          closing_date: string;
          opening_cash_minor: number;
          cash_collected_minor: number | null;
          upi_collected_minor: number | null;
          card_collected_minor: number | null;
          online_collected_minor: number | null;
          bank_transfer_collected_minor: number | null;
          other_collected_minor: number | null;
          total_collected_minor: number | null;
          cash_expense_minor: number | null;
          total_expense_minor: number | null;
          expected_cash_minor: number | null;
          actual_cash_minor: number | null;
          variance_minor: number | null;
          variance_reason: string | null;
          status: "OPEN" | "CLOSED" | "REOPENED";
          opened_by: string | null;
          opened_at: string;
          closed_by: string | null;
          closed_at: string | null;
          reopened_by: string | null;
          reopened_at: string | null;
          reopen_reason: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          facility_id: string;
          closing_date: string;
          opening_cash_minor?: number;
        };
        Update: Partial<Database['public']['Tables']['daily_closings']['Insert']>;
        Relationships: [];
      };
      daily_closing_events: {
        Row: {
          id: string;
          closing_id: string;
          facility_id: string;
          event: string;
          detail: Record<string, unknown>;
          actor: string | null;
          created_at: string;
        };
        Insert: {
          id?: string;
          closing_id: string;
          facility_id: string;
          event: string;
          detail?: Record<string, unknown>;
          actor?: string | null;
        };
        Update: Partial<Database['public']['Tables']['daily_closing_events']['Insert']>;
        Relationships: [];
      };
      maintenance_issue_categories: {
        Row: {
          id: string;
          facility_id: string | null;
          name: string;
          icon: string;
          description: string | null;
          is_active: boolean;
          sort_order: number;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          facility_id?: string | null;
          name: string;
          icon?: string;
          description?: string | null;
          is_active?: boolean;
          sort_order?: number;
        };
        Update: Partial<Database['public']['Tables']['maintenance_issue_categories']['Insert']>;
        Relationships: [];
      };
      maintenance_tickets: {
        Row: {
          id: string;
          facility_id: string;
          court_id: string;
          facility_sport_id: string | null;
          issue_category_id: string;
          title: string;
          description: string;
          priority: "LOW" | "MEDIUM" | "HIGH" | "CRITICAL";
          status: "REPORTED" | "ASSIGNED" | "SCHEDULED" | "IN_PROGRESS" | "RESOLVED" | "CLOSED";
          reported_by: string;
          reported_at: string;
          assigned_to: string | null;
          scheduled_start: string | null;
          scheduled_end: string | null;
          actual_start: string | null;
          actual_end: string | null;
          estimated_cost_minor: number | null;
          actual_cost_minor: number | null;
          expense_id: string | null;
          notes: string | null;
          resolved_at: string | null;
          closed_at: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          facility_id: string;
          court_id: string;
          issue_category_id: string;
          title: string;
          description: string;
          priority?: "LOW" | "MEDIUM" | "HIGH" | "CRITICAL";
          reported_by: string;
        };
        Update: Partial<Database['public']['Tables']['maintenance_tickets']['Insert']>;
        Relationships: [];
      };
      maintenance_blocks: {
        Row: {
          id: string;
          facility_id: string;
          court_id: string;
          ticket_id: string;
          start_time: string;
          end_time: string;
          status: "ACTIVE" | "ENDED" | "CANCELLED";
          created_by: string;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          facility_id: string;
          court_id: string;
          ticket_id: string;
          start_time: string;
          end_time: string;
          created_by: string;
        };
        Update: Partial<Database['public']['Tables']['maintenance_blocks']['Insert']>;
        Relationships: [];
      };
      maintenance_ticket_activity: {
        Row: {
          id: string;
          ticket_id: string;
          facility_id: string;
          event_type: string;
          actor_id: string | null;
          note: string | null;
          metadata: Record<string, unknown>;
          created_at: string;
        };
        Insert: {
          id?: string;
          ticket_id: string;
          facility_id: string;
          event_type: string;
          note?: string | null;
        };
        Update: Partial<Database['public']['Tables']['maintenance_ticket_activity']['Insert']>;
        Relationships: [];
      };
      maintenance_ticket_attachments: {
        Row: {
          id: string;
          ticket_id: string;
          facility_id: string;
          storage_path: string;
          file_name: string;
          content_type: string | null;
          size_bytes: number | null;
          uploaded_by: string | null;
          created_at: string;
        };
        Insert: {
          id?: string;
          ticket_id: string;
          facility_id: string;
          storage_path: string;
          file_name: string;
          content_type?: string | null;
          size_bytes?: number | null;
        };
        Update: Partial<Database['public']['Tables']['maintenance_ticket_attachments']['Insert']>;
        Relationships: [];
      };
    };
    Views: {
      finance_transactions_view: {
        Row: {
          id: string;
          reference: string;
          facility_id: string;
          created_at: string;
          paid_at: string | null;
          effective_at: string;
          source_type: "MEMBERSHIP" | "MEMBER_BOOKING" | "GUEST_BOOKING";
          customer_name: string | null;
          customer_phone: string | null;
          booking_id: string | null;
          membership_id: string | null;
          payment_order_id: string | null;
          amount_minor: number;
          currency: string;
          payment_method: string | null;
          status: "created" | "paid" | "failed" | "refunded";
          razorpay_order_id: string | null;
          razorpay_payment_id: string | null;
          refunded_minor: number;
          pending_refund_minor: number;
          net_minor: number;
        };
        Relationships: [];
      };
    };
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
      has_permission: {
        Args: { p_facility: string; p_permission: string };
        Returns: boolean;
      };
      my_facility_permissions: {
        Args: { p_facility: string };
        Returns: string[];
      };
      mark_password_reset_complete: {
        Args: Record<string, never>;
        Returns: undefined;
      };
      record_my_login: {
        Args: Record<string, never>;
        Returns: undefined;
      };
      log_security_event: {
        Args: {
          p_facility_id: string;
          p_event: string;
          p_summary: string;
          p_target_user_id?: string | null;
          p_target_role_id?: string | null;
          p_detail?: Record<string, unknown>;
        };
        Returns: undefined;
      };
      list_staff: {
        Args: {
          p_facility_id: string;
          p_search?: string | null;
          p_status?: string | null;
          p_role_id?: string | null;
          p_limit?: number;
          p_offset?: number;
        };
        Returns: {
          assignment_id: string;
          user_id: string;
          full_name: string;
          email: string;
          phone: string | null;
          avatar_url: string | null;
          role_id: string | null;
          role_name: string;
          base_role: FacilityRole;
          status: "ACTIVE" | "INACTIVE" | "INVITED";
          is_primary: boolean;
          title: string | null;
          facility_count: number;
          last_login_at: string | null;
          joined_at: string;
          total_count: number;
        }[];
      };
      get_staff: {
        Args: { p_facility_id: string; p_user_id: string };
        Returns: Record<string, unknown>;
      };
      list_roles: {
        Args: { p_facility_id: string };
        Returns: {
          id: string;
          key: string | null;
          name: string;
          description: string | null;
          is_system: boolean;
          is_custom: boolean;
          is_active: boolean;
          version: number;
          staff_count: number;
          permission_count: number;
        }[];
      };
      get_role: {
        Args: { p_role_id: string };
        Returns: Record<string, unknown>;
      };
      list_role_templates: {
        Args: Record<string, never>;
        Returns: { id: string; name: string; description: string | null; permission_keys: string[] }[];
      };
      list_permissions: {
        Args: Record<string, never>;
        Returns: {
          key: string;
          module: string;
          action: string;
          label: string;
          description: string | null;
          is_dangerous: boolean;
          sort_order: number;
        }[];
      };
      list_security_events: {
        Args: {
          p_facility_id: string;
          p_event?: string | null;
          p_target_user_id?: string | null;
          p_from?: string | null;
          p_to?: string | null;
          p_limit?: number;
          p_offset?: number;
        };
        Returns: {
          id: string;
          event: string;
          summary: string;
          actor_name: string | null;
          target_name: string | null;
          detail: Record<string, unknown>;
          created_at: string;
          total_count: number;
        }[];
      };
      create_role: {
        Args: {
          p_facility_id: string;
          p_name: string;
          p_description?: string | null;
          p_permission_keys?: string[];
          p_from_template_id?: string | null;
        };
        Returns: string;
      };
      update_role: {
        Args: {
          p_role_id: string;
          p_facility_id: string;
          p_name?: string | null;
          p_description?: string | null;
          p_is_active?: boolean | null;
          p_permission_keys?: string[] | null;
          p_expected_version?: number | null;
        };
        Returns: string;
      };
      delete_role: {
        Args: { p_role_id: string; p_facility_id: string };
        Returns: undefined;
      };
      assign_staff_role: {
        Args: { p_facility_id: string; p_user_id: string; p_role_id: string };
        Returns: undefined;
      };
      set_staff_status: {
        Args: { p_facility_id: string; p_user_id: string; p_status: string };
        Returns: undefined;
      };
      update_staff_profile: {
        Args: { p_facility_id: string; p_user_id: string; p_title?: string | null; p_notes?: string | null };
        Returns: undefined;
      };
      add_facility_access: {
        Args: { p_facility_id: string; p_user_id: string; p_role_id: string; p_is_primary?: boolean };
        Returns: undefined;
      };
      remove_facility_access: {
        Args: { p_facility_id: string; p_user_id: string };
        Returns: undefined;
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
          p_party_size?: number;
          p_payment_method?: string | null;
        };
        Returns: Database["public"]["Tables"]["bookings"]["Row"];
      };
      get_guest_bookings_summary: {
        Args: { p_facility_id: string; p_from: string; p_to: string };
        Returns: unknown;
      };
      list_guest_bookings_admin: {
        Args: {
          p_facility_id: string;
          p_search?: string | null;
          p_facility_sport_id?: string | null;
          p_court_id?: string | null;
          p_status?: string | null;
          p_payment_status?: string | null;
          p_from?: string | null;
          p_to?: string | null;
          p_limit?: number;
          p_offset?: number;
        };
        Returns: {
          booking_id: string;
          code: string;
          guest_name: string;
          guest_phone: string | null;
          sport_name: string | null;
          court_name: string;
          start_time: string;
          end_time: string;
          party_size: number;
          amount_minor: number | null;
          paid_minor: number;
          outstanding_minor: number;
          currency: string;
          payment_status: "PENDING" | "PARTIALLY_PAID" | "PAID" | "REFUNDED";
          payment_method: string | null;
          status: string;
          /** COURT = a bookings row; SESSION = a released membership seat. */
          source: "COURT" | "SESSION";
          total_count: number;
        }[];
      };
      update_guest_booking: {
        Args: { p_booking_id: string; p_guest_name: string; p_guest_phone: string | null; p_party_size: number; p_notes: string | null };
        Returns: Database["public"]["Tables"]["bookings"]["Row"];
      };
      complete_guest_booking: {
        Args: { p_booking_id: string };
        Returns: Database["public"]["Tables"]["bookings"]["Row"];
      };
      record_guest_booking_payment: {
        Args: { p_booking_id: string; p_method: string; p_amount_minor: number };
        Returns: Database["public"]["Tables"]["bookings"]["Row"];
      };
      duplicate_guest_booking: {
        Args: { p_booking_id: string; p_new_start: string; p_new_end: string };
        Returns: Database["public"]["Tables"]["bookings"]["Row"];
      };
      delete_guest_booking: {
        Args: { p_booking_id: string };
        Returns: undefined;
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
          p_monthly_price_inr?: number | null;
        };
        Returns: Database["public"]["Tables"]["memberships"]["Row"];
      };
      create_membership_full: {
        Args: {
          p_facility_id: string;
          p_full_name: string;
          p_phone: string;
          p_email: string | null;
          p_date_of_birth: string | null;
          p_gender: string | null;
          p_address: string | null;
          p_name: string | null;
          p_membership_type: string;
          p_max_family_members: number;
          p_start_date: string;
          p_duration_days: number;
          p_description: string | null;
          p_membership_fee_inr: number;
          p_registration_fee_inr: number;
          p_gst_percent: number;
          p_payment_mode: string;
          p_payment_methods: string | null;
          p_payment_reference: string | null;
          p_referral_member_id: string | null;
          p_discovery_source: string | null;
          p_notes: string | null;
          p_monthly_price_inr?: number | null;
          p_batch_id?: string | null;
          p_new_batch?: {
            courtId: string;
            facilitySportId: string;
            daysOfWeek: number[];
            startTime: string;
            endTime: string;
            capacity: number;
            name?: string;
          } | null;
        };
        Returns: Database["public"]["Tables"]["memberships"]["Row"];
      };
      update_membership_full: {
        Args: {
          p_membership_id: string;
          p_full_name: string;
          p_phone: string;
          p_email: string | null;
          p_date_of_birth: string | null;
          p_gender: string | null;
          p_address: string | null;
          p_name: string | null;
          p_membership_type: string;
          p_max_family_members: number;
          p_start_date: string;
          p_duration_days: number;
          p_description: string | null;
          p_membership_fee_inr: number;
          p_registration_fee_inr: number;
          p_gst_percent: number;
          p_referral_member_id: string | null;
          p_discovery_source: string | null;
          p_notes: string | null;
          p_batch_id?: string | null;
          p_new_batch?: {
            courtId: string;
            facilitySportId: string;
            daysOfWeek: number[];
            startTime: string;
            endTime: string;
            capacity: number;
            name?: string;
          } | null;
        };
        Returns: Database["public"]["Tables"]["memberships"]["Row"];
      };
      set_facility_membership_access_days: {
        Args: { p_facility_id: string; p_days: number[] };
        Returns: Database["public"]["Tables"]["facilities"]["Row"];
      };
      list_memberships: {
        Args: {
          p_facility_id: string;
          p_search?: string | null;
          p_status?: string | null;
          p_plan_id?: string | null;
          p_sort?: string;
          p_limit?: number;
          p_offset?: number;
        };
        Returns: {
          membership_id: string;
          member_id: string;
          member_name: string;
          member_phone: string;
          member_email: string | null;
          plan_id: string;
          plan_name: string;
          monthly_price_inr: number;
          display_status: string;
          start_date: string;
          end_date: string;
          days_left: number;
          created_by: string | null;
          created_by_name: string | null;
          batch_name: string | null;
          batch_days: number[] | null;
          batch_start: string | null;
          batch_end: string | null;
          batch_court: string | null;
          total_count: number;
        }[];
      };
      list_assignable_batches: {
        Args: { p_facility_id: string; p_plan_id?: string | null };
        Returns: {
          batch_id: string;
          name: string;
          plan_id: string | null;
          court_id: string;
          court_name: string;
          facility_sport_id: string;
          sport_name: string;
          days_of_week: number[];
          start_time: string;
          end_time: string;
          capacity: number;
          enrolled_count: number;
          spare: number;
        }[];
      };
      get_public_signup_batches: {
        Args: { p_facility_id: string; p_plan_id: string };
        Returns: {
          batchId: string;
          name: string;
          courtName: string;
          sportName: string;
          daysOfWeek: number[];
          startTime: string;
          endTime: string;
          capacity: number;
          spare: number;
        }[];
      };
      record_session_guest_payment: {
        Args: { p_session_booking_id: string; p_method: string; p_amount_minor: number };
        Returns: Database['public']['Tables']['membership_session_bookings']['Row'];
      };
      get_public_booking_facility: {
        Args: { p_facility_id: string };
        Returns: {
          facilityId: string;
          facilityName: string;
          city: string;
          currency: string;
          helpPhone: string | null;
          logoUrl: string | null;
          heroImageUrl: string | null;
          sports: { facilitySportId: string; name: string; sportKey: string | null }[];
        };
      };
      get_public_court_availability: {
        Args: { p_facility_id: string; p_facility_sport_id: string; p_date: string };
        Returns: {
          courtId: string;
          courtName: string;
          slots: { startTime: string; endTime: string; available: boolean; priceMinor: number }[];
        }[];
      };
      public_create_guest_booking: {
        Args: {
          p_facility_id: string;
          p_court_id: string;
          p_start_time: string;
          p_end_time: string;
          p_name: string;
          p_phone: string;
          p_email?: string | null;
          p_purpose?: string | null;
          p_notes?: string | null;
          p_party_size?: number;
        };
        Returns: {
          bookingId: string;
          code: string;
          facilityName: string;
          sportName: string;
          courtName: string;
          startTime: string;
          endTime: string;
          guestName: string;
          guestPhone: string;
          amountMinor: number;
          currency: string;
          paymentStatus: string;
          bookingStatus: string;
        };
      };
      get_membership_page_summary: {
        Args: { p_facility_id: string };
        Returns: {
          total_members: number;
          total_members_prev: number;
          active_members: number;
          payment_incomplete_members: number;
          revenue_inr: number;
          revenue_prev_inr: number;
        }[];
      };
      delete_member: {
        Args: { p_member_id: string };
        Returns: undefined;
      };
      record_membership_payment: {
        Args: { p_membership_id: string; p_method?: string };
        Returns: Database["public"]["Tables"]["memberships"]["Row"];
      };
      get_membership_detail: {
        Args: { p_membership_id: string };
        Returns: unknown;
      };
      get_membership_revenue_timeseries: {
        Args: {
          p_facility_id: string;
          p_granularity?: string;
          p_from?: string | null;
          p_to?: string | null;
        };
        Returns: { bucket: string; amount_inr: number; payment_count: number }[];
      };
      get_public_membership_signup_info: {
        Args: { p_facility_id: string };
        Returns: {
          facilityId: string;
          facilityName: string;
          city: string;
          plans: {
            id: string;
            name: string;
            priceInr: number;
            durationDays: number;
            features: string[];
          }[];
        };
      };
      public_start_membership_signup: {
        Args: {
          p_facility_id: string;
          p_full_name: string;
          p_phone: string;
          p_email: string;
          p_plan_id: string;
          p_batch_id?: string | null;
        };
        Returns: { membershipId: string; memberId: string; amountInr: number };
      };
      record_membership_subscription: {
        Args: {
          p_membership_id: string;
          p_razorpay_plan_id: string;
          p_razorpay_subscription_id: string;
          p_amount_inr: number;
          p_short_url?: string | null;
          p_razorpay_customer_id?: string | null;
        };
        Returns: Database["public"]["Tables"]["membership_subscriptions"]["Row"];
      };
      apply_subscription_webhook: {
        Args: {
          p_razorpay_subscription_id: string;
          p_status: MembershipSubscriptionStatus;
          p_charge_count?: number | null;
          p_current_start?: string | null;
          p_current_end?: string | null;
        };
        Returns: undefined;
      };
      record_subscription_charge: {
        Args: {
          p_razorpay_subscription_id: string;
          p_amount_inr: number;
          p_razorpay_payment_id: string;
          p_paid_at?: string;
        };
        Returns: undefined;
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
      get_membership_utilization_sessions: {
        Args: { p_facility_id: string; p_from: string; p_to: string };
        Returns: { court_id: string; session_date: string; start_time: string; end_time: string }[];
      };
      get_membership_sessions_summary: {
        Args: { p_facility_id: string };
        Returns: unknown;
      };
      list_membership_sessions_admin: {
        Args: {
          p_facility_id: string;
          p_search?: string | null;
          p_facility_sport_id?: string | null;
          p_court_id?: string | null;
          p_status?: string | null;
          p_day?: number | null;
          p_limit?: number;
          p_offset?: number;
        };
        Returns: {
          batch_id: string;
          name: string;
          court_id: string;
          court_name: string;
          facility_sport_id: string;
          sport_name: string;
          days_of_week: number[];
          start_time: string;
          end_time: string;
          capacity: number;
          roster_count: number;
          released_today: number;
          guest_booked_today: number;
          utilization_pct: number;
          status: string;
          is_active: boolean;
          total_count: number;
        }[];
      };
      get_membership_session_detail: {
        Args: { p_batch_id: string };
        Returns: unknown;
      };
      list_membership_session_members: {
        Args: { p_batch_id: string };
        Returns: {
          id: string;
          member_id: string;
          full_name: string;
          phone: string;
          status: string;
          added_on: string;
        }[];
      };
      set_membership_batch_notes: {
        Args: { p_batch_id: string; p_notes: string };
        Returns: undefined;
      };
      list_membership_session_occurrences: {
        Args: { p_batch_id: string; p_days?: number };
        Returns: {
          occurrence_date: string;
          is_blocked: boolean;
          block_reason: string | null;
          materialized: boolean;
          member_count: number;
          guest_count: number;
          released_capacity: number;
        }[];
      };
      list_membership_session_bookings: {
        Args: { p_batch_id: string; p_limit?: number };
        Returns: {
          booking_id: string;
          session_date: string;
          participant_type: string;
          participant_name: string;
          slot_source: string;
          status: string;
          amount_minor: number | null;
          created_at: string;
        }[];
      };
      list_membership_session_activity: {
        Args: { p_batch_id: string; p_limit?: number };
        Returns: { kind: string; actor: string | null; detail: string; at: string }[];
      };
      block_membership_batch_date: {
        Args: { p_batch_id: string; p_date: string; p_reason?: string | null };
        Returns: undefined;
      };
      unblock_membership_batch_date: {
        Args: { p_batch_id: string; p_date: string };
        Returns: undefined;
      };
      duplicate_membership_batch: {
        Args: { p_batch_id: string; p_new_name?: string | null };
        Returns: Database["public"]["Tables"]["membership_batches"]["Row"];
      };
      membership_batch_roster_count: {
        Args: { p_batch_id: string };
        Returns: number;
      };
      create_payment_order: {
        Args: {
          p_facility_id: string;
          p_source_type: "MEMBERSHIP" | "MEMBER_BOOKING" | "GUEST_BOOKING";
          p_booking_id?: string | null;
          p_membership_session_booking_id?: string | null;
          p_member_id?: string | null;
          p_plan_id?: string | null;
        };
        Returns: Database["public"]["Tables"]["payment_orders"]["Row"];
      };
      get_payment_order: {
        Args: { p_payment_order_id: string };
        Returns: Database["public"]["Tables"]["payment_orders"]["Row"];
      };
      record_payment_attempt: {
        Args: {
          p_payment_order_id: string;
          p_status: "PAYMENT_ATTEMPTED" | "FAILED";
          p_razorpay_payment_id?: string | null;
          p_razorpay_signature?: string | null;
        };
        Returns: Database["public"]["Tables"]["payment_orders"]["Row"];
      };
      apply_payment_verification: {
        Args: {
          p_payment_order_id: string;
          p_razorpay_order_id: string;
          p_razorpay_payment_id: string;
          p_razorpay_status: "AUTHORIZED" | "CAPTURED" | "FAILED" | "PAYMENT_VERIFIED";
          p_amount_minor: number;
          p_currency: string;
          p_razorpay_signature?: string | null;
        };
        Returns: Database["public"]["Tables"]["payment_orders"]["Row"];
      };
      settle_payment: {
        Args: { p_payment_order_id: string };
        Returns: Database["public"]["Tables"]["payment_orders"]["Row"];
      };
      activate_membership: {
        Args: { p_member_id: string; p_facility_id: string; p_plan_id: string; p_start_date: string };
        Returns: Database["public"]["Tables"]["memberships"]["Row"];
      };
      cancel_booking: {
        Args: {
          p_booking_id: string;
          p_reason?: string | null;
          p_refund_override_percent?: number | null;
          p_override_reason?: string | null;
        };
        Returns: Database["public"]["Tables"]["bookings"]["Row"];
      };
      cancel_membership_guest_slot: {
        Args: {
          p_booking_id: string;
          p_reason?: string | null;
          p_refund_override_percent?: number | null;
          p_override_reason?: string | null;
        };
        Returns: Record<string, unknown>;
      };
      cancel_membership: {
        Args: {
          p_membership_id: string;
          p_reason?: string | null;
          p_refund_amount_minor?: number | null;
          p_override_reason?: string | null;
        };
        Returns: Database["public"]["Tables"]["memberships"]["Row"];
      };
      refundable_amount: {
        Args: { p_payment_order_id: string };
        Returns: number;
      };
      get_effective_cancellation_policy: {
        Args: { p_facility_id: string };
        Returns: Database["public"]["Tables"]["cancellation_policies"]["Row"];
      };
      upsert_cancellation_policy: {
        Args: {
          p_facility_id: string;
          p_full_refund_hours: number;
          p_full_refund_percent: number;
          p_partial_refund_hours: number;
          p_partial_refund_percent: number;
        };
        Returns: Database["public"]["Tables"]["cancellation_policies"]["Row"];
      };
      get_refund: {
        Args: { p_refund_id: string };
        Returns: Database["public"]["Tables"]["refunds"]["Row"];
      };
      list_refunds: {
        Args: {
          p_facility_id: string;
          p_status?: string | null;
          p_source_type?: string | null;
          p_preset?: string | null;
          p_start_date?: string | null;
          p_end_date?: string | null;
          p_limit?: number;
          p_offset?: number;
        };
        Returns: Database["public"]["Tables"]["refunds"]["Row"][];
      };
      list_settlement_exceptions: {
        Args: {
          p_facility_id: string;
          p_status?: string | null;
          p_source_type?: string | null;
          p_preset?: string | null;
          p_start_date?: string | null;
          p_end_date?: string | null;
        };
        Returns: Database["public"]["Tables"]["settlement_exceptions"]["Row"][];
      };
      get_finance_summary: {
        Args: { p_facility_id: string; p_preset?: string; p_start_date?: string | null; p_end_date?: string | null };
        Returns: {
          gross_revenue_minor: number;
          refunds_minor: number;
          expenses_minor: number;
          net_revenue_minor: number;
          outstanding_minor: number;
          transaction_count: number;
          successful_payment_count: number;
          failed_payment_count: number;
          pending_payment_count: number;
          pending_refund_count: number;
          settlement_exception_count: number;
        }[];
      };
      list_expenses: {
        Args: {
          p_facility_id: string;
          p_preset?: string | null;
          p_start_date?: string | null;
          p_end_date?: string | null;
          p_category_id?: string | null;
          p_limit?: number;
          p_offset?: number;
          p_search?: string | null;
          p_payment_status?: string | null;
          p_payment_method?: string | null;
          p_vendor?: string | null;
          p_min_minor?: number | null;
          p_max_minor?: number | null;
          p_include_void?: boolean;
        };
        Returns: {
          id: string;
          category_id: string;
          category_name: string;
          amount_minor: number;
          amount_paid_minor: number;
          currency: string;
          payment_method: string | null;
          payment_status: "PAID" | "PARTIAL" | "PENDING";
          spent_on: string;
          due_on: string | null;
          vendor: string | null;
          reference: string | null;
          notes: string | null;
          receipt_path: string | null;
          status: string;
          created_by_name: string | null;
          created_at: string;
          total_count: number;
        }[];
      };
      void_expense: {
        Args: { p_expense_id: string; p_reason?: string | null };
        Returns: Database['public']['Tables']['expenses']['Row'];
      };
      create_expense: {
        Args: {
          p_facility_id: string;
          p_category_id: string;
          p_amount_minor: number;
          p_spent_on: string;
          p_payment_method?: string | null;
          p_vendor?: string | null;
          p_reference?: string | null;
          p_notes?: string | null;
          p_payment_status?: string;
          p_amount_paid_minor?: number | null;
          p_tax_minor?: number | null;
          p_due_on?: string | null;
          p_receipt_path?: string | null;
        };
        Returns: Database['public']['Tables']['expenses']['Row'];
      };
      update_expense: {
        Args: {
          p_expense_id: string;
          p_category_id?: string | null;
          p_amount_minor?: number | null;
          p_spent_on?: string | null;
          p_payment_method?: string | null;
          p_vendor?: string | null;
          p_reference?: string | null;
          p_notes?: string | null;
          p_tax_minor?: number | null;
          p_due_on?: string | null;
          p_receipt_path?: string | null;
        };
        Returns: Database['public']['Tables']['expenses']['Row'];
      };
      record_expense_payment: {
        Args: {
          p_expense_id: string;
          p_amount_minor?: number | null;
          p_paid_on?: string | null;
          p_payment_method?: string | null;
          p_reference?: string | null;
          p_note?: string | null;
          p_idempotency_key?: string | null;
        };
        Returns: Database['public']['Tables']['expenses']['Row'];
      };
      get_expense: {
        Args: { p_expense_id: string };
        Returns: {
          id: string;
          facility_id: string;
          category_id: string;
          category_name: string;
          amount_minor: number;
          amount_paid_minor: number;
          tax_minor: number | null;
          currency: string;
          payment_status: "PAID" | "PARTIAL" | "PENDING";
          payment_method: string | null;
          spent_on: string;
          due_on: string | null;
          vendor: string | null;
          reference: string | null;
          notes: string | null;
          receipt_path: string | null;
          status: string;
          created_by: string | null;
          created_by_name: string | null;
          created_at: string;
          updated_at: string;
          voided_at: string | null;
          void_reason: string | null;
          source_maintenance_ticket_id: string | null;
          payments: {
            id: string;
            amountMinor: number;
            paidOn: string;
            paymentMethod: string | null;
            reference: string | null;
            note: string | null;
            createdAt: string;
          }[];
        }[];
      };
      get_expense_summary: {
        Args: { p_facility_id: string; p_preset?: string; p_start_date?: string | null; p_end_date?: string | null };
        Returns: {
          total_minor: number;
          this_month_minor: number;
          this_week_minor: number;
          pending_minor: number;
          pending_count: number;
          maintenance_minor: number;
          other_minor: number;
        }[];
      };
      get_daily_closing_summary: {
        Args: { p_facility_id: string; p_date?: string | null };
        Returns: {
          closing_date: string;
          opening_cash_minor: number;
          cash_collected_minor: number;
          upi_collected_minor: number;
          card_collected_minor: number;
          online_collected_minor: number;
          bank_transfer_collected_minor: number;
          other_collected_minor: number;
          total_collected_minor: number;
          cash_expense_minor: number;
          other_expense_minor: number;
          total_expense_minor: number;
          expected_cash_minor: number;
          payment_count: number;
          expense_count: number;
          pending_payment_count: number;
          closing_id: string | null;
          status: "NOT_STARTED" | "OPEN" | "CLOSED" | "REOPENED";
          actual_cash_minor: number | null;
          variance_minor: number | null;
          variance_reason: string | null;
          closed_at: string | null;
        }[];
      };
      open_daily_closing: {
        Args: { p_facility_id: string; p_date?: string | null; p_opening_cash_minor?: number | null };
        Returns: Database['public']['Tables']['daily_closings']['Row'];
      };
      set_daily_closing_opening_cash: {
        Args: { p_closing_id: string; p_opening_cash_minor: number };
        Returns: Database['public']['Tables']['daily_closings']['Row'];
      };
      close_daily_closing: {
        Args: { p_closing_id: string; p_actual_cash_minor: number; p_variance_reason?: string | null };
        Returns: Database['public']['Tables']['daily_closings']['Row'];
      };
      reopen_daily_closing: {
        Args: { p_closing_id: string; p_reason: string };
        Returns: Database['public']['Tables']['daily_closings']['Row'];
      };
      list_daily_closings: {
        Args: {
          p_facility_id: string;
          p_preset?: string;
          p_start_date?: string | null;
          p_end_date?: string | null;
          p_limit?: number;
          p_offset?: number;
        };
        Returns: {
          id: string;
          closing_date: string;
          opening_cash_minor: number;
          total_collected_minor: number | null;
          total_expense_minor: number | null;
          expected_cash_minor: number | null;
          actual_cash_minor: number | null;
          variance_minor: number | null;
          status: "OPEN" | "CLOSED" | "REOPENED";
          closed_at: string | null;
          closed_by_name: string | null;
          total_count: number;
        }[];
      };
      get_pnl: {
        Args: {
          p_facility_id: string;
          p_preset?: string;
          p_start_date?: string | null;
          p_end_date?: string | null;
          p_category_id?: string | null;
        };
        Returns: {
          booking_revenue_minor: number;
          membership_revenue_minor: number;
          guest_booking_revenue_minor: number;
          other_revenue_minor: number;
          gross_revenue_minor: number;
          refunds_minor: number;
          total_revenue_minor: number;
          total_expense_minor: number;
          net_profit_minor: number;
          profit_margin_pct: number;
          expense_by_category: { categoryId: string; category: string; amountMinor: number }[];
        }[];
      };
      get_pnl_trend: {
        Args: {
          p_facility_id: string;
          p_preset?: string;
          p_start_date?: string | null;
          p_end_date?: string | null;
          p_granularity?: string;
        };
        Returns: { bucket_date: string; revenue_minor: number; expense_minor: number; net_minor: number }[];
      };
      get_transaction_details: {
        Args: { p_transaction_id: string };
        Returns: Record<string, unknown>;
      };
      list_pending_payments: {
        Args: {
          p_facility_id: string;
          p_search?: string | null;
          p_source_type?: string | null;
          p_status?: string | null;
          p_from?: string | null;
          p_to?: string | null;
          p_sort?: string | null;
          p_limit?: number;
          p_offset?: number;
          p_source_id?: string | null;
        };
        Returns: {
          source_type: "GUEST_BOOKING" | "BOOKING" | "MEMBERSHIP";
          source_id: string;
          reference: string;
          customer_name: string;
          customer_phone: string | null;
          description: string;
          facility_name: string | null;
          court_name: string | null;
          starts_at: string | null;
          ends_at: string | null;
          total_minor: number;
          paid_minor: number;
          outstanding_minor: number;
          status: "PENDING" | "PARTIALLY_PAID" | "OVERDUE" | "PAID";
          payment_method: string | null;
          due_on: string;
          total_count: number;
        }[];
      };
      get_pending_payments_summary: {
        Args: { p_facility_id: string; p_from?: string | null; p_to?: string | null };
        Returns: {
          outstanding_minor: number;
          pending_minor: number;
          partially_paid_minor: number;
          overdue_minor: number;
          obligation_count: number;
        }[];
      };
      record_obligation_payment: {
        Args: {
          p_source_type: string;
          p_source_id: string;
          p_amount_minor: number;
          p_method: string;
          p_paid_on?: string | null;
          p_reference?: string | null;
          p_notes?: string | null;
          p_idempotency_key?: string | null;
        };
        Returns: {
          duplicate: boolean;
          totalMinor?: number;
          paidMinor?: number;
          outstandingMinor?: number;
          paymentId?: string;
        };
      };
      list_finance_ledger: {
        Args: {
          p_facility_id: string;
          p_preset?: string;
          p_start_date?: string | null;
          p_end_date?: string | null;
          p_txn_type?: string | null;
          p_category?: string | null;
          p_payment_method?: string | null;
          p_status?: string | null;
          p_search?: string | null;
          p_limit?: number;
          p_offset?: number;
        };
        Returns: {
          id: string;
          reference: string;
          occurred_at: string;
          description: string;
          category: string;
          txn_type: "INCOME" | "EXPENSE" | "REFUND";
          payment_method: string | null;
          amount_minor: number;
          currency: string;
          status: string;
          source_type: string;
          booking_id: string | null;
          membership_id: string | null;
          expense_id: string | null;
          total_count: number;
        }[];
      };
      list_finance_payment_methods: {
        Args: { p_facility_id: string };
        Returns: { payment_method: string }[];
      };
      get_payment_method_breakdown: {
        Args: { p_facility_id: string; p_preset?: string; p_start_date?: string | null; p_end_date?: string | null };
        Returns: { payment_method: string; amount_minor: number; payment_count: number }[];
      };
      get_revenue_breakdown: {
        Args: { p_facility_id: string; p_preset?: string; p_start_date?: string | null; p_end_date?: string | null };
        Returns: {
          membership_revenue_minor: number;
          member_booking_revenue_minor: number;
          guest_booking_revenue_minor: number;
          refunds_minor: number;
          net_revenue_minor: number;
          membership_included_usage_count: number;
        }[];
      };
      get_revenue_trend: {
        Args: { p_facility_id: string; p_preset?: string; p_start_date?: string | null; p_end_date?: string | null; p_granularity?: string };
        Returns: { bucket_date: string; gross_minor: number; refund_minor: number; net_minor: number }[];
      };
      list_finance_transactions: {
        Args: {
          p_facility_id: string;
          p_preset?: string;
          p_start_date?: string | null;
          p_end_date?: string | null;
          p_source_type?: string | null;
          p_status?: string | null;
          p_search?: string | null;
          p_limit?: number;
          p_offset?: number;
        };
        Returns: Database["public"]["Views"]["finance_transactions_view"]["Row"][];
      };
      count_finance_transactions: {
        Args: {
          p_facility_id: string;
          p_preset?: string;
          p_start_date?: string | null;
          p_end_date?: string | null;
          p_source_type?: string | null;
          p_status?: string | null;
          p_search?: string | null;
        };
        Returns: number;
      };
      get_finance_transaction: {
        Args: { p_transaction_id: string };
        Returns: Database["public"]["Views"]["finance_transactions_view"]["Row"];
      };
      get_booking_analytics: {
        Args: {
          p_facility_id: string;
          p_preset?: string;
          p_start_date?: string | null;
          p_end_date?: string | null;
          p_facility_sport_id?: string | null;
          p_court_id?: string | null;
        };
        Returns: {
          total: number;
          completed: number;
          confirmed: number;
          pending: number;
          cancelled: number;
          guest_count: number;
          member_count: number;
          avg_guest_booking_value_minor: number;
        }[];
      };
      get_booking_trend: {
        Args: {
          p_facility_id: string;
          p_preset?: string;
          p_start_date?: string | null;
          p_end_date?: string | null;
          p_facility_sport_id?: string | null;
          p_court_id?: string | null;
          p_granularity?: string;
        };
        Returns: { bucket_date: string; total: number; completed: number; cancelled: number }[];
      };
      get_bookings_by_sport: {
        Args: {
          p_facility_id: string;
          p_preset?: string;
          p_start_date?: string | null;
          p_end_date?: string | null;
          p_facility_sport_id?: string | null;
          p_court_id?: string | null;
        };
        Returns: { facility_sport_id: string; sport_name: string; booking_count: number }[];
      };
      get_booking_source_split: {
        Args: {
          p_facility_id: string;
          p_preset?: string;
          p_start_date?: string | null;
          p_end_date?: string | null;
          p_facility_sport_id?: string | null;
          p_court_id?: string | null;
        };
        Returns: { source: string; booking_count: number }[];
      };
      get_overall_utilization: {
        Args: {
          p_facility_id: string;
          p_preset?: string;
          p_start_date?: string | null;
          p_end_date?: string | null;
          p_facility_sport_id?: string | null;
          p_court_id?: string | null;
        };
        Returns: { open_minutes: number; booked_minutes: number; utilization_pct: number }[];
      };
      get_court_utilization: {
        Args: {
          p_facility_id: string;
          p_preset?: string;
          p_start_date?: string | null;
          p_end_date?: string | null;
          p_facility_sport_id?: string | null;
          p_court_id?: string | null;
        };
        Returns: {
          court_id: string;
          court_name: string;
          facility_sport_id: string;
          sport_name: string;
          open_minutes: number;
          booked_minutes: number;
          utilization_pct: number;
        }[];
      };
      get_sport_utilization: {
        Args: {
          p_facility_id: string;
          p_preset?: string;
          p_start_date?: string | null;
          p_end_date?: string | null;
          p_facility_sport_id?: string | null;
          p_court_id?: string | null;
        };
        Returns: {
          facility_sport_id: string;
          sport_name: string;
          open_minutes: number;
          booked_minutes: number;
          utilization_pct: number;
        }[];
      };
      get_peak_hours: {
        Args: {
          p_facility_id: string;
          p_preset?: string;
          p_start_date?: string | null;
          p_end_date?: string | null;
          p_facility_sport_id?: string | null;
          p_court_id?: string | null;
        };
        Returns: { hour: number; open_minutes: number; booked_minutes: number; demand_pct: number }[];
      };
      get_demand_heatmap: {
        Args: {
          p_facility_id: string;
          p_preset?: string;
          p_start_date?: string | null;
          p_end_date?: string | null;
          p_facility_sport_id?: string | null;
          p_court_id?: string | null;
        };
        Returns: {
          dow: number;
          hour: number;
          open_minutes: number;
          booked_minutes: number;
          demand_pct: number;
        }[];
      };
      get_revenue_by_sport: {
        Args: {
          p_facility_id: string;
          p_preset?: string;
          p_start_date?: string | null;
          p_end_date?: string | null;
          p_facility_sport_id?: string | null;
          p_court_id?: string | null;
        };
        Returns: { facility_sport_id: string; sport_name: string; revenue_minor: number }[];
      };
      get_revenue_by_court: {
        Args: {
          p_facility_id: string;
          p_preset?: string;
          p_start_date?: string | null;
          p_end_date?: string | null;
          p_facility_sport_id?: string | null;
          p_court_id?: string | null;
        };
        Returns: {
          court_id: string;
          court_name: string;
          facility_sport_id: string;
          sport_name: string;
          revenue_minor: number;
        }[];
      };
      get_analytics_overview: {
        Args: {
          p_facility_id: string;
          p_preset?: string;
          p_start_date?: string | null;
          p_end_date?: string | null;
          p_facility_sport_id?: string | null;
          p_court_id?: string | null;
        };
        Returns: {
          gross_revenue_minor: number;
          booking_revenue_minor: number;
          membership_revenue_minor: number;
          expenses_minor: number;
          net_revenue_minor: number;
          outstanding_minor: number;
          total_bookings: number;
          completed_bookings: number;
          cancelled_bookings: number;
          overall_utilization_pct: number;
        }[];
      };
      get_membership_analytics: {
        Args: { p_facility_id: string; p_preset?: string; p_start_date?: string | null; p_end_date?: string | null };
        Returns: {
          active_members: number;
          new_memberships: number;
          expiring_soon: number;
          membership_revenue_minor: number;
          paid_count: number;
          partially_paid_count: number;
          pending_count: number;
          outstanding_minor: number;
        }[];
      };
      get_memberships_by_type: {
        Args: { p_facility_id: string; p_preset?: string; p_start_date?: string | null; p_end_date?: string | null };
        Returns: { membership_type: string; plan_name: string; count: number; revenue_minor: number }[];
      };
      get_membership_session_analytics: {
        Args: {
          p_facility_id: string;
          p_preset?: string;
          p_start_date?: string | null;
          p_end_date?: string | null;
          p_facility_sport_id?: string | null;
          p_court_id?: string | null;
        };
        Returns: {
          session_count: number;
          total_capacity: number;
          member_allocations: number;
          guest_released: number;
          guest_booked: number;
          remaining_released: number;
          unused_capacity: number;
        }[];
      };
      get_guest_release_analytics: {
        Args: {
          p_facility_id: string;
          p_preset?: string;
          p_start_date?: string | null;
          p_end_date?: string | null;
          p_facility_sport_id?: string | null;
          p_court_id?: string | null;
        };
        Returns: { released: number; booked: number; remaining: number; revenue_minor: number }[];
      };
      get_guest_booking_analytics: {
        Args: {
          p_facility_id: string;
          p_preset?: string;
          p_start_date?: string | null;
          p_end_date?: string | null;
          p_facility_sport_id?: string | null;
          p_court_id?: string | null;
        };
        Returns: {
          total: number;
          completed: number;
          confirmed: number;
          pending: number;
          cancelled: number;
          revenue_minor: number;
          avg_booking_value_minor: number;
          collected_minor: number;
          outstanding_minor: number;
          collection_rate_pct: number;
        }[];
      };
      get_guest_bookings_by_sport: {
        Args: {
          p_facility_id: string;
          p_preset?: string;
          p_start_date?: string | null;
          p_end_date?: string | null;
          p_facility_sport_id?: string | null;
          p_court_id?: string | null;
        };
        Returns: { facility_sport_id: string; sport_name: string; booking_count: number; revenue_minor: number }[];
      };
      get_guest_bookings_by_court: {
        Args: {
          p_facility_id: string;
          p_preset?: string;
          p_start_date?: string | null;
          p_end_date?: string | null;
          p_facility_sport_id?: string | null;
          p_court_id?: string | null;
        };
        Returns: {
          court_id: string;
          court_name: string;
          sport_name: string;
          booking_count: number;
          revenue_minor: number;
        }[];
      };
      get_guest_peak_hours: {
        Args: {
          p_facility_id: string;
          p_preset?: string;
          p_start_date?: string | null;
          p_end_date?: string | null;
          p_facility_sport_id?: string | null;
          p_court_id?: string | null;
        };
        Returns: { hour: number; booking_count: number }[];
      };
      list_maintenance_issue_categories: {
        Args: { p_facility_id: string; p_include_inactive?: boolean };
        Returns: {
          id: string;
          facility_id: string | null;
          name: string;
          icon: string;
          description: string | null;
          is_active: boolean;
          sort_order: number;
          issue_count: number;
          is_shared: boolean;
        }[];
      };
      create_maintenance_issue_category: {
        Args: { p_facility_id: string; p_name: string; p_icon: string; p_description?: string | null; p_sort_order?: number };
        Returns: Database['public']['Tables']['maintenance_issue_categories']['Row'];
      };
      update_maintenance_issue_category: {
        Args: {
          p_category_id: string;
          p_name: string;
          p_icon: string;
          p_description?: string | null;
          p_sort_order?: number;
          p_is_active?: boolean;
        };
        Returns: Database['public']['Tables']['maintenance_issue_categories']['Row'];
      };
      create_maintenance_ticket: {
        Args: {
          p_facility_id: string;
          p_court_id: string;
          p_issue_category_id: string;
          p_priority: "LOW" | "MEDIUM" | "HIGH" | "CRITICAL";
          p_title: string;
          p_description: string;
          p_scheduled_start?: string | null;
          p_scheduled_end?: string | null;
          p_assigned_to?: string | null;
          p_estimated_cost_minor?: number | null;
          p_notes?: string | null;
        };
        Returns: Database['public']['Tables']['maintenance_tickets']['Row'];
      };
      update_maintenance_ticket: {
        Args: {
          p_ticket_id: string;
          p_title: string;
          p_description: string;
          p_issue_category_id: string;
          p_priority: "LOW" | "MEDIUM" | "HIGH" | "CRITICAL";
          p_notes?: string | null;
        };
        Returns: Database['public']['Tables']['maintenance_tickets']['Row'];
      };
      assign_maintenance_ticket: {
        Args: { p_ticket_id: string; p_assigned_to: string };
        Returns: Database['public']['Tables']['maintenance_tickets']['Row'];
      };
      schedule_maintenance: {
        Args: { p_ticket_id: string; p_start: string; p_end: string };
        Returns: Database['public']['Tables']['maintenance_tickets']['Row'];
      };
      start_maintenance_ticket: {
        Args: { p_ticket_id: string };
        Returns: Database['public']['Tables']['maintenance_tickets']['Row'];
      };
      add_maintenance_note: {
        Args: { p_ticket_id: string; p_note: string };
        Returns: Database['public']['Tables']['maintenance_ticket_activity']['Row'];
      };
      update_maintenance_cost: {
        Args: {
          p_ticket_id: string;
          p_estimated_cost_minor?: number | null;
          p_actual_cost_minor?: number | null;
          p_post_to_expenses?: boolean;
          p_expense_category_id?: string | null;
          p_payment_method?: string | null;
          p_vendor?: string | null;
        };
        Returns: Database['public']['Tables']['maintenance_tickets']['Row'];
      };
      resolve_maintenance_ticket: {
        Args: { p_ticket_id: string; p_actual_end?: string | null };
        Returns: Database['public']['Tables']['maintenance_tickets']['Row'];
      };
      reopen_maintenance_ticket: {
        Args: { p_ticket_id: string };
        Returns: Database['public']['Tables']['maintenance_tickets']['Row'];
      };
      close_maintenance_ticket: {
        Args: { p_ticket_id: string; p_reason?: string | null };
        Returns: Database['public']['Tables']['maintenance_tickets']['Row'];
      };
      list_maintenance_tickets: {
        Args: {
          p_facility_id: string;
          p_search?: string | null;
          p_status?: string | null;
          p_priority?: string | null;
          p_court_id?: string | null;
          p_facility_sport_id?: string | null;
          p_issue_category_id?: string | null;
          p_assigned_to?: string | null;
          p_from?: string | null;
          p_to?: string | null;
          p_sort?: string | null;
          p_limit?: number;
          p_offset?: number;
        };
        Returns: {
          ticket_id: string;
          code: string;
          court_id: string;
          court_name: string;
          sport_name: string | null;
          issue_category_id: string;
          category_name: string;
          title: string;
          priority: "LOW" | "MEDIUM" | "HIGH" | "CRITICAL";
          status: "REPORTED" | "ASSIGNED" | "SCHEDULED" | "IN_PROGRESS" | "RESOLVED" | "CLOSED";
          reported_by_name: string;
          assigned_to_name: string | null;
          scheduled_start: string | null;
          reported_at: string;
          actual_cost_minor: number | null;
          estimated_cost_minor: number | null;
          total_count: number;
        }[];
      };
      get_maintenance_ticket_detail: {
        Args: { p_ticket_id: string };
        Returns: unknown;
      };
      get_maintenance_court_status: {
        Args: { p_facility_id: string };
        Returns: { court_id: string; court_name: string; sport_name: string | null; status: "AVAILABLE" | "IN_USE" | "UNDER_MAINTENANCE" | "BLOCKED" }[];
      };
      get_maintenance_overview: {
        Args: { p_facility_id: string };
        Returns: unknown;
      };
      detect_maintenance_affected_bookings: {
        Args: { p_court_id: string; p_start: string; p_end: string; p_exclude_ticket_id?: string | null };
        Returns: {
          booking_id: string;
          customer_type: "MEMBER" | "GUEST";
          guest_name: string | null;
          guest_phone: string | null;
          member_id: string | null;
          start_time: string;
          end_time: string;
          status: string;
          payment_status: string;
          amount_minor: number | null;
        }[];
      };
      detect_maintenance_affected_membership_sessions: {
        Args: { p_court_id: string; p_start: string; p_end: string; p_timezone?: string };
        Returns: {
          batch_id: string;
          batch_name: string;
          session_date: string;
          start_time: string;
          end_time: string;
          member_booked_count: number;
          guest_booked_count: number;
        }[];
      };
      add_maintenance_attachment: {
        Args: { p_ticket_id: string; p_storage_path: string; p_file_name: string; p_content_type?: string | null; p_size_bytes?: number | null };
        Returns: Database['public']['Tables']['maintenance_ticket_attachments']['Row'];
      };
      list_facility_staff: {
        Args: { p_facility_id: string };
        Returns: { user_id: string; full_name: string; role: FacilityRole }[];
      };

      // ── Inventory & Vendors ──────────────────────────────────────────────
      create_vendor: {
        Args: {
          p_facility_id: string;
          p_name: string;
          p_contact_person?: string | null;
          p_phone?: string | null;
          p_email?: string | null;
          p_address?: string | null;
          p_gst_number?: string | null;
          p_pan_number?: string | null;
          p_notes?: string | null;
        };
        Returns: Database["public"]["Tables"]["vendors"]["Row"];
      };
      update_vendor: {
        Args: {
          p_vendor_id: string;
          p_name?: string | null;
          p_contact_person?: string | null;
          p_phone?: string | null;
          p_email?: string | null;
          p_address?: string | null;
          p_gst_number?: string | null;
          p_pan_number?: string | null;
          p_notes?: string | null;
          p_status?: string | null;
        };
        Returns: Database["public"]["Tables"]["vendors"]["Row"];
      };
      create_inventory_category: {
        Args: { p_facility_id: string; p_name: string; p_description?: string | null; p_sort_order?: number };
        Returns: Database["public"]["Tables"]["inventory_categories"]["Row"];
      };
      update_inventory_category: {
        Args: {
          p_category_id: string;
          p_name?: string | null;
          p_description?: string | null;
          p_is_active?: boolean | null;
          p_sort_order?: number | null;
        };
        Returns: Database["public"]["Tables"]["inventory_categories"]["Row"];
      };
      create_inventory_item: {
        Args: {
          p_facility_id: string;
          p_name: string;
          p_sku: string;
          p_category_id?: string | null;
          p_unit?: string;
          p_reorder_level?: number;
          p_brand?: string | null;
          p_description?: string | null;
          p_default_unit_cost_minor?: number | null;
          p_preferred_vendor_id?: string | null;
          p_image_path?: string | null;
          p_opening_stock?: number;
        };
        Returns: Database["public"]["Tables"]["inventory_items"]["Row"];
      };
      update_inventory_item: {
        Args: {
          p_item_id: string;
          p_name?: string | null;
          p_sku?: string | null;
          p_category_id?: string | null;
          p_unit?: string | null;
          p_reorder_level?: number | null;
          p_brand?: string | null;
          p_description?: string | null;
          p_default_unit_cost_minor?: number | null;
          p_preferred_vendor_id?: string | null;
          p_image_path?: string | null;
          p_status?: string | null;
        };
        Returns: Database["public"]["Tables"]["inventory_items"]["Row"];
      };
      record_stock_movement: {
        Args: {
          p_item_id: string;
          p_movement_type: string;
          p_quantity: number;
          p_reason?: string | null;
          p_notes?: string | null;
          p_unit_cost_minor?: number | null;
          p_reference_type?: string;
          p_reference_id?: string | null;
        };
        Returns: Database["public"]["Tables"]["inventory_movements"]["Row"];
      };
      create_purchase_order: {
        Args: {
          p_facility_id: string;
          p_vendor_id: string;
          p_lines: unknown;
          p_order_date?: string | null;
          p_expected_delivery?: string | null;
          p_reference?: string | null;
          p_notes?: string | null;
          p_invoice_path?: string | null;
        };
        Returns: string;
      };
      update_purchase_order: {
        Args: {
          p_po_id: string;
          p_lines?: unknown;
          p_expected_delivery?: string | null;
          p_reference?: string | null;
          p_notes?: string | null;
          p_invoice_path?: string | null;
        };
        Returns: undefined;
      };
      place_purchase_order: {
        Args: { p_po_id: string };
        Returns: undefined;
      };
      receive_purchase_order: {
        Args: { p_po_id: string; p_receipts: unknown };
        Returns: undefined;
      };
      cancel_purchase_order: {
        Args: { p_po_id: string; p_reason: string };
        Returns: undefined;
      };
      record_purchase_payment: {
        Args: {
          p_po_id: string;
          p_amount_minor: number;
          p_paid_on?: string | null;
          p_payment_method?: string | null;
          p_reference?: string | null;
          p_note?: string | null;
        };
        Returns: undefined;
      };
      get_inventory_overview: {
        Args: { p_facility_id: string };
        Returns: Record<string, unknown>;
      };
      list_inventory_items: {
        Args: {
          p_facility_id: string;
          p_search?: string | null;
          p_category_id?: string | null;
          p_status?: string | null;
          p_stock_status?: string | null;
          p_vendor_id?: string | null;
          p_sort?: string;
          p_limit?: number;
          p_offset?: number;
        };
        Returns: {
          id: string;
          name: string;
          sku: string;
          brand: string | null;
          category_id: string | null;
          category_name: string | null;
          unit: string;
          current_stock: number;
          reorder_level: number;
          unit_cost_minor: number;
          inventory_value_minor: number;
          status: "ACTIVE" | "INACTIVE";
          stock_status: "IN_STOCK" | "LOW_STOCK" | "OUT_OF_STOCK";
          preferred_vendor_id: string | null;
          preferred_vendor_name: string | null;
          image_path: string | null;
          updated_at: string | null;
          total_count: number;
        }[];
      };
      get_inventory_item: {
        Args: { p_item_id: string };
        Returns: Record<string, unknown>;
      };
      list_stock_movements: {
        Args: {
          p_facility_id: string;
          p_movement_type?: string | null;
          p_item_id?: string | null;
          p_from?: string | null;
          p_to?: string | null;
          p_performed_by?: string | null;
          p_limit?: number;
          p_offset?: number;
        };
        Returns: {
          id: string;
          created_at: string;
          movement_type: "STOCK_IN" | "STOCK_OUT" | "ADJUSTMENT" | "PURCHASE_RECEIVED" | "RETURN";
          item_id: string;
          item_name: string;
          quantity: number;
          balance_after: number;
          unit_cost_minor: number | null;
          reason: string | null;
          notes: string | null;
          reference_type: string | null;
          reference_id: string | null;
          reference_label: string | null;
          performed_by: string | null;
          performed_by_name: string | null;
          total_count: number;
        }[];
      };
      list_vendors: {
        Args: {
          p_facility_id: string;
          p_search?: string | null;
          p_status?: string | null;
          p_limit?: number;
          p_offset?: number;
        };
        Returns: {
          id: string;
          name: string;
          contact_person: string | null;
          phone: string | null;
          email: string | null;
          status: "ACTIVE" | "INACTIVE";
          po_count: number;
          total_purchases_minor: number;
          outstanding_minor: number;
          total_count: number;
        }[];
      };
      get_vendor: {
        Args: { p_vendor_id: string };
        Returns: Record<string, unknown>;
      };
      list_purchase_orders: {
        Args: {
          p_facility_id: string;
          p_vendor_id?: string | null;
          p_status?: string | null;
          p_payment_status?: string | null;
          p_from?: string | null;
          p_to?: string | null;
          p_limit?: number;
          p_offset?: number;
        };
        Returns: {
          id: string;
          po_number: string;
          vendor_id: string;
          vendor_name: string;
          order_date: string;
          expected_delivery: string | null;
          status: "DRAFT" | "ORDERED" | "PARTIALLY_RECEIVED" | "RECEIVED" | "CANCELLED";
          total_minor: number;
          amount_paid_minor: number;
          payment_status: string;
          item_count: number;
          total_count: number;
        }[];
      };
      get_purchase_order: {
        Args: { p_po_id: string };
        Returns: Record<string, unknown>;
      };
      list_inventory_categories: {
        Args: { p_facility_id: string };
        Returns: {
          id: string;
          name: string;
          description: string | null;
          is_active: boolean;
          sort_order: number;
          item_count: number;
          inventory_value_minor: number;
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