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
          created_at: string | null
          duration_min: number | null
          id: string
          match_id: string | null
          scheduled_at: string | null
          status: string | null
        }
        Insert: {
          cal_booking_id?: string | null
          cal_meeting_url?: string | null
          created_at?: string | null
          duration_min?: number | null
          id?: string
          match_id?: string | null
          scheduled_at?: string | null
          status?: string | null
        }
        Update: {
          cal_booking_id?: string | null
          cal_meeting_url?: string | null
          created_at?: string | null
          duration_min?: number | null
          id?: string
          match_id?: string | null
          scheduled_at?: string | null
          status?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "bookings_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: false
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
        ]
      }
      call_experience_surveys: {
        Row: {
          booking_id: string | null
          id: string
          prospect_id: string | null
          score: number | null
          submitted_at: string | null
        }
        Insert: {
          booking_id?: string | null
          id?: string
          prospect_id?: string | null
          score?: number | null
          submitted_at?: string | null
        }
        Update: {
          booking_id?: string | null
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
      experts: {
        Row: {
          availability: string | null
          avatar_url: string | null
          bio: string | null
          cal_username: string | null
          composite_score: number | null
          created_at: string | null
          display_name: string | null
          headline: string | null
          id: string
          preferences: Json | null
          profile: Json | null
          rate_max: number | null
          rate_min: number | null
          score_updated_at: string | null
          verified_at: string | null
        }
        Insert: {
          availability?: string | null
          avatar_url?: string | null
          bio?: string | null
          cal_username?: string | null
          composite_score?: number | null
          created_at?: string | null
          display_name?: string | null
          headline?: string | null
          id: string
          preferences?: Json | null
          profile?: Json | null
          rate_max?: number | null
          rate_min?: number | null
          score_updated_at?: string | null
          verified_at?: string | null
        }
        Update: {
          availability?: string | null
          avatar_url?: string | null
          bio?: string | null
          cal_username?: string | null
          composite_score?: number | null
          created_at?: string | null
          display_name?: string | null
          headline?: string | null
          id?: string
          preferences?: Json | null
          profile?: Json | null
          rate_max?: number | null
          rate_min?: number | null
          score_updated_at?: string | null
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
            isOneToOne: false
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
          created_at: string | null
          expert_id: string | null
          id: string
          ls_checkout_id: string | null
          ls_order_id: string | null
          prospect_id: string | null
          status: string | null
        }
        Insert: {
          amount?: number | null
          billed_at?: string | null
          booking_id?: string | null
          created_at?: string | null
          expert_id?: string | null
          id?: string
          ls_checkout_id?: string | null
          ls_order_id?: string | null
          prospect_id?: string | null
          status?: string | null
        }
        Update: {
          amount?: number | null
          billed_at?: string | null
          booking_id?: string | null
          created_at?: string | null
          expert_id?: string | null
          id?: string
          ls_checkout_id?: string | null
          ls_order_id?: string | null
          prospect_id?: string | null
          status?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "leads_booking_id_fkey"
            columns: ["booking_id"]
            isOneToOne: false
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
          id: string
          prospect_id: string | null
          score: number | null
          submitted_at: string | null
        }
        Insert: {
          booking_id?: string | null
          id?: string
          prospect_id?: string | null
          score?: number | null
          submitted_at?: string | null
        }
        Update: {
          booking_id?: string | null
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
          created_at: string | null
          domain: string | null
          id: string
          label: string | null
          matching_weights: Json
          quiz_schema: Json
          vertical: string | null
        }
        Insert: {
          created_at?: string | null
          domain?: string | null
          id: string
          label?: string | null
          matching_weights: Json
          quiz_schema: Json
          vertical?: string | null
        }
        Update: {
          created_at?: string | null
          domain?: string | null
          id?: string
          label?: string | null
          matching_weights?: Json
          quiz_schema?: Json
          vertical?: string | null
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      [_ in never]: never
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
