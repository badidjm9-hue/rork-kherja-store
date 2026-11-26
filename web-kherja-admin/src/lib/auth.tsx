import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from "react";
import type { Session } from "@supabase/supabase-js";
import { supabase } from "./supabase";

export type Permission =
  | "overview.read"
  | "users.read"
  | "users.manage"
  | "drivers.read"
  | "drivers.approve"
  | "drivers.manage"
  | "rides.read"
  | "rides.manage"
  | "finance.read"
  | "finance.adjust"
  | "pricing.read"
  | "pricing.manage"
  | "admins.manage"
  | "audit.read"
  | "deliveries.read";

export interface AdminMe {
  user_id: string;
  role: string;
  display_name: string;
  email: string | null;
  permissions: Permission[];
}

interface AuthValue {
  session: Session | null;
  admin: AdminMe | null;
  /** loading = session/admin check in progress */
  loading: boolean;
  /** true when signed in but not an active admin */
  denied: boolean;
  can: (p: Permission) => boolean;
  signIn: (email: string, password: string) => Promise<void>;
  signOut: () => Promise<void>;
}

const AuthContext = createContext<AuthValue | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null);
  const [admin, setAdmin] = useState<AdminMe | null>(null);
  const [loading, setLoading] = useState(true);
  const [denied, setDenied] = useState(false);

  const loadAdmin = useCallback(async (s: Session | null) => {
    if (!s) {
      setAdmin(null);
      setDenied(false);
      setLoading(false);
      return;
    }
    setLoading(true);
    const { data, error } = await supabase.rpc("admin_me");
    if (error || !data) {
      setAdmin(null);
      setDenied(true);
    } else {
      setAdmin(data as unknown as AdminMe);
      setDenied(false);
    }
    setLoading(false);
  }, []);

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session);
      void loadAdmin(data.session);
    });
    const { data: sub } = supabase.auth.onAuthStateChange((event, s) => {
      setSession(s);
      if (event === "SIGNED_IN" || event === "SIGNED_OUT" || event === "USER_UPDATED") {
        // Defer to avoid calling Supabase inside the auth callback.
        setTimeout(() => void loadAdmin(s), 0);
      }
    });
    return () => sub.subscription.unsubscribe();
  }, [loadAdmin]);

  const signIn = useCallback(async (email: string, password: string) => {
    const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
    if (error) throw error;
  }, []);

  const signOut = useCallback(async () => {
    await supabase.auth.signOut();
  }, []);

  const can = useCallback((p: Permission) => Boolean(admin?.permissions.includes(p)), [admin]);

  return (
    <AuthContext.Provider value={{ session, admin, loading, denied, can, signIn, signOut }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be used inside AuthProvider");
  return ctx;
}
