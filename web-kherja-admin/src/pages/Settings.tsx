import { useEffect, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { Loader2 } from "lucide-react";
import { supabase, must, errorMessage, type AppSetting } from "@/lib/supabase";
import { useAuth } from "@/lib/auth";
import { useI18n } from "@/lib/i18n";
import { ErrorBlock, LoadingBlock, PageHeader } from "@/components/kj";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";

interface Field {
  key: string;
  fr: string;
  ar: string;
  hintFr: string;
  hintAr: string;
  numeric?: boolean;
  dir?: "ltr";
}
const FIELDS: Field[] = [
  { key: "support.phone", fr: "Téléphone du support", ar: "هاتف الدعم", hintFr: "Affiché aux utilisateurs.", hintAr: "يظهر للمستخدمين.", dir: "ltr" },
  { key: "support.email", fr: "E-mail du support", ar: "بريد الدعم", hintFr: "Affiché aux utilisateurs.", hintAr: "يظهر للمستخدمين.", dir: "ltr" },
  { key: "ride.offer_ttl_minutes", fr: "Durée de validité d'une demande (min)", ar: "مدة صلاحية الطلب (دقيقة)", hintFr: "Entre 1 et 120.", hintAr: "بين 1 و120.", numeric: true },
  { key: "maintenance.banner", fr: "Bannière d'information", ar: "شريط معلومات", hintFr: "Texte court (300 caractères max). Laisser vide pour masquer.", hintAr: "نص قصير (300 حرف كحد أقصى). اتركه فارغاً للإخفاء." },
];

export default function SettingsPage() {
  const { t, date } = useI18n();
  const { can } = useAuth();
  const qc = useQueryClient();
  const canEdit = can("settings.manage");
  const settings = useQuery({
    queryKey: ["app-settings"],
    queryFn: async () => must(await supabase.from("app_settings").select("*")) as AppSetting[],
  });
  const [form, setForm] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState<string | null>(null);

  useEffect(() => {
    if (!settings.data) return;
    const f: Record<string, string> = {};
    for (const s of settings.data) f[s.key] = s.value === null ? "" : String(s.value);
    setForm(f);
  }, [settings.data]);

  const saved = (key: string) => {
    const s = settings.data?.find((x) => x.key === key);
    return s ? String(s.value) : "";
  };

  const save = async (f: Field) => {
    const raw = (form[f.key] ?? "").trim();
    if (f.numeric) {
      const n = Number(raw);
      if (!Number.isInteger(n) || n < 1 || n > 120) {
        toast.error(t("Valeur invalide (1 à 120).", "قيمة غير صالحة (من 1 إلى 120)."));
        return;
      }
    }
    setBusy(f.key);
    try {
      must(await supabase.rpc("admin_set_setting", { p_key: f.key, p_value: f.numeric ? Number(raw) : raw }));
      toast.success(t("Paramètre enregistré", "تم حفظ الإعداد"));
      qc.invalidateQueries({ queryKey: ["app-settings"] });
      qc.invalidateQueries({ queryKey: ["audit"] });
    } catch (e) {
      toast.error(errorMessage(e));
    } finally {
      setBusy(null);
    }
  };

  return (
    <div>
      <PageHeader
        title={t("Paramètres", "الإعدادات")}
        subtitle={t("Chaque modification est enregistrée dans le journal d'audit.", "كل تعديل يُسجل في سجل التدقيق.")}
      />
      {settings.isLoading && <LoadingBlock />}
      {settings.error && <ErrorBlock error={settings.error} />}
      {settings.data && (
        <div className="space-y-4">
          {FIELDS.map((f) => {
            const row = settings.data.find((s) => s.key === f.key);
            const dirty = (form[f.key] ?? "").trim() !== saved(f.key);
            return (
              <div key={f.key} className="kj-card space-y-2 p-5">
                <Label htmlFor={f.key}>{t(f.fr, f.ar)}</Label>
                <div className="flex flex-wrap gap-2">
                  <Input
                    id={f.key}
                    className="min-w-[240px] flex-1"
                    dir={f.dir}
                    inputMode={f.numeric ? "numeric" : undefined}
                    value={form[f.key] ?? ""}
                    disabled={!canEdit}
                    onChange={(e) => setForm((p) => ({ ...p, [f.key]: e.target.value }))}
                  />
                  {canEdit && (
                    <Button disabled={!dirty || busy === f.key} onClick={() => save(f)}>
                      {busy === f.key && <Loader2 className="me-2 h-4 w-4 animate-spin" />}
                      {t("Enregistrer", "حفظ")}
                    </Button>
                  )}
                </div>
                <p className="text-xs text-muted-foreground">
                  {t(f.hintFr, f.hintAr)}
                  {row ? ` · ${t("Modifié", "عُدّل")} ${date(row.updated_at)}` : ""}
                </p>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
