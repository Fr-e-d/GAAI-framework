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
    PostgrestVersion: "14.1"
  }
  public: {
    Tables: {
      bookings: {
        Row: {
          cal_booking_id: string | null
          cal_meeting_url: string | null
          confirmed_at: string | null
          created_at: string | null
          description: string | null
          duration_min: number | null
          end_at: string | null
          expert_id: string | null
          gcal_event_id: string | null
          held_until: string | null
          id: string
          match_id: string | null
          meeting_url: string | null
          prep_token: string | null
          prospect_email: string | null
          prospect_id: string | null
          prospect_name: string | null
          reminder_h1_sent_at: string | null
          reminder_j1_sent_at: string | null
          scheduled_at: string | null
          start_at: string | null
          status: string | null
        }
        Insert: {
          cal_booking_id?: string | null
          cal_meeting_url?: string | null
          confirmed_at?: string | null
          created_at?: string | null
          description?: string | null
          duration_min?: number | null
          end_at?: string | null
          expert_id?: string | null
          gcal_event_id?: string | null
          held_until?: string | null
          id?: string
          match_id?: string | null
          meeting_url?: string | null
          prep_token?: string | null
          prospect_email?: string | null
          prospect_id?: string | null
          prospect_name?: string | null
          reminder_h1_sent_at?: string | null
          reminder_j1_sent_at?: string | null
          scheduled_at?: string | null
          start_at?: string | null
          status?: string | null
        }
        Update: {
          cal_booking_id?: string | null
          cal_meeting_url?: string | null
          confirmed_at?: string | null
          created_at?: string | null
          description?: string | null
          duration_min?: number | null
          end_at?: string | null
          expert_id?: string | null
          gcal_event_id?: string | null
          held_until?: string | null
          id?: string
          match_id?: string | null
          meeting_url?: string | null
          prep_token?: string | null
          prospect_email?: string | null
          prospect_id?: string | null
          prospect_name?: string | null
          reminder_h1_sent_at?: string | null
          reminder_j1_sent_at?: string | null
          scheduled_at?: string | null
          start_at?: string | null
          status?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "bookings_expert_id_fkey"
            columns: ["expert_id"]
            isOneToOne: false
            referencedRelation: "experts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bookings_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: false
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bookings_prospect_id_fkey"
            columns: ["prospect_id"]
            isOneToOne: false
            referencedRelation: "prospects"
            referencedColumns: ["id"]
          },
        ]
      }
      call_experience_surveys: {
        Row: {
          booking_id: string | null
          comment: string | null
          id: string
          prospect_id: string | null
          score: number | null
          submitted_at: string | null
        }
        Insert: {
          booking_id?: string | null
          comment?: string | null
          id?: string
          prospect_id?: string | null
          score?: number | null
          submitted_at?: string | null
        }
        Update: {
          booking_id?: string | null
          comment?: string | null
          id?: string
          prospect_id?: string | null
          score?: number | null
          submitted_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "call_experience_surveys_booking_id_fkey"
            columns: ["booking_id"]
            isOneToOne: false
            referencedRelation: "bookings"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "call_experience_surveys_prospect_id_fkey"
            columns: ["prospect_id"]
            isOneToOne: false
            referencedRelation: "prospects"
            referencedColumns: ["id"]
          },
        ]
      }
      credit_transactions: {
        Row: {
          amount: number
          balance_after: number
          created_at: string | null
          description: string | null
          expert_id: string
          id: string
          lead_id: string | null
          type: string
        }
        Insert: {
          amount: number
          balance_after: number
          created_at?: string | null
          description?: string | null
          expert_id: string
          id?: string
          lead_id?: string | null
          type: string
        }
        Update: {
          amount?: number
          balance_after?: number
          created_at?: string | null
          description?: string | null
          expert_id?: string
          id?: string
          lead_id?: string | null
          type?: string
        }
        Relationships: [
          {
            foreignKeyName: "credit_transactions_expert_id_fkey"
            columns: ["expert_id"]
            isOneToOne: false
            referencedRelation: "experts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "credit_transactions_lead_id_fkey"
            columns: ["lead_id"]
            isOneToOne: false
            referencedRelation: "leads"
            referencedColumns: ["id"]
          },
        ]
      }
      experts: {
        Row: {
          admissibility_criteria: Json
          availability: string | null
          availability_rules: Json | null
          avatar_url: string | null
          bio: string | null
          cal_username: string | null
          composite_score: number | null
          created_at: string | null
          credit_balance: number
          display_name: string | null
          gcal_access_token: string | null
          gcal_connected: boolean | null
          gcal_connected_at: string | null
          gcal_email: string | null
          gcal_refresh_token: string | null
          gcal_token_expiry_at: string | null
          headline: string | null
          id: string
          ls_subscription_id: string | null
          ls_subscription_status: string | null
          max_lead_price: number | null
          preferences: Json | null
          profile: Json | null
          rate_max: number | null
          rate_min: number | null
          reminder_settings: Json | null
          score_updated_at: string | null
          spending_limit: number | null
          verified_at: string | null
        }
        Insert: {
          admissibility_criteria?: Json
          availability?: string | null
          availability_rules?: Json | null
          avatar_url?: string | null
          bio?: string | null
          cal_username?: string | null
          composite_score?: number | null
          created_at?: string | null
          credit_balance?: number
          display_name?: string | null
          gcal_access_token?: string | null
          gcal_connected?: boolean | null
          gcal_connected_at?: string | null
          gcal_email?: string | null
          gcal_refresh_token?: string | null
          gcal_token_expiry_at?: string | null
          headline?: string | null
          id: string
          ls_subscription_id?: string | null
          ls_subscription_status?: string | null
          max_lead_price?: number | null
          preferences?: Json | null
          profile?: Json | null
          rate_max?: number | null
          rate_min?: number | null
          reminder_settings?: Json | null
          score_updated_at?: string | null
          spending_limit?: number | null
          verified_at?: string | null
        }
        Update: {
          admissibility_criteria?: Json
          availability?: string | null
          availability_rules?: Json | null
          avatar_url?: string | null
          bio?: string | null
          cal_username?: string | null
          composite_score?: number | null
          created_at?: string | null
          credit_balance?: number
          display_name?: string | null
          gcal_access_token?: string | null
          gcal_connected?: boolean | null
          gcal_connected_at?: string | null
          gcal_email?: string | null
          gcal_refresh_token?: string | null
          gcal_token_expiry_at?: string | null
          headline?: string | null
          id?: string
          ls_subscription_id?: string | null
          ls_subscription_status?: string | null
          max_lead_price?: number | null
          preferences?: Json | null
          profile?: Json | null
          rate_max?: number | null
          rate_min?: number | null
          reminder_settings?: Json | null
          score_updated_at?: string | null
          spending_limit?: number | null
          verified_at?: string | null
        }
        Relationships: []
      }
      lead_evaluations: {
        Row: {
          conversion_declared: boolean | null
          conversion_declared_at: string | null
          expert_id: string | null
          id: string
          lead_id: string | null
          lead_quality_score: number | null
          notes: string | null
          submitted_at: string | null
        }
        Insert: {
          conversion_declared?: boolean | null
          conversion_declared_at?: string | null
          expert_id?: string | null
          id?: string
          lead_id?: string | null
          lead_quality_score?: number | null
          notes?: string | null
          submitted_at?: string | null
        }
        Update: {
          conversion_declared?: boolean | null
          conversion_declared_at?: string | null
          expert_id?: string | null
          id?: string
          lead_id?: string | null
          lead_quality_score?: number | null
          notes?: string | null
          submitted_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "lead_evaluations_expert_id_fkey"
            columns: ["expert_id"]
            isOneToOne: false
            referencedRelation: "experts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lead_evaluations_lead_id_fkey"
            columns: ["lead_id"]
            isOneToOne: true
            referencedRelation: "leads"
            referencedColumns: ["id"]
          },
        ]
      }
      leads: {
        Row: {
          amount: number | null
          billed_at: string | null
          booking_id: string | null
          confirmed_at: string | null
          created_at: string | null
          expert_id: string | null
          flag_reason: string | null
          flagged_at: string | null
          id: string
          ls_checkout_id: string | null
          ls_order_id: string | null
          prospect_id: string | null
          status: string | null
          usage_reported_at: string | null
        }
        Insert: {
          amount?: number | null
          billed_at?: string | null
          booking_id?: string | null
          confirmed_at?: string | null
          created_at?: string | null
          expert_id?: string | null
          flag_reason?: string | null
          flagged_at?: string | null
          id?: string
          ls_checkout_id?: string | null
          ls_order_id?: string | null
          prospect_id?: string | null
          status?: string | null
          usage_reported_at?: string | null
        }
        Update: {
          amount?: number | null
          billed_at?: string | null
          booking_id?: string | null
          confirmed_at?: string | null
          created_at?: string | null
          expert_id?: string | null
          flag_reason?: string | null
          flagged_at?: string | null
          id?: string
          ls_checkout_id?: string | null
          ls_order_id?: string | null
          prospect_id?: string | null
          status?: string | null
          usage_reported_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "leads_booking_id_fkey"
            columns: ["booking_id"]
            isOneToOne: true
            referencedRelation: "bookings"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "leads_expert_id_fkey"
            columns: ["expert_id"]
            isOneToOne: false
            referencedRelation: "experts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "leads_prospect_id_fkey"
            columns: ["prospect_id"]
            isOneToOne: false
            referencedRelation: "prospects"
            referencedColumns: ["id"]
          },
        ]
      }
      matches: {
        Row: {
          created_at: string | null
          expert_id: string | null
          expires_at: string | null
          id: string
          prospect_id: string | null
          score: number | null
          score_breakdown: Json | null
          status: string | null
        }
        Insert: {
          created_at?: string | null
          expert_id?: string | null
          expires_at?: string | null
          id?: string
          prospect_id?: string | null
          score?: number | null
          score_breakdown?: Json | null
          status?: string | null
        }
        Update: {
          created_at?: string | null
          expert_id?: string | null
          expires_at?: string | null
          id?: string
          prospect_id?: string | null
          score?: number | null
          score_breakdown?: Json | null
          status?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "matches_expert_id_fkey"
            columns: ["expert_id"]
            isOneToOne: false
            referencedRelation: "experts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "matches_prospect_id_fkey"
            columns: ["prospect_id"]
            isOneToOne: false
            referencedRelation: "prospects"
            referencedColumns: ["id"]
          },
        ]
      }
      project_satisfaction_surveys: {
        Row: {
          booking_id: string | null
          comment: string | null
          id: string
          prospect_id: string | null
          score: number | null
          submitted_at: string | null
        }
        Insert: {
          booking_id?: string | null
          comment?: string | null
          id?: string
          prospect_id?: string | null
          score?: number | null
          submitted_at?: string | null
        }
        Update: {
          booking_id?: string | null
          comment?: string | null
          id?: string
          prospect_id?: string | null
          score?: number | null
          submitted_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "project_satisfaction_surveys_booking_id_fkey"
            columns: ["booking_id"]
            isOneToOne: false
            referencedRelation: "bookings"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "project_satisfaction_surveys_prospect_id_fkey"
            columns: ["prospect_id"]
            isOneToOne: false
            referencedRelation: "prospects"
            referencedColumns: ["id"]
          },
        ]
      }
      prospects: {
        Row: {
          created_at: string | null
          email: string | null
          id: string
          quiz_answers: Json | null
          requirements: Json | null
          satellite_id: string | null
          status: string | null
          utm_campaign: string | null
          utm_source: string | null
        }
        Insert: {
          created_at?: string | null
          email?: string | null
          id?: string
          quiz_answers?: Json | null
          requirements?: Json | null
          satellite_id?: string | null
          status?: string | null
          utm_campaign?: string | null
          utm_source?: string | null
        }
        Update: {
          created_at?: string | null
          email?: string | null
          id?: string
          quiz_answers?: Json | null
          requirements?: Json | null
          satellite_id?: string | null
          status?: string | null
          utm_campaign?: string | null
          utm_source?: string | null
        }
        Relationships: []
      }
      satellite_configs: {
        Row: {
          active: boolean
          brand: Json | null
          content: Json | null
          created_at: string | null
          domain: string | null
          id: string
          label: string | null
          matching_weights: Json
          quiz_schema: Json
          structured_data: Json | null
          theme: Json | null
          tracking_enabled: boolean
          updated_at: string | null
          vertical: string | null
        }
        Insert: {
          active?: boolean
          brand?: Json | null
          content?: Json | null
          created_at?: string | null
          domain?: string | null
          id: string
          label?: string | null
          matching_weights: Json
          quiz_schema: Json
          structured_data?: Json | null
          theme?: Json | null
          tracking_enabled?: boolean
          updated_at?: string | null
          vertical?: string | null
        }
        Update: {
          active?: boolean
          brand?: Json | null
          content?: Json | null
          created_at?: string | null
          domain?: string | null
          id?: string
          label?: string | null
          matching_weights?: Json
          quiz_schema?: Json
          structured_data?: Json | null
          theme?: Json | null
          tracking_enabled?: boolean
          updated_at?: string | null
          vertical?: string | null
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      merge_expert_profile: {
        Args: {
          p_admissibility_criteria?: Json
          p_availability?: string
          p_bio?: string
          p_display_name?: string
          p_headline?: string
          p_id: string
          p_preferences?: Json
          p_profile?: Json
          p_rate_max?: number
          p_rate_min?: number
        }
        Returns: {
          admissibility_criteria: Json
          availability: string | null
          availability_rules: Json | null
          avatar_url: string | null
          bio: string | null
          cal_username: string | null
          composite_score: number | null
          created_at: string | null
          credit_balance: number
          display_name: string | null
          gcal_access_token: string | null
          gcal_connected: boolean | null
          gcal_connected_at: string | null
          gcal_email: string | null
          gcal_refresh_token: string | null
          gcal_token_expiry_at: string | null
          headline: string | null
          id: string
          ls_subscription_id: string | null
          ls_subscription_status: string | null
          max_lead_price: number | null
          preferences: Json | null
          profile: Json | null
          rate_max: number | null
          rate_min: number | null
          reminder_settings: Json | null
          score_updated_at: string | null
          spending_limit: number | null
          verified_at: string | null
        }[]
        SetofOptions: {
          from: "*"
          to: "experts"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      debit_lead_credit: {
        Args: {
          p_expert_id: string
          p_booking_id: string
          p_prospect_id: string
          p_amount: number
        }
        Returns: Json
      }
      restore_lead_credit: {
        Args: {
          p_expert_id: string
          p_lead_id: string
          p_amount: number
          p_flag_reason: string
        }
        Returns: Json
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
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
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
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
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
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
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
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
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
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
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
