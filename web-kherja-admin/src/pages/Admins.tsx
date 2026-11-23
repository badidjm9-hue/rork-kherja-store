import { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { Loader2, ShieldCheck, UserPlus } from "lucide-react";
import { supabase, must, errorMessage, type AdminUser } from "@/lib/supabase";
import { useAuth } from "@/lib/auth";
import { useI18n } from "@/lib/i18n";
import { ROLE_CODES, roleLabel } from "@/lib/labels";
import { Avatar, EmptyState, ErrorBlock, LoadingBlock, PageHeader, Pill } from "@/components/kj";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";

export default function Admins() {
  const { t, relative } = useI18n();
  const { admin } = useAuth();
  const qc = useQueryClient();

  const admins = useQuery({
    queryKey: ["admin-users"],
    queryFn: async () => must(await supabase.from("admin_users").select("*").order("created_at")) as AdminUser[],
  });
  const perms = useQuery({
    queryKey: ["admin-role-permissions"],
    queryFn: async () => must(await supabase.from("admin_role_permissions").select("*")),
  });

  const [email, setEmail] = useState("");
  const [name, setName] = useState("");
  const [role, setRole] = useState<string>("support_agent");
  const [busy, setBusy] = useState<string | null>(null);

  const setAdmin = async (key: string, args: { p_email: string; p_role: string; p_active?: boolean; p_display_name?: string }, ok: string) => {
    setBusy(key);
    try {
      must(await supabase.rpc("admin_set_admin", args));
      toast.success(ok);
      await qc.invalidateQueries({ queryKey: ["admin-users"] });
      return true;
    } catch (e) {
      const msg = errorMessage(e);
      toast.error(
        /no account/i.test(msg)
          ? t("Aucun compte avec cet email. La personne doit d'abord avoir un compte KHERJA.", "لا يوجد حساب بهذا البريد. يجب أن يكون للشخص حساب KHERJA أولاً.")
          : msg,
      );
      return false;
    } finally {
      setBusy(null);
    }
  };

  const permsByRole = (r: string) => (perms.data ?? []).filter((p) => p.role_code === r).map((p) => p.permission_code).sort();

  return (
    <div>
      <PageHeader
        title={t("Administrateurs", "المسؤولون")}
        subtitle={t("Accès au tableau de bord et permissions par rôle", "الوصول إلى لوحة التحكم والصلاحيات حسب الدور")}
      />

      <div className="grid gap-5 xl:grid-cols-[1fr_380px]">
        <div className="kj-card divide-y">
          {admins.isLoading && <LoadingBlock />}
          {admins.error && <ErrorBlock error={admins.error} />}
          {admins.data?.length === 0 && <EmptyState icon={ShieldCheck} title={t("Aucun administrateur", "لا يوجد مسؤولون")} />}
          {admins.data?.map((a) => {
            const self = a.user_id === admin?.user_id;
            return (
              <div key={a.user_id} className="flex flex-wrap items-center gap-4 px-5 py-4">
                <Avatar name={a.display_name} />
                <div className="min-w-0 flex-1">
                  <p className="flex items-center gap-2 font-semibold">
                    {a.display_name}
                    {self && <span className="text-xs text-muted-foreground">({t("vous", "أنت")})</span>}
                  </p>
                  <p className="truncate text-sm text-muted-foreground">{a.email ?? "—"}</p>
                  <p className="text-xs text-muted-foreground">
                    {t("Dernière activité", "آخر نشاط")} : {a.last_seen_at ? relative(a.last_seen_at) : t("jamais", "أبدًا")}
                  </p>
                </div>
                <select
                  disabled={self || busy === a.user_id || !a.email}
                  value={a.role_code}
                  onChange={(e) =>
                    void setAdmin(a.user_id, { p_email: a.email ?? "", p_role: e.target.value, p_active: a.active, p_display_name: a.display_name }, t("Rôle mis à jour", "تم تحديث الدور"))
                  }
                  className="h-9 rounded-xl border bg-card px-3 text-sm font-semibold disabled:opacity-60"
                >
                  {ROLE_CODES.map((r) => (
                    <option key={r} value={r}>
                      {roleLabel(t, r)}
                    </option>
                  ))}
                </select>
                <div className="flex items-center gap-2">
                  <Pill tone={a.active ? "green" : "gray"}>{a.active ? t("Actif", "نشط") : t("Désactivé", "معطل")}</Pill>
                  {busy === a.user_id ? (
                    <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" />
                  ) : (
                    <Switch
                      disabled={self || !a.email}
                      checked={a.active}
                      onCheckedChange={(x) =>
                        void setAdmin(
                          a.user_id,
                          { p_email: a.email ?? "", p_role: a.role_code, p_active: x, p_display_name: a.display_name },
                          x ? t("Accès réactivé", "تمت إعادة التفعيل") : t("Accès désactivé", "تم تعطيل الوصول"),
                        )
                      }
                    />
                  )}
                </div>
              </div>
            );
          })}
        </div>

        <div className="space-y-5">
          <form
            className="kj-card space-y-4 p-5"
            onSubmit={async (e) => {
              e.preventDefault();
              const ok = await setAdmin(
                "new",
                { p_email: email.trim().toLowerCase(), p_role: role, p_active: true, p_display_name: name.trim() || undefined },
                t("Administrateur ajouté", "تمت إضافة المسؤول"),
              );
              if (ok) {
                setEmail("");
                setName("");
              }
            }}
          >
            <div className="flex items-center gap-3">
              <span className="grid h-9 w-9 place-items-center rounded-xl bg-accent text-primary">
                <UserPlus className="h-[18px] w-[18px]" />
              </span>
              <div>
                <p className="font-bold">{t("Ajouter un administrateur", "إضافة مسؤول")}</p>
                <p className="text-xs text-muted-foreground">{t("Le compte doit déjà exister (email + mot de passe).", "يجب أن يكون الحساب موجودًا مسبقًا (بريد + كلمة مرور).")}</p>
              </div>
            </div>
            <div className="space-y-1.5">
              <Label>{t("Email", "البريد الإلكتروني")}</Label>
              <Input type="email" required value={email} onChange={(e) => setEmail(e.target.value)} className="h-10 rounded-xl" />
            </div>
            <div className="space-y-1.5">
              <Label>{t("Nom affiché", "الاسم الظاهر")}</Label>
              <Input value={name} onChange={(e) => setName(e.target.value)} className="h-10 rounded-xl" />
            </div>
            <div className="space-y-1.5">
              <Label>{t("Rôle", "الدور")}</Label>
              <select value={role} onChange={(e) => setRole(e.target.value)} className="h-10 w-full rounded-xl border bg-card px-3 text-sm">
                {ROLE_CODES.map((r) => (
                  <option key={r} value={r}>
                    {roleLabel(t, r)}
                  </option>
                ))}
              </select>
            </div>
            <Button type="submit" className="h-11 w-full font-bold" disabled={busy === "new" || !email.trim()}>
              {busy === "new" && <Loader2 className="h-4 w-4 animate-spin" />}
              {t("Donner l'accès", "منح الوصول")}
            </Button>
          </form>

          <div className="kj-card p-5">
            <p className="mb-3 font-bold">{t("Permissions par rôle", "الصلاحيات حسب الدور")}</p>
            {perms.isLoading && <LoadingBlock />}
            {perms.error && <ErrorBlock error={perms.error} />}
            <div className="space-y-4">
              {perms.data &&
                ROLE_CODES.map((r) => (
                  <div key={r}>
                    <p className="mb-1.5 text-sm font-semibold">{roleLabel(t, r)}</p>
                    <div className="flex flex-wrap gap-1">
                      {permsByRole(r).map((p) => (
                        <span key={p} className="rounded-md bg-muted px-1.5 py-0.5 font-mono text-[11px] text-muted-foreground">
                          {p}
                        </span>
                      ))}
                    </div>
                  </div>
                ))}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
