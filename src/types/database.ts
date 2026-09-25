// GERADO por npm run db:types a partir das migrations. Não editar manualmente.
export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[]

export type Database = {
  public: {
    Tables: {
      appointment_notes: {
        Row: {
          id: string
          barbershop_id: string
          appointment_id: string
          body: string
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          barbershop_id: string
          appointment_id: string
          body: string
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          barbershop_id?: string
          appointment_id?: string
          body?: string
          created_at?: string
          updated_at?: string
        }
        Relationships: [
          { foreignKeyName: "appointment_notes_barbershop_id_appointment_id_fkey"; columns: ["barbershop_id","appointment_id"]; isOneToOne: false; referencedRelation: "appointments"; referencedColumns: ["barbershop_id","id"] },
          { foreignKeyName: "appointment_notes_barbershop_id_fkey"; columns: ["barbershop_id"]; isOneToOne: false; referencedRelation: "barbershops"; referencedColumns: ["id"] }
        ]
      }
      appointments: {
        Row: {
          id: string
          barbershop_id: string
          customer_id: string
          professional_id: string
          service_id: string
          starts_at: string
          ends_at: string
          occupied_until: string
          status: Database['public']['Enums']['appointment_status']
          price_cents: number
          duration_minutes: number
          commission_percent: number
          source: string
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          barbershop_id: string
          customer_id: string
          professional_id: string
          service_id: string
          starts_at: string
          ends_at: string
          occupied_until: string
          status?: Database['public']['Enums']['appointment_status']
          price_cents: number
          duration_minutes: number
          commission_percent?: number
          source?: string
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          barbershop_id?: string
          customer_id?: string
          professional_id?: string
          service_id?: string
          starts_at?: string
          ends_at?: string
          occupied_until?: string
          status?: Database['public']['Enums']['appointment_status']
          price_cents?: number
          duration_minutes?: number
          commission_percent?: number
          source?: string
          created_at?: string
          updated_at?: string
        }
        Relationships: [
          { foreignKeyName: "appointments_barbershop_id_customer_id_fkey"; columns: ["barbershop_id","customer_id"]; isOneToOne: false; referencedRelation: "customers"; referencedColumns: ["barbershop_id","id"] },
          { foreignKeyName: "appointments_barbershop_id_fkey"; columns: ["barbershop_id"]; isOneToOne: false; referencedRelation: "barbershops"; referencedColumns: ["id"] },
          { foreignKeyName: "appointments_barbershop_id_professional_id_service_id_fkey"; columns: ["barbershop_id","professional_id","service_id"]; isOneToOne: false; referencedRelation: "professional_services"; referencedColumns: ["barbershop_id","professional_id","service_id"] }
        ]
      }
      audit_logs: {
        Row: {
          id: string
          barbershop_id: string
          actor_id: string | null
          action: string
          entity_table: string
          entity_id: string | null
          created_at: string
        }
        Insert: {
          id?: string
          barbershop_id: string
          actor_id?: string | null
          action: string
          entity_table: string
          entity_id?: string | null
          created_at?: string
        }
        Update: {
          id?: string
          barbershop_id?: string
          actor_id?: string | null
          action?: string
          entity_table?: string
          entity_id?: string | null
          created_at?: string
        }
        Relationships: [
          { foreignKeyName: "audit_logs_barbershop_id_fkey"; columns: ["barbershop_id"]; isOneToOne: false; referencedRelation: "barbershops"; referencedColumns: ["id"] }
        ]
      }
      barbershop_members: {
        Row: {
          id: string
          barbershop_id: string
          user_id: string
          role: Database['public']['Enums']['member_role']
          is_active: boolean
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          barbershop_id: string
          user_id: string
          role: Database['public']['Enums']['member_role']
          is_active?: boolean
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          barbershop_id?: string
          user_id?: string
          role?: Database['public']['Enums']['member_role']
          is_active?: boolean
          created_at?: string
          updated_at?: string
        }
        Relationships: [
          { foreignKeyName: "barbershop_members_barbershop_id_fkey"; columns: ["barbershop_id"]; isOneToOne: false; referencedRelation: "barbershops"; referencedColumns: ["id"] }
        ]
      }
      barbershops: {
        Row: {
          id: string
          name: string
          slug: string
          description: string
          phone: string | null
          whatsapp: string | null
          instagram: string | null
          address: string | null
          postal_code: string | null
          city: string | null
          state: string | null
          maps_url: string | null
          logo_path: string | null
          cover_path: string | null
          welcome_message: string
          theme: Database['public']['Enums']['theme_name']
          primary_color: string
          secondary_color: string
          timezone: string
          is_active: boolean
          is_published: boolean
          onboarding_step: number
          onboarding_completed_at: string | null
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          name: string
          slug: string
          description?: string
          phone?: string | null
          whatsapp?: string | null
          instagram?: string | null
          address?: string | null
          postal_code?: string | null
          city?: string | null
          state?: string | null
          maps_url?: string | null
          logo_path?: string | null
          cover_path?: string | null
          welcome_message?: string
          theme?: Database['public']['Enums']['theme_name']
          primary_color?: string
          secondary_color?: string
          timezone?: string
          is_active?: boolean
          is_published?: boolean
          onboarding_step?: number
          onboarding_completed_at?: string | null
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          name?: string
          slug?: string
          description?: string
          phone?: string | null
          whatsapp?: string | null
          instagram?: string | null
          address?: string | null
          postal_code?: string | null
          city?: string | null
          state?: string | null
          maps_url?: string | null
          logo_path?: string | null
          cover_path?: string | null
          welcome_message?: string
          theme?: Database['public']['Enums']['theme_name']
          primary_color?: string
          secondary_color?: string
          timezone?: string
          is_active?: boolean
          is_published?: boolean
          onboarding_step?: number
          onboarding_completed_at?: string | null
          created_at?: string
          updated_at?: string
        }
        Relationships: [
          { foreignKeyName: "barbershops_theme_fkey"; columns: ["theme"]; isOneToOne: false; referencedRelation: "themes"; referencedColumns: ["id"] }
        ]
      }
      blocked_times: {
        Row: {
          id: string
          barbershop_id: string
          professional_id: string | null
          starts_at: string
          ends_at: string
          reason: string
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          barbershop_id: string
          professional_id?: string | null
          starts_at: string
          ends_at: string
          reason: string
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          barbershop_id?: string
          professional_id?: string | null
          starts_at?: string
          ends_at?: string
          reason?: string
          created_at?: string
          updated_at?: string
        }
        Relationships: [
          { foreignKeyName: "blocked_times_barbershop_id_fkey"; columns: ["barbershop_id"]; isOneToOne: false; referencedRelation: "barbershops"; referencedColumns: ["id"] },
          { foreignKeyName: "blocked_times_barbershop_id_professional_id_fkey"; columns: ["barbershop_id","professional_id"]; isOneToOne: false; referencedRelation: "professionals"; referencedColumns: ["barbershop_id","id"] }
        ]
      }
      business_hours: {
        Row: {
          id: string
          barbershop_id: string
          weekday: number
          start_minute: number
          end_minute: number
        }
        Insert: {
          id?: string
          barbershop_id: string
          weekday: number
          start_minute: number
          end_minute: number
        }
        Update: {
          id?: string
          barbershop_id?: string
          weekday?: number
          start_minute?: number
          end_minute?: number
        }
        Relationships: [
          { foreignKeyName: "business_hours_barbershop_id_fkey"; columns: ["barbershop_id"]; isOneToOne: false; referencedRelation: "barbershops"; referencedColumns: ["id"] }
        ]
      }
      customer_notes: {
        Row: {
          id: string
          barbershop_id: string
          customer_id: string
          body: string
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          barbershop_id: string
          customer_id: string
          body: string
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          barbershop_id?: string
          customer_id?: string
          body?: string
          created_at?: string
          updated_at?: string
        }
        Relationships: [
          { foreignKeyName: "customer_notes_barbershop_id_customer_id_fkey"; columns: ["barbershop_id","customer_id"]; isOneToOne: false; referencedRelation: "customers"; referencedColumns: ["barbershop_id","id"] },
          { foreignKeyName: "customer_notes_barbershop_id_fkey"; columns: ["barbershop_id"]; isOneToOne: false; referencedRelation: "barbershops"; referencedColumns: ["id"] }
        ]
      }
      customers: {
        Row: {
          id: string
          barbershop_id: string
          user_id: string | null
          name: string
          phone: string
          email: string | null
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          barbershop_id: string
          user_id?: string | null
          name: string
          phone: string
          email?: string | null
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          barbershop_id?: string
          user_id?: string | null
          name?: string
          phone?: string
          email?: string | null
          created_at?: string
          updated_at?: string
        }
        Relationships: [
          { foreignKeyName: "customers_barbershop_id_fkey"; columns: ["barbershop_id"]; isOneToOne: false; referencedRelation: "barbershops"; referencedColumns: ["id"] }
        ]
      }
      notification_templates: {
        Row: {
          id: string
          barbershop_id: string
          event: string
          body: string
          enabled: boolean
          created_at: string
          updated_at: string
          meta_name: string | null
          meta_language: string
        }
        Insert: {
          id?: string
          barbershop_id: string
          event: string
          body: string
          enabled?: boolean
          created_at?: string
          updated_at?: string
          meta_name?: string | null
          meta_language?: string
        }
        Update: {
          id?: string
          barbershop_id?: string
          event?: string
          body?: string
          enabled?: boolean
          created_at?: string
          updated_at?: string
          meta_name?: string | null
          meta_language?: string
        }
        Relationships: [
          { foreignKeyName: "notification_templates_barbershop_id_fkey"; columns: ["barbershop_id"]; isOneToOne: false; referencedRelation: "barbershops"; referencedColumns: ["id"] }
        ]
      }
      notifications: {
        Row: {
          id: string
          barbershop_id: string
          appointment_id: string
          event: string
          scheduled_at: string
          status: string
          attempts: number
          deduplication_key: string
          created_at: string
          updated_at: string
          processing_started_at: string | null
        }
        Insert: {
          id?: string
          barbershop_id: string
          appointment_id: string
          event: string
          scheduled_at: string
          status?: string
          attempts?: number
          deduplication_key: string
          created_at?: string
          updated_at?: string
          processing_started_at?: string | null
        }
        Update: {
          id?: string
          barbershop_id?: string
          appointment_id?: string
          event?: string
          scheduled_at?: string
          status?: string
          attempts?: number
          deduplication_key?: string
          created_at?: string
          updated_at?: string
          processing_started_at?: string | null
        }
        Relationships: [
          { foreignKeyName: "notifications_barbershop_id_appointment_id_fkey"; columns: ["barbershop_id","appointment_id"]; isOneToOne: false; referencedRelation: "appointments"; referencedColumns: ["barbershop_id","id"] },
          { foreignKeyName: "notifications_barbershop_id_fkey"; columns: ["barbershop_id"]; isOneToOne: false; referencedRelation: "barbershops"; referencedColumns: ["id"] }
        ]
      }
      payments: {
        Row: {
          id: string
          barbershop_id: string
          appointment_id: string
          amount_cents: number
          method: Database['public']['Enums']['payment_method']
          paid_at: string
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          barbershop_id: string
          appointment_id: string
          amount_cents: number
          method: Database['public']['Enums']['payment_method']
          paid_at?: string
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          barbershop_id?: string
          appointment_id?: string
          amount_cents?: number
          method?: Database['public']['Enums']['payment_method']
          paid_at?: string
          created_at?: string
          updated_at?: string
        }
        Relationships: [
          { foreignKeyName: "payments_barbershop_id_appointment_id_fkey"; columns: ["barbershop_id","appointment_id"]; isOneToOne: true; referencedRelation: "appointments"; referencedColumns: ["barbershop_id","id"] },
          { foreignKeyName: "payments_barbershop_id_fkey"; columns: ["barbershop_id"]; isOneToOne: false; referencedRelation: "barbershops"; referencedColumns: ["id"] }
        ]
      }
      plans: {
        Row: {
          id: string
          name: string
          professional_limit: number | null
          features: Json
        }
        Insert: {
          id: string
          name: string
          professional_limit?: number | null
          features?: Json
        }
        Update: {
          id?: string
          name?: string
          professional_limit?: number | null
          features?: Json
        }
        Relationships: [

        ]
      }
      professional_schedules: {
        Row: {
          id: string
          barbershop_id: string
          professional_id: string
          weekday: number
          start_minute: number
          end_minute: number
        }
        Insert: {
          id?: string
          barbershop_id: string
          professional_id: string
          weekday: number
          start_minute: number
          end_minute: number
        }
        Update: {
          id?: string
          barbershop_id?: string
          professional_id?: string
          weekday?: number
          start_minute?: number
          end_minute?: number
        }
        Relationships: [
          { foreignKeyName: "professional_schedules_barbershop_id_fkey"; columns: ["barbershop_id"]; isOneToOne: false; referencedRelation: "barbershops"; referencedColumns: ["id"] },
          { foreignKeyName: "professional_schedules_barbershop_id_professional_id_fkey"; columns: ["barbershop_id","professional_id"]; isOneToOne: false; referencedRelation: "professionals"; referencedColumns: ["barbershop_id","id"] }
        ]
      }
      professional_services: {
        Row: {
          barbershop_id: string
          professional_id: string
          service_id: string
          is_enabled: boolean
        }
        Insert: {
          barbershop_id: string
          professional_id: string
          service_id: string
          is_enabled?: boolean
        }
        Update: {
          barbershop_id?: string
          professional_id?: string
          service_id?: string
          is_enabled?: boolean
        }
        Relationships: [
          { foreignKeyName: "professional_services_barbershop_id_fkey"; columns: ["barbershop_id"]; isOneToOne: false; referencedRelation: "barbershops"; referencedColumns: ["id"] },
          { foreignKeyName: "professional_services_barbershop_id_professional_id_fkey"; columns: ["barbershop_id","professional_id"]; isOneToOne: false; referencedRelation: "professionals"; referencedColumns: ["barbershop_id","id"] },
          { foreignKeyName: "professional_services_barbershop_id_service_id_fkey"; columns: ["barbershop_id","service_id"]; isOneToOne: false; referencedRelation: "services"; referencedColumns: ["barbershop_id","id"] }
        ]
      }
      professionals: {
        Row: {
          id: string
          barbershop_id: string
          member_id: string | null
          name: string
          phone: string | null
          email: string | null
          photo_path: string | null
          specialties: string
          status: Database['public']['Enums']['professional_status']
          commission_percent: number
          buffer_minutes: number
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          barbershop_id: string
          member_id?: string | null
          name: string
          phone?: string | null
          email?: string | null
          photo_path?: string | null
          specialties?: string
          status?: Database['public']['Enums']['professional_status']
          commission_percent?: number
          buffer_minutes?: number
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          barbershop_id?: string
          member_id?: string | null
          name?: string
          phone?: string | null
          email?: string | null
          photo_path?: string | null
          specialties?: string
          status?: Database['public']['Enums']['professional_status']
          commission_percent?: number
          buffer_minutes?: number
          created_at?: string
          updated_at?: string
        }
        Relationships: [
          { foreignKeyName: "professionals_barbershop_id_fkey"; columns: ["barbershop_id"]; isOneToOne: false; referencedRelation: "barbershops"; referencedColumns: ["id"] },
          { foreignKeyName: "professionals_barbershop_id_member_id_fkey"; columns: ["barbershop_id","member_id"]; isOneToOne: true; referencedRelation: "barbershop_members"; referencedColumns: ["barbershop_id","id"] }
        ]
      }
      profiles: {
        Row: {
          id: string
          full_name: string
          phone: string | null
          created_at: string
          updated_at: string
        }
        Insert: {
          id: string
          full_name?: string
          phone?: string | null
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          full_name?: string
          phone?: string | null
          created_at?: string
          updated_at?: string
        }
        Relationships: [

        ]
      }
      services: {
        Row: {
          id: string
          barbershop_id: string
          name: string
          description: string
          price_cents: number
          duration_minutes: number
          image_path: string | null
          category: string | null
          is_active: boolean
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          barbershop_id: string
          name: string
          description?: string
          price_cents: number
          duration_minutes: number
          image_path?: string | null
          category?: string | null
          is_active?: boolean
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          barbershop_id?: string
          name?: string
          description?: string
          price_cents?: number
          duration_minutes?: number
          image_path?: string | null
          category?: string | null
          is_active?: boolean
          created_at?: string
          updated_at?: string
        }
        Relationships: [
          { foreignKeyName: "services_barbershop_id_fkey"; columns: ["barbershop_id"]; isOneToOne: false; referencedRelation: "barbershops"; referencedColumns: ["id"] }
        ]
      }
      settings: {
        Row: {
          barbershop_id: string
          cancellation_hours: number
          booking_notice_minutes: number
          booking_horizon_days: number
          slot_minutes: number
          commissions_enabled: boolean
          accepted_payments: (Database['public']['Enums']['payment_method'])[]
          reminder_24h: boolean
          reminder_2h: boolean
          created_at: string
          updated_at: string
          bot_enabled: boolean
          bot_booking_enabled: boolean
          bot_welcome_message: string
          bot_menu_message: string
          bot_service_prompt: string
          bot_professional_prompt: string
          bot_date_prompt: string
          bot_slot_prompt: string
          bot_confirmation_message: string
          bot_handoff_message: string
        }
        Insert: {
          barbershop_id: string
          cancellation_hours?: number
          booking_notice_minutes?: number
          booking_horizon_days?: number
          slot_minutes?: number
          commissions_enabled?: boolean
          accepted_payments?: (Database['public']['Enums']['payment_method'])[]
          reminder_24h?: boolean
          reminder_2h?: boolean
          created_at?: string
          updated_at?: string
          bot_enabled?: boolean
          bot_booking_enabled?: boolean
          bot_welcome_message?: string
          bot_menu_message?: string
          bot_service_prompt?: string
          bot_professional_prompt?: string
          bot_date_prompt?: string
          bot_slot_prompt?: string
          bot_confirmation_message?: string
          bot_handoff_message?: string
        }
        Update: {
          barbershop_id?: string
          cancellation_hours?: number
          booking_notice_minutes?: number
          booking_horizon_days?: number
          slot_minutes?: number
          commissions_enabled?: boolean
          accepted_payments?: (Database['public']['Enums']['payment_method'])[]
          reminder_24h?: boolean
          reminder_2h?: boolean
          created_at?: string
          updated_at?: string
          bot_enabled?: boolean
          bot_booking_enabled?: boolean
          bot_welcome_message?: string
          bot_menu_message?: string
          bot_service_prompt?: string
          bot_professional_prompt?: string
          bot_date_prompt?: string
          bot_slot_prompt?: string
          bot_confirmation_message?: string
          bot_handoff_message?: string
        }
        Relationships: [
          { foreignKeyName: "settings_barbershop_id_fkey"; columns: ["barbershop_id"]; isOneToOne: true; referencedRelation: "barbershops"; referencedColumns: ["id"] }
        ]
      }
      subscriptions: {
        Row: {
          id: string
          barbershop_id: string
          plan: string
          status: Database['public']['Enums']['subscription_status']
          started_at: string
          expires_at: string | null
          trial_ends_at: string | null
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          barbershop_id: string
          plan: string
          status?: Database['public']['Enums']['subscription_status']
          started_at?: string
          expires_at?: string | null
          trial_ends_at?: string | null
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          barbershop_id?: string
          plan?: string
          status?: Database['public']['Enums']['subscription_status']
          started_at?: string
          expires_at?: string | null
          trial_ends_at?: string | null
          created_at?: string
          updated_at?: string
        }
        Relationships: [
          { foreignKeyName: "subscriptions_barbershop_id_fkey"; columns: ["barbershop_id"]; isOneToOne: true; referencedRelation: "barbershops"; referencedColumns: ["id"] },
          { foreignKeyName: "subscriptions_plan_fkey"; columns: ["plan"]; isOneToOne: false; referencedRelation: "plans"; referencedColumns: ["id"] }
        ]
      }
      themes: {
        Row: {
          id: Database['public']['Enums']['theme_name']
          name: string
        }
        Insert: {
          id: Database['public']['Enums']['theme_name']
          name: string
        }
        Update: {
          id?: Database['public']['Enums']['theme_name']
          name?: string
        }
        Relationships: [

        ]
      }
      whatsapp_connections: {
        Row: {
          barbershop_id: string
          phone: string | null
          status: string
          phone_number_id: string | null
          business_account_id: string | null
          connected_at: string | null
          created_at: string
          updated_at: string
        }
        Insert: {
          barbershop_id: string
          phone?: string | null
          status?: string
          phone_number_id?: string | null
          business_account_id?: string | null
          connected_at?: string | null
          created_at?: string
          updated_at?: string
        }
        Update: {
          barbershop_id?: string
          phone?: string | null
          status?: string
          phone_number_id?: string | null
          business_account_id?: string | null
          connected_at?: string | null
          created_at?: string
          updated_at?: string
        }
        Relationships: [
          { foreignKeyName: "whatsapp_connections_barbershop_id_fkey"; columns: ["barbershop_id"]; isOneToOne: true; referencedRelation: "barbershops"; referencedColumns: ["id"] }
        ]
      }
      whatsapp_messages: {
        Row: {
          id: string
          barbershop_id: string
          customer_id: string | null
          appointment_id: string | null
          provider_message_id: string | null
          direction: string
          status: string
          body: string
          created_at: string
          updated_at: string
          sender_phone: string | null
        }
        Insert: {
          id?: string
          barbershop_id: string
          customer_id?: string | null
          appointment_id?: string | null
          provider_message_id?: string | null
          direction: string
          status: string
          body: string
          created_at?: string
          updated_at?: string
          sender_phone?: string | null
        }
        Update: {
          id?: string
          barbershop_id?: string
          customer_id?: string | null
          appointment_id?: string | null
          provider_message_id?: string | null
          direction?: string
          status?: string
          body?: string
          created_at?: string
          updated_at?: string
          sender_phone?: string | null
        }
        Relationships: [
          { foreignKeyName: "whatsapp_messages_barbershop_id_appointment_id_fkey"; columns: ["barbershop_id","appointment_id"]; isOneToOne: false; referencedRelation: "appointments"; referencedColumns: ["barbershop_id","id"] },
          { foreignKeyName: "whatsapp_messages_barbershop_id_customer_id_fkey"; columns: ["barbershop_id","customer_id"]; isOneToOne: false; referencedRelation: "customers"; referencedColumns: ["barbershop_id","id"] },
          { foreignKeyName: "whatsapp_messages_barbershop_id_fkey"; columns: ["barbershop_id"]; isOneToOne: false; referencedRelation: "barbershops"; referencedColumns: ["id"] }
        ]
      }
    }
    Views: { [_ in never]: never }
    Functions: {
      admin_create_shop: { Args: { shop_name: string; owner_email: string; selected_plan?: string }; Returns: string }
      admin_overview: { Args: { [key: string]: never }; Returns: Json }
      admin_shops: { Args: { [key: string]: never }; Returns: Json }
      admin_update_shop: { Args: { tenant: string; selected_plan: string; selected_status: Database['public']['Enums']['subscription_status'] }; Returns: undefined }
      agenda: { Args: { tenant: string; from_date: string; until_date: string }; Returns: Json }
      appointment_action: { Args: { appointment: string; new_status: Database['public']['Enums']['appointment_status']; method?: Database['public']['Enums']['payment_method'] }; Returns: undefined }
      appointment_payment_methods: { Args: { tenant: string }; Returns: Json }
      available_slots: { Args: { tenant: string; service: string; booking_date: string; professional?: string }; Returns: Json }
      book_appointment: { Args: { tenant: string; service: string; professional: string; starts: string; customer_name: string; customer_phone: string; customer?: string; existing_appointment?: string }; Returns: string }
      complete_onboarding: { Args: { tenant: string }; Returns: undefined }
      customer_history: { Args: { tenant: string; customer: string }; Returns: Json }
      customer_summary: { Args: { tenant: string }; Returns: Json }
      end_support: { Args: { tenant: string }; Returns: undefined }
      finance_report: { Args: { tenant: string; from_date: string; until_date: string }; Returns: Json }
      manage_block: { Args: { tenant: string; starts: string; ends: string; reason: string; professional?: string; block_id?: string }; Returns: undefined }
      manage_member: { Args: { tenant: string; member_email: string; member_role: Database['public']['Enums']['member_role']; enabled?: boolean }; Returns: undefined }
      my_commissions: { Args: { tenant: string; from_date: string; until_date: string }; Returns: Json }
      plan_details: { Args: { tenant: string }; Returns: Json }
      professional_service_ids: { Args: { tenant: string; professional: string }; Returns: Json }
      public_catalog: { Args: { shop_slug: string }; Returns: Json }
      session_context: { Args: { [key: string]: never }; Returns: Json }
      set_professional_services: { Args: { tenant: string; professional: string; service_ids: (string)[] }; Returns: undefined }
      start_support: { Args: { tenant: string; reason: string }; Returns: string }
      team_members: { Args: { tenant: string }; Returns: Json }
      wa_begin: { Args: { tenant: string; state_hash: string }; Returns: undefined }
      wa_bot_reply: { Args: { inbox: string; public_url: string }; Returns: string }
      wa_claim: { Args: { [key: string]: never }; Returns: Json }
      wa_claim_notifications: { Args: { [key: string]: never }; Returns: Json }
      wa_connection_error: { Args: { tenant: string }; Returns: undefined }
      wa_consume: { Args: { state: string }; Returns: string }
      wa_delivery_allowed: { Args: { tenant: string; phone: string; ciphertext: string; delivery: string; notification?: boolean }; Returns: boolean }
      wa_disconnect: { Args: { tenant: string }; Returns: undefined }
      wa_finish: { Args: { inbox_id: string; successful: boolean }; Returns: undefined }
      wa_finish_notification: { Args: { notification: string; successful: boolean }; Returns: undefined }
      wa_receive: { Args: { phone_id: string; provider_id: string; sender_phone: string; message_body: string }; Returns: undefined }
      wa_registration_pin: { Args: { tenant: string; phone: string; ciphertext: string }; Returns: string }
      wa_save: { Args: { tenant: string; phone_id: string; account_id: string; ciphertext: string }; Returns: undefined }
    }
    Enums: {
      appointment_status: "scheduled" | "confirmed" | "in_progress" | "completed" | "cancelled" | "no_show"
      member_role: "owner" | "manager" | "professional" | "receptionist"
      payment_method: "pix" | "cash" | "debit" | "credit" | "other"
      professional_status: "available" | "vacation" | "absent" | "disabled"
      subscription_status: "trial" | "active" | "past_due" | "cancelled" | "blocked"
      theme_name: "premium" | "classic" | "modern"
    }
    CompositeTypes: { [_ in never]: never }
  }
}
