/* eslint-disable */
// AUTO-GENERATED — DO NOT EDIT
// Run migrations to regenerate.

export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.18"
  }
  public: {
    Tables: {
      admin_permissions: {
        Row: {
          code: string
          description: string
        }
        Insert: {
          code: string
          description: string
        }
        Update: {
          code?: string
          description?: string
        }
        Relationships: []
      }
      admin_role_permissions: {
        Row: {
          permission_code: string
          role_code: string
        }
        Insert: {
          permission_code: string
          role_code: string
        }
        Update: {
          permission_code?: string
          role_code?: string
        }
        Relationships: [
          {
            foreignKeyName: "admin_role_permissions_permission_code_fkey"
            columns: ["permission_code"]
            isOneToOne: false
            referencedRelation: "admin_permissions"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "admin_role_permissions_role_code_fkey"
            columns: ["role_code"]
            isOneToOne: false
            referencedRelation: "admin_roles"
            referencedColumns: ["code"]
          },
        ]
      }
      admin_roles: {
        Row: {
          code: string
          description: string | null
          name_ar: string
          name_fr: string
        }
        Insert: {
          code: string
          description?: string | null
          name_ar: string
          name_fr: string
        }
        Update: {
          code?: string
          description?: string | null
          name_ar?: string
          name_fr?: string
        }
        Relationships: []
      }
      admin_users: {
        Row: {
          active: boolean
          created_at: string
          created_by: string | null
          display_name: string
          email: string | null
          last_seen_at: string | null
          role_code: string
          user_id: string
        }
        Insert: {
          active?: boolean
          created_at?: string
          created_by?: string | null
          display_name?: string
          email?: string | null
          last_seen_at?: string | null
          role_code: string
          user_id: string
        }
        Update: {
          active?: boolean
          created_at?: string
          created_by?: string | null
          display_name?: string
          email?: string | null
          last_seen_at?: string | null
          role_code?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "admin_users_role_code_fkey"
            columns: ["role_code"]
            isOneToOne: false
            referencedRelation: "admin_roles"
            referencedColumns: ["code"]
          },
        ]
      }
      audit_logs: {
        Row: {
          action: string
          actor_id: string | null
          after_data: Json | null
          before_data: Json | null
          created_at: string
          entity_id: string | null
          entity_type: string
          id: number
          reason: string | null
        }
        Insert: {
          action: string
          actor_id?: string | null
          after_data?: Json | null
          before_data?: Json | null
          created_at?: string
          entity_id?: string | null
          entity_type: string
          id?: never
          reason?: string | null
        }
        Update: {
          action?: string
          actor_id?: string | null
          after_data?: Json | null
          before_data?: Json | null
          created_at?: string
          entity_id?: string | null
          entity_type?: string
          id?: never
          reason?: string | null
        }
        Relationships: []
      }
      vehicles: {
        Row: {
          category: string
          color: string
          created_at: string
          driver_id: string
          id: string
          is_primary: boolean
          make: string
          model: string
          plate: string
          seats: number
          status: string
          suspended_reason: string | null
          updated_at: string
          year: number | null
        }
        Insert: never
        Update: never
        Relationships: []
      }
      notification_broadcasts: {
        Row: {
          audience: string
          body: string
          created_at: string
          created_by: string | null
          id: string
          kind: string
          recipients: number
          title: string
        }
        Insert: never
        Update: never
        Relationships: []
      }
      support_tickets: {
        Row: { category: string; created_at: string; id: string; message: string; ride_id: string | null; status: string; user_id: string }
        Insert: never
        Update: never
        Relationships: []
      }
      sos_alerts: {
        Row: { created_at: string; id: string; lat: number | null; lng: number | null; ride_id: string | null; status: string; user_id: string }
        Insert: never
        Update: never
        Relationships: []
      }
      app_settings: {
        Row: { key: string; updated_at: string; updated_by: string | null; value: Json }
        Insert: never
        Update: never
        Relationships: []
      }
      delivery_orders: {
        Row: {
          accepted_at: string | null
          city: string
          created_at: string
          delivered_at: string | null
          delivery_fee: number
          dest_label: string
          dest_lat: number
          dest_lng: number
          distance_km: number
          driver_id: string | null
          expires_at: string
          id: string
          package_description: string
          passenger_id: string
          payment_method: string
          picked_up_at: string | null
          pickup_label: string
          pickup_lat: number
          pickup_lng: number
          recipient_name: string
          recipient_phone: string
          sender_note: string | null
          status: string
          updated_at: string
          vehicle: string
        }
        Insert: never
        Update: never
        Relationships: []
      }
      driver_documents: {
        Row: {
          doc_type: string
          driver_id: string
          id: string
          mime_type: string
          reason: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          status: string
          storage_path: string
          uploaded_at: string
        }
        Insert: {
          doc_type: string
          driver_id: string
          id?: string
          mime_type?: string
          reason?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string
          storage_path: string
          uploaded_at?: string
        }
        Update: {
          doc_type?: string
          driver_id?: string
          id?: string
          mime_type?: string
          reason?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string
          storage_path?: string
          uploaded_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "driver_documents_driver_id_fkey"
            columns: ["driver_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      offers: {
        Row: {
          created_at: string
          driver_id: string
          id: string
          kind: string
          price: number
          request_id: string
          status: string
        }
        Insert: {
          created_at?: string
          driver_id: string
          id?: string
          kind?: string
          price: number
          request_id: string
          status?: string
        }
        Update: {
          created_at?: string
          driver_id?: string
          id?: string
          kind?: string
          price?: number
          request_id?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "offers_driver_id_fkey"
            columns: ["driver_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "offers_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "ride_requests"
            referencedColumns: ["id"]
          },
        ]
      }
      otp_codes: {
        Row: {
          code: string
          created_at: string
          expires_at: string
          phone: string
        }
        Insert: {
          code: string
          created_at?: string
          expires_at: string
          phone: string
        }
        Update: {
          code?: string
          created_at?: string
          expires_at?: string
          phone?: string
        }
        Relationships: []
      }
      pricing_versions: {
        Row: {
          config: Json
          created_at: string
          created_by: string | null
          effective_at: string | null
          id: string
          note: string | null
          published_at: string | null
          published_by: string | null
          restored_from: string | null
          status: string
          version: number
        }
        Insert: {
          config: Json
          created_at?: string
          created_by?: string | null
          effective_at?: string | null
          id?: string
          note?: string | null
          published_at?: string | null
          published_by?: string | null
          restored_from?: string | null
          status?: string
          version?: never
        }
        Update: {
          config?: Json
          created_at?: string
          created_by?: string | null
          effective_at?: string | null
          id?: string
          note?: string | null
          published_at?: string | null
          published_by?: string | null
          restored_from?: string | null
          status?: string
          version?: never
        }
        Relationships: [
          {
            foreignKeyName: "pricing_versions_restored_from_fkey"
            columns: ["restored_from"]
            isOneToOne: false
            referencedRelation: "pricing_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      profiles: {
        Row: {
          account_status: string
          city: string
          created_at: string
          current_lat: number | null
          current_lng: number | null
          driver_status: string
          id: string
          is_online: boolean
          language: string
          location_updated_at: string | null
          name: string
          phone: string | null
          rating_avg: number
          rating_count: number
          role: string
          status_reason: string | null
          trips_count: number
          updated_at: string
          vehicle_color: string | null
          vehicle_make: string | null
          vehicle_model: string | null
          vehicle_plate: string | null
        }
        Insert: {
          account_status?: string
          city?: string
          created_at?: string
          current_lat?: number | null
          current_lng?: number | null
          driver_status?: string
          id: string
          is_online?: boolean
          language?: string
          location_updated_at?: string | null
          name?: string
          phone?: string | null
          rating_avg?: number
          rating_count?: number
          role?: string
          status_reason?: string | null
          trips_count?: number
          updated_at?: string
          vehicle_color?: string | null
          vehicle_make?: string | null
          vehicle_model?: string | null
          vehicle_plate?: string | null
        }
        Update: {
          account_status?: string
          city?: string
          created_at?: string
          current_lat?: number | null
          current_lng?: number | null
          driver_status?: string
          id?: string
          is_online?: boolean
          language?: string
          location_updated_at?: string | null
          name?: string
          phone?: string | null
          rating_avg?: number
          rating_count?: number
          role?: string
          status_reason?: string | null
          trips_count?: number
          updated_at?: string
          vehicle_color?: string | null
          vehicle_make?: string | null
          vehicle_model?: string | null
          vehicle_plate?: string | null
        }
        Relationships: []
      }
      ratings: {
        Row: {
          comment: string | null
          created_at: string
          id: string
          ratee_id: string
          rater_id: string
          ride_id: string
          stars: number
        }
        Insert: {
          comment?: string | null
          created_at?: string
          id?: string
          ratee_id: string
          rater_id: string
          ride_id: string
          stars: number
        }
        Update: {
          comment?: string | null
          created_at?: string
          id?: string
          ratee_id?: string
          rater_id?: string
          ride_id?: string
          stars?: number
        }
        Relationships: [
          {
            foreignKeyName: "ratings_ratee_id_fkey"
            columns: ["ratee_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ratings_rater_id_fkey"
            columns: ["rater_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ratings_ride_id_fkey"
            columns: ["ride_id"]
            isOneToOne: false
            referencedRelation: "rides"
            referencedColumns: ["id"]
          },
        ]
      }
      ride_messages: {
        Row: {
          body: string
          created_at: string
          id: string
          request_id: string
          sender_id: string
        }
        Insert: {
          body: string
          created_at?: string
          id?: string
          request_id: string
          sender_id: string
        }
        Update: {
          body?: string
          created_at?: string
          id?: string
          request_id?: string
          sender_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "ride_messages_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "ride_requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ride_messages_sender_id_fkey"
            columns: ["sender_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      ride_requests: {
        Row: {
          city: string
          created_at: string
          dest_label: string
          dest_lat: number
          dest_lng: number
          discount: number
          distance_km: number
          estimated_fare: number | null
          expires_at: string
          id: string
          passenger_id: string
          pickup_label: string
          pickup_lat: number
          pickup_lng: number
          price_before_discount: number | null
          pricing_version_id: string | null
          proposed_fare: number
          status: string
          vehicle: string
          women_only: boolean
        }
        Insert: {
          city?: string
          created_at?: string
          dest_label: string
          dest_lat: number
          dest_lng: number
          discount?: number
          distance_km: number
          estimated_fare?: number | null
          expires_at?: string
          id?: string
          passenger_id: string
          pickup_label: string
          pickup_lat: number
          pickup_lng: number
          price_before_discount?: number | null
          pricing_version_id?: string | null
          proposed_fare: number
          status?: string
          vehicle: string
          women_only?: boolean
        }
        Update: {
          city?: string
          created_at?: string
          dest_label?: string
          dest_lat?: number
          dest_lng?: number
          discount?: number
          distance_km?: number
          estimated_fare?: number | null
          expires_at?: string
          id?: string
          passenger_id?: string
          pickup_label?: string
          pickup_lat?: number
          pickup_lng?: number
          price_before_discount?: number | null
          pricing_version_id?: string | null
          proposed_fare?: number
          status?: string
          vehicle?: string
          women_only?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "ride_requests_passenger_id_fkey"
            columns: ["passenger_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ride_requests_pricing_version_id_fkey"
            columns: ["pricing_version_id"]
            isOneToOne: false
            referencedRelation: "pricing_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      ride_status_history: {
        Row: {
          actor_id: string | null
          created_at: string
          id: number
          note: string | null
          ride_id: string
          status: string
        }
        Insert: {
          actor_id?: string | null
          created_at?: string
          id?: never
          note?: string | null
          ride_id: string
          status: string
        }
        Update: {
          actor_id?: string | null
          created_at?: string
          id?: never
          note?: string | null
          ride_id?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "ride_status_history_ride_id_fkey"
            columns: ["ride_id"]
            isOneToOne: false
            referencedRelation: "rides"
            referencedColumns: ["id"]
          },
        ]
      }
      rides: {
        Row: {
          cancel_reason: string | null
          cancelled_by: string | null
          city: string
          commission: number | null
          completed_at: string | null
          created_at: string
          dest_label: string
          dest_lat: number
          dest_lng: number
          distance_km: number | null
          driver_id: string
          driver_net: number | null
          estimated_fare: number | null
          fare: number
          id: string
          passenger_id: string
          pickup_label: string
          pickup_lat: number
          pickup_lng: number
          pricing_snapshot: Json | null
          pricing_version_id: string | null
          request_id: string
          started_at: string | null
          status: string
          vehicle: string
        }
        Insert: {
          cancel_reason?: string | null
          cancelled_by?: string | null
          city?: string
          commission?: number | null
          completed_at?: string | null
          created_at?: string
          dest_label: string
          dest_lat: number
          dest_lng: number
          distance_km?: number | null
          driver_id: string
          driver_net?: number | null
          estimated_fare?: number | null
          fare: number
          id?: string
          passenger_id: string
          pickup_label: string
          pickup_lat: number
          pickup_lng: number
          pricing_snapshot?: Json | null
          pricing_version_id?: string | null
          request_id: string
          started_at?: string | null
          status?: string
          vehicle: string
        }
        Update: {
          cancel_reason?: string | null
          cancelled_by?: string | null
          city?: string
          commission?: number | null
          completed_at?: string | null
          created_at?: string
          dest_label?: string
          dest_lat?: number
          dest_lng?: number
          distance_km?: number | null
          driver_id?: string
          driver_net?: number | null
          estimated_fare?: number | null
          fare?: number
          id?: string
          passenger_id?: string
          pickup_label?: string
          pickup_lat?: number
          pickup_lng?: number
          pricing_snapshot?: Json | null
          pricing_version_id?: string | null
          request_id?: string
          started_at?: string | null
          status?: string
          vehicle?: string
        }
        Relationships: [
          {
            foreignKeyName: "rides_cancelled_by_fkey"
            columns: ["cancelled_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "rides_driver_id_fkey"
            columns: ["driver_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "rides_passenger_id_fkey"
            columns: ["passenger_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "rides_pricing_version_id_fkey"
            columns: ["pricing_version_id"]
            isOneToOne: false
            referencedRelation: "pricing_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "rides_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "ride_requests"
            referencedColumns: ["id"]
          },
        ]
      }
      transactions: {
        Row: {
          amount: number
          created_at: string
          created_by: string | null
          id: string
          kind: string
          label: string | null
          method: string
          ride_id: string | null
          user_id: string
        }
        Insert: {
          amount: number
          created_at?: string
          created_by?: string | null
          id?: string
          kind: string
          label?: string | null
          method?: string
          ride_id?: string | null
          user_id: string
        }
        Update: {
          amount?: number
          created_at?: string
          created_by?: string | null
          id?: string
          kind?: string
          label?: string | null
          method?: string
          ride_id?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "transactions_ride_id_fkey"
            columns: ["ride_id"]
            isOneToOne: false
            referencedRelation: "rides"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "transactions_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      accept_offer: { Args: { p_offer_id: string }; Returns: string }
      active_pricing: {
        Args: never
        Returns: {
          config: Json
          created_at: string
          created_by: string | null
          effective_at: string | null
          id: string
          note: string | null
          published_at: string | null
          published_by: string | null
          restored_from: string | null
          status: string
          version: number
        }
        SetofOptions: {
          from: "*"
          to: "pricing_versions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      admin_adjust_ride: {
        Args: { p_amount: number; p_reason: string; p_ride_id: string }
        Returns: undefined
      }
      admin_cancel_ride: {
        Args: { p_reason: string; p_ride_id: string }
        Returns: undefined
      }
      admin_cancel_scheduled_pricing: {
        Args: { p_id: string }
        Returns: undefined
      }
      admin_me: { Args: never; Returns: Json }
      admin_overview: { Args: { p_from: string; p_to: string }; Returns: Json }
      admin_publish_pricing: {
        Args: { p_effective_at?: string; p_id: string }
        Returns: undefined
      }
      admin_restore_pricing: {
        Args: { p_id: string; p_note?: string }
        Returns: string
      }
      admin_set_ticket_status: {
        Args: { p_id: string; p_status: string }
        Returns: undefined
      }
      admin_set_sos_status: {
        Args: { p_id: string; p_status: string }
        Returns: undefined
      }
      admin_set_vehicle_status: {
        Args: { p_id: string; p_reason?: string; p_status: string }
        Returns: undefined
      }
      admin_send_broadcast: {
        Args: { p_audience: string; p_body: string; p_kind: string; p_title: string }
        Returns: number
      }
      admin_set_setting: { Args: { p_key: string; p_value: Json }; Returns: undefined }
      admin_report_summary: { Args: { p_from: string; p_to: string }; Returns: Json }
      admin_driver_phone_status: {
        Args: { p_ids: string[] }
        Returns: { user_id: string; phone_verified: boolean }[]
      }
      admin_review_document: {
        Args: { p_id: string; p_reason?: string; p_status: string }
        Returns: undefined
      }
      admin_save_pricing: {
        Args: {
          p_config: Json
          p_effective_at?: string
          p_note?: string
          p_publish?: boolean
        }
        Returns: string
      }
      admin_set_account_status: {
        Args: { p_reason?: string; p_status: string; p_user: string }
        Returns: undefined
      }
      admin_set_admin: {
        Args: {
          p_active?: boolean
          p_display_name?: string
          p_email: string
          p_role: string
        }
        Returns: undefined
      }
      admin_set_driver_status: {
        Args: { p_reason?: string; p_status: string; p_user: string }
        Returns: undefined
      }
      admin_simulate_fare: {
        Args: {
          p_at: string
          p_city: string
          p_commission_pct?: number
          p_config: Json
          p_distance: number
          p_vehicle: string
        }
        Returns: Json
      }
      assert_active_user: {
        Args: never
        Returns: {
          account_status: string
          city: string
          created_at: string
          current_lat: number | null
          current_lng: number | null
          driver_status: string
          id: string
          is_online: boolean
          language: string
          location_updated_at: string | null
          name: string
          phone: string | null
          rating_avg: number
          rating_count: number
          role: string
          status_reason: string | null
          trips_count: number
          updated_at: string
          vehicle_color: string | null
          vehicle_make: string | null
          vehicle_model: string | null
          vehicle_plate: string | null
        }
        SetofOptions: {
          from: "*"
          to: "profiles"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      cancel_request: { Args: { p_request_id: string }; Returns: undefined }
      cancel_ride: {
        Args: { p_reason?: string; p_ride_id: string }
        Returns: undefined
      }
      commission_for: {
        Args: { c: Json; p_fare: number; p_vehicle: string }
        Returns: number
      }
      compute_fare: {
        Args: {
          c: Json
          p_at: string
          p_city: string
          p_commission_override?: number
          p_distance: number
          p_vehicle: string
        }
        Returns: Json
      }
      create_request: {
        Args: {
          p_city?: string
          p_dest_label: string
          p_dest_lat: number
          p_dest_lng: number
          p_distance_km: number
          p_pickup_label: string
          p_pickup_lat: number
          p_pickup_lng: number
          p_proposed_fare: number
          p_vehicle: string
          p_women_only?: boolean
        }
        Returns: string
      }
      driver_offer_preview: {
        Args: { p_price: number; p_request_id: string }
        Returns: Json
      }
      expire_stale_requests: { Args: never; Returns: undefined }
      has_perm: { Args: { p_perm: string }; Returns: boolean }
      haversine_km: {
        Args: { lat1: number; lat2: number; lng1: number; lng2: number }
        Returns: number
      }
      is_admin: { Args: never; Returns: boolean }
      make_offer: {
        Args: { p_kind?: string; p_price: number; p_request_id: string }
        Returns: string
      }
      ping_location: {
        Args: { p_lat: number; p_lng: number }
        Returns: undefined
      }
      quote_fare: {
        Args: {
          p_city?: string
          p_dest_lat: number
          p_dest_lng: number
          p_distance_km: number
          p_pickup_lat: number
          p_pickup_lng: number
          p_vehicle: string
        }
        Returns: Json
      }
      require_perm: { Args: { p_perm: string }; Returns: undefined }
      required_driver_documents: { Args: never; Returns: string[] }
      submit_driver_document: {
        Args: { p_mime?: string; p_path: string; p_type: string }
        Returns: {
          doc_type: string
          driver_id: string
          id: string
          mime_type: string
          reason: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          status: string
          storage_path: string
          uploaded_at: string
        }
        SetofOptions: {
          from: "*"
          to: "driver_documents"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      submit_rating: {
        Args: { p_comment?: string; p_ride_id: string; p_stars: number }
        Returns: undefined
      }
      trusted_distance: {
        Args: {
          p_client: number
          p_lat1: number
          p_lat2: number
          p_lng1: number
          p_lng2: number
        }
        Returns: number
      }
      update_ride: {
        Args: { p_ride_id: string; p_status: string }
        Returns: undefined
      }
      validate_pricing: { Args: { c: Json }; Returns: undefined }
      write_audit: {
        Args: {
          p_action: string
          p_after: Json
          p_before: Json
          p_entity_id: string
          p_entity_type: string
          p_reason: string
        }
        Returns: undefined
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {},
  },
} as const
