import { useEffect, useMemo, useState, type ReactNode } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import {
  Bike,
  CalendarClock,
  CarFront,
  Check,
  FileClock,
  History,
  Loader2,
  MapPin,
  Moon,
  Package,
  Percent,
  Plus,
  RotateCcw,
  Save,
  Send,
  SlidersHorizontal,
  Sun,
  Trash2,
  Undo2,
  X,
  Zap,
} from "lucide-react";
import { supabase, must, errorMessage, type PricingVersion } from "@/lib/supabase";
import { useAuth } from "@/lib/auth";
import { useI18n } from "@/lib/i18n";
import {
  classify,
  cloneConfig,
  diffConfig,
  DAY_NAMES_AR,
  DAY_NAMES_FR,
  type FareResult,
  type PricingConfig,
  type VersionState,
} from "@/lib/pricing";
import { cn } from "@/lib/utils";
import { ErrorBlock, LoadingBlock, PageHeader, Pill } from "@/components/kj";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { Textarea } from "@/components/ui/textarea";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";

function useDebounced<T>(value: T, ms = 400) {
  const [v, setV] = useState(value);
  useEffect(() => {
    const id = setTimeout(() => setV(value), ms);
    return () => clearTimeout(id);
  }, [value, ms]);
  return v;
}

function toLocalInput(d: Date) {
  // datetime-local in Algiers time (UTC+1, no DST)
  return new Date(d.getTime() + 3600_000).toISOString().slice(0, 16);
}
function fromLocalInput(s: string) {
  return new Date(`${s}:00+01:00`);
}

async function simulate(config: PricingConfig, distance: number, vehicle: string, city: string, at: Date, commissionPct?: number) {
  return must(
    await supabase.rpc("admin_simulate_fare", {
      p_config: config as never,
      p_distance: distance,
      p_vehicle: vehicle,
      p_city: city,
      p_at: at.toISOString(),
      p_commission_pct: commissionPct,
    }),
  ) as unknown as FareResult;
}

export default function Pricing() {
  const { t, date } = useI18n();
  const { can } = useAuth();
  const canManage = can("pricing.manage");
  const qc = useQueryClient();

  const versions = useQuery({
    queryKey: ["pricing-versions"],
    queryFn: async () =>
      must(await supabase.from("pricing_versions").select("*").order("version", { ascending: false }).limit(200)) as PricingVersion[],
  });
  const admins = useQuery({
    queryKey: ["admin-names"],
    enabled: can("admins.manage"),
    queryFn: async () => must(await supabase.from("admin_users").select("user_id,display_name")),
  });
  const adminName = (id: string | null) =>
    id ? admins.data?.find((a) => a.user_id === id)?.display_name ?? t("Administrateur", "مسؤول") : t("Système", "النظام");

  const states = useMemo(() => classify(versions.data ?? []), [versions.data]);
  const active = versions.data?.find((v) => states.get(v.id) === "active");
  const scheduled = (versions.data ?? []).filter((v) => states.get(v.id) === "scheduled");

  const [cfg, setCfg] = useState<PricingConfig | null>(null);
  const [baseId, setBaseId] = useState<string | null>(null);
  const [tab, setTab] = useState("editor");

  useEffect(() => {
    if (!cfg && active) {
      setCfg(cloneConfig(active.config));
      setBaseId(active.id);
    }
  }, [active, cfg]);

  const refresh = () => qc.invalidateQueries({ queryKey: ["pricing-versions"] });

  if (versions.isLoading) return <LoadingBlock />;
  if (versions.error) return <ErrorBlock error={versions.error} />;
  if (!active || !cfg) return <ErrorBlock error={t("Aucune grille publiée.", "لا يوجد جدول أسعار منشور.")} />;

  const base = versions.data?.find((v) => v.id === baseId) ?? active;

  return (
    <div>
      <PageHeader
        title={t("Tarifs & commissions", "الأسعار والعمولات")}
        subtitle={t(
          "Calcul 100 % serveur. Les passagers et chauffeurs ne voient jamais le prix/km, la commission ni la formule.",
          "الحساب على الخادم بالكامل. لا يرى الركاب والسائقون أبدًا السعر لكل كم أو العمولة أو الصيغة.",
        )}
        actions={
          <div className="flex items-center gap-2 rounded-xl border bg-card px-3 py-2 text-sm">
            <span className="h-2 w-2 animate-pulse rounded-full bg-success" />
            <span className="font-semibold">{t("En vigueur", "سارية")} : v{active.version}</span>
            <span className="text-muted-foreground">· {date(active.effective_at)}</span>
          </div>
        }
      />

      {scheduled.length > 0 && (
        <div className="mb-5 space-y-2">
          {scheduled.map((s) => (
            <div key={s.id} className="flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-primary/25 bg-accent px-4 py-3 text-sm">
              <div className="flex items-center gap-3">
                <CalendarClock className="h-5 w-5 text-primary" />
                <div>
                  <p className="font-bold text-accent-foreground">
                    {t(`Version v${s.version} programmée`, `النسخة v${s.version} مجدولة`)} — {date(s.effective_at)}
                  </p>
                  {s.note && <p className="text-muted-foreground">{s.note}</p>}
                </div>
              </div>
              {canManage && (
                <Button
                  size="sm"
                  variant="outline"
                  onClick={async () => {
                    try {
                      must(await supabase.rpc("admin_cancel_scheduled_pricing", { p_id: s.id }));
                      toast.success(t("Programmation annulée", "تم إلغاء الجدولة"));
                      await refresh();
                    } catch (e) {
                      toast.error(errorMessage(e));
                    }
                  }}
                >
                  <X className="h-4 w-4" />
                  {t("Annuler la programmation", "إلغاء الجدولة")}
                </Button>
              )}
            </div>
          ))}
        </div>
      )}

      <Tabs value={tab} onValueChange={setTab}>
        <TabsList className="mb-5 h-11 rounded-xl bg-card p-1 shadow-sm">
          <TabsTrigger value="editor" className="gap-2 rounded-lg px-4 data-[state=active]:bg-primary data-[state=active]:text-primary-foreground">
            <SlidersHorizontal className="h-4 w-4" />
            {t("Configuration", "الإعدادات")}
          </TabsTrigger>
          <TabsTrigger value="simulator" className="gap-2 rounded-lg px-4 data-[state=active]:bg-primary data-[state=active]:text-primary-foreground">
            <Zap className="h-4 w-4" />
            {t("Simulateur", "المحاكي")}
          </TabsTrigger>
          <TabsTrigger value="history" className="gap-2 rounded-lg px-4 data-[state=active]:bg-primary data-[state=active]:text-primary-foreground">
            <History className="h-4 w-4" />
            {t("Historique", "السجل")}
          </TabsTrigger>
        </TabsList>

        <TabsContent value="editor">
          <Editor
            cfg={cfg}
            setCfg={setCfg}
            base={base}
            active={active}
            canManage={canManage}
            onReset={() => {
              setCfg(cloneConfig(active.config));
              setBaseId(active.id);
            }}
            onSaved={async () => {
              await refresh();
              setCfg(null);
              setBaseId(null);
            }}
          />
        </TabsContent>

        <TabsContent value="simulator">
          <Simulator draft={cfg} active={active} />
        </TabsContent>

        <TabsContent value="history">
          <HistoryList
            versions={versions.data ?? []}
            states={states}
            active={active}
            canManage={canManage}
            adminName={adminName}
            onLoad={(v) => {
              setCfg(cloneConfig(v.config));
              setBaseId(v.id);
              setTab("editor");
              toast.message(t(`Version v${v.version} chargée dans l'éditeur`, `تم تحميل النسخة v${v.version} في المحرر`));
            }}
            onChanged={refresh}
          />
        </TabsContent>
      </Tabs>
    </div>
  );
}

/* ---------------------------------- Editor --------------------------------- */

function Section({ icon: Icon, title, subtitle, children, right }: { icon: typeof CarFront; title: string; subtitle?: string; children: ReactNode; right?: ReactNode }) {
  return (
    <section className="kj-card p-5">
      <div className="mb-4 flex items-start justify-between gap-3">
        <div className="flex items-start gap-3">
          <span className="grid h-9 w-9 shrink-0 place-items-center rounded-xl bg-accent text-primary">
            <Icon className="h-[18px] w-[18px]" />
          </span>
          <div>
            <h3 className="font-bold">{title}</h3>
            {subtitle && <p className="text-xs text-muted-foreground">{subtitle}</p>}
          </div>
        </div>
        {right}
      </div>
      {children}
    </section>
  );
}

function NumField({
  label,
  value,
  onChange,
  suffix,
  step = 1,
  min = 0,
  disabled,
  hint,
}: {
  label: string;
  value: number;
  onChange: (n: number) => void;
  suffix?: string;
  step?: number;
  min?: number;
  disabled?: boolean;
  hint?: string;
}) {
  const [text, setText] = useState(String(value));
  useEffect(() => setText(String(value)), [value]);
  return (
    <div className="space-y-1.5">
      <Label className="text-xs font-semibold text-muted-foreground">{label}</Label>
      <div className="relative">
        <Input
          type="number"
          inputMode="decimal"
          step={step}
          min={min}
          disabled={disabled}
          value={text}
          onChange={(e) => {
            setText(e.target.value);
            const n = Number(e.target.value);
            if (e.target.value.trim() !== "" && Number.isFinite(n)) onChange(n);
          }}
          onBlur={() => setText(String(value))}
          className={cn("kj-num h-10 rounded-xl", suffix && "pe-14")}
        />
        {suffix && <span className="pointer-events-none absolute end-3 top-1/2 -translate-y-1/2 text-xs font-semibold text-muted-foreground">{suffix}</span>}
      </div>
      {hint && <p className="text-[11px] text-muted-foreground">{hint}</p>}
    </div>
  );
}

function Editor({
  cfg,
  setCfg,
  base,
  active,
  canManage,
  onReset,
  onSaved,
}: {
  cfg: PricingConfig;
  setCfg: (c: PricingConfig) => void;
  base: PricingVersion;
  active: PricingVersion;
  canManage: boolean;
  onReset: () => void;
  onSaved: () => Promise<void>;
}) {
  const { t, lang, money } = useI18n();
  const da = lang === "ar" ? "دج" : "DA";
  const update = (fn: (c: PricingConfig) => void) => {
    const next = cloneConfig(cfg);
    fn(next);
    setCfg(next);
  };
  const changes = useMemo(() => diffConfig(active.config, cfg), [active.config, cfg]);
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState<null | "draft" | "publish" | "schedule">(null);
  const [scheduleAt, setScheduleAt] = useState(() => toLocalInput(new Date(Date.now() + 24 * 3600_000)));
  const [confirm, setConfirm] = useState<null | "publish" | "schedule">(null);
  const [newCity, setNewCity] = useState("");
  const dis = !canManage;

  const debounced = useDebounced(cfg, 500);
  const preview = useQuery({
    queryKey: ["pricing-preview", JSON.stringify(debounced)],
    queryFn: async () => {
      const noon = new Date();
      noon.setUTCHours(11, 0, 0, 0); // 12:00 Algiers, off-peak
      const rows = await Promise.all(
        [1, 5, 10, 20].map(async (km) => ({
          km,
          car: await simulate(debounced, km, "car", "Alger", noon),
          moto: await simulate(debounced, km, "moto", "Alger", noon),
        })),
      );
      return rows;
    },
    retry: false,
  });

  const save = async (mode: "draft" | "publish" | "schedule") => {
    setBusy(mode);
    try {
      must(
        await supabase.rpc("admin_save_pricing", {
          p_config: cfg as never,
          p_publish: mode !== "draft",
          p_effective_at: mode === "schedule" ? fromLocalInput(scheduleAt).toISOString() : undefined,
          p_note: note.trim() || undefined,
        }),
      );
      toast.success(
        mode === "draft"
          ? t("Brouillon enregistré", "تم حفظ المسودة")
          : mode === "publish"
            ? t("Nouveaux tarifs en vigueur", "الأسعار الجديدة سارية")
            : t("Changement programmé", "تمت جدولة التغيير"),
      );
      setNote("");
      await onSaved();
    } catch (e) {
      toast.error(errorMessage(e));
    } finally {
      setBusy(null);
      setConfirm(null);
    }
  };

  const vehicleBlock = (key: "car" | "moto") => {
    const v = cfg.vehicles[key];
    const Icon = key === "car" ? CarFront : Bike;
    return (
      <Section
        icon={Icon}
        title={key === "car" ? t("Voiture", "سيارة") : t("Moto", "دراجة نارية")}
        subtitle={t("Tarif de base appliqué par le serveur", "السعر الأساسي المطبق من الخادم")}
        right={
          <div className="flex items-center gap-2 text-xs font-semibold text-muted-foreground">
            {v.enabled ? t("Actif", "مفعل") : t("Désactivé", "معطل")}
            <Switch disabled={dis} checked={v.enabled} onCheckedChange={(x) => update((c) => void (c.vehicles[key].enabled = x))} />
          </div>
        }
      >
        <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
          <NumField disabled={dis} label={t("Prix par km", "السعر لكل كم")} suffix={`${da}/km`} value={v.per_km} onChange={(n) => update((c) => void (c.vehicles[key].per_km = n))} />
          <NumField disabled={dis} label={t("Prise en charge", "سعر الانطلاق")} suffix={da} value={v.base_fare} onChange={(n) => update((c) => void (c.vehicles[key].base_fare = n))} />
          <NumField disabled={dis} label={t("Tarif minimum", "الحد الأدنى")} suffix={da} value={v.min_fare} onChange={(n) => update((c) => void (c.vehicles[key].min_fare = n))} />
          <NumField disabled={dis} label={t("Tarif maximum", "الحد الأقصى")} suffix={da} value={v.max_fare} hint={t("0 = illimité", "0 = بلا حد")} onChange={(n) => update((c) => void (c.vehicles[key].max_fare = n))} />
          <div className="space-y-1.5">
            <Label className="text-xs font-semibold text-muted-foreground">{t("Arrondi", "التقريب")}</Label>
            <div className="flex rounded-xl border bg-muted/40 p-0.5">
              {[1, 5, 10, 50, 100].map((r) => (
                <button
                  key={r}
                  disabled={dis}
                  onClick={() => update((c) => void (c.vehicles[key].rounding = r))}
                  className={cn("kj-num flex-1 rounded-lg py-1.5 text-xs font-semibold", v.rounding === r ? "bg-card text-primary shadow-sm" : "text-muted-foreground")}
                >
                  {r}
                </button>
              ))}
            </div>
          </div>
          <NumField disabled={dis} label={t("Attente / min", "الانتظار / دقيقة")} suffix={da} value={v.waiting_per_min} onChange={(n) => update((c) => void (c.vehicles[key].waiting_per_min = n))} />
          <NumField disabled={dis} label={t("Frais d'annulation", "رسوم الإلغاء")} suffix={da} value={v.cancellation_fee} onChange={(n) => update((c) => void (c.vehicles[key].cancellation_fee = n))} />
          <NumField disabled={dis} label={t("Commission", "العمولة")} suffix="%" value={cfg.commission.by_vehicle[key]} onChange={(n) => update((c) => void (c.commission.by_vehicle[key] = n))} />
        </div>
        <p className="mt-3 text-[11px] text-muted-foreground">
          {t(
            "Attente et annulation : enregistrés dans la grille, facturation activée dans une prochaine version des apps.",
            "الانتظار والإلغاء: محفوظان في الجدول، وسيتم تفعيل الفوترة في إصدار قادم من التطبيقات.",
          )}
        </p>
      </Section>
    );
  };

  return (
    <div className="grid gap-5 xl:grid-cols-[1fr_360px]">
      <div className="space-y-5">
        {base.id !== active.id && (
          <div className="flex items-center justify-between rounded-xl bg-warning-soft px-4 py-2.5 text-sm text-warning">
            <span className="font-semibold">{t(`Basé sur la version v${base.version}`, `مبني على النسخة v${base.version}`)}</span>
            <button className="font-bold underline" onClick={onReset}>{t("Repartir de la version en vigueur", "البدء من النسخة السارية")}</button>
          </div>
        )}
        {vehicleBlock("car")}
        {vehicleBlock("moto")}

        <Section icon={Percent} title={t("Commission", "العمولة")} subtitle={t("Retenue sur le prix convenu à la fin de la course", "تُقتطع من السعر المتفق عليه عند نهاية الرحلة")}>
          <div className="mb-4 flex w-fit rounded-xl border bg-muted/40 p-0.5">
            {(["percent", "fixed"] as const).map((m) => (
              <button
                key={m}
                disabled={dis}
                onClick={() => update((c) => void (c.commission.method = m))}
                className={cn("rounded-lg px-4 py-1.5 text-sm font-semibold", cfg.commission.method === m ? "bg-card text-primary shadow-sm" : "text-muted-foreground")}
              >
                {m === "percent" ? t("Pourcentage (par véhicule)", "نسبة مئوية (حسب المركبة)") : t("Montant fixe", "مبلغ ثابت")}
              </button>
            ))}
          </div>
          <div className="grid grid-cols-2 gap-3 md:grid-cols-3">
            {cfg.commission.method === "fixed" && (
              <NumField disabled={dis} label={t("Montant fixe par course", "مبلغ ثابت لكل رحلة")} suffix={da} value={cfg.commission.fixed_amount} onChange={(n) => update((c) => void (c.commission.fixed_amount = n))} />
            )}
            <NumField disabled={dis} label={t("Commission minimum", "الحد الأدنى للعمولة")} suffix={da} value={cfg.commission.min_amount} onChange={(n) => update((c) => void (c.commission.min_amount = n))} />
            <NumField disabled={dis} label={t("Commission maximum", "الحد الأقصى للعمولة")} suffix={da} value={cfg.commission.max_amount} hint={t("0 = aucun plafond", "0 = بلا سقف")} onChange={(n) => update((c) => void (c.commission.max_amount = n))} />
          </div>
          {cfg.commission.method === "percent" && (
            <p className="mt-3 text-xs text-muted-foreground">{t("Les pourcentages se règlent dans chaque bloc véhicule ci-dessus.", "تُضبط النسب في كل قسم مركبة أعلاه.")}</p>
          )}
        </Section>

        <Section icon={Sun} title={t("Majorations & remises", "الزيادات والتخفيضات")} subtitle={t("Heure d'Alger", "توقيت الجزائر")}>
          <div className="space-y-4">
            <ModRow
              icon={<Zap className="h-4 w-4" />}
              title={t("Heures de pointe", "ساعات الذروة")}
              enabled={cfg.modifiers.peak.enabled}
              disabled={dis}
              onToggle={(x) => update((c) => void (c.modifiers.peak.enabled = x))}
            >
              <NumField disabled={dis} label={t("Majoration", "الزيادة")} suffix="%" value={cfg.modifiers.peak.pct} onChange={(n) => update((c) => void (c.modifiers.peak.pct = n))} />
              <div className="col-span-2 space-y-1.5">
                <Label className="text-xs font-semibold text-muted-foreground">{t("Plages horaires", "الفترات الزمنية")}</Label>
                <div className="flex flex-wrap items-center gap-2">
                  {cfg.modifiers.peak.windows.map((w, i) => (
                    <div key={i} className="flex items-center gap-1 rounded-xl border bg-card px-2 py-1">
                      <HourSelect disabled={dis} value={w[0]} onChange={(h) => update((c) => void (c.modifiers.peak.windows[i][0] = h))} />
                      <span className="text-muted-foreground">→</span>
                      <HourSelect disabled={dis} value={w[1]} onChange={(h) => update((c) => void (c.modifiers.peak.windows[i][1] = h))} />
                      {!dis && (
                        <button onClick={() => update((c) => void c.modifiers.peak.windows.splice(i, 1))} className="ms-1 text-muted-foreground hover:text-destructive">
                          <X className="h-3.5 w-3.5" />
                        </button>
                      )}
                    </div>
                  ))}
                  {!dis && (
                    <Button size="sm" variant="ghost" className="h-8" onClick={() => update((c) => void c.modifiers.peak.windows.push([12, 14]))}>
                      <Plus className="h-4 w-4" />
                      {t("Plage", "فترة")}
                    </Button>
                  )}
                </div>
              </div>
            </ModRow>

            <ModRow
              icon={<Moon className="h-4 w-4" />}
              title={t("Nuit", "الليل")}
              enabled={cfg.modifiers.night.enabled}
              disabled={dis}
              onToggle={(x) => update((c) => void (c.modifiers.night.enabled = x))}
            >
              <NumField disabled={dis} label={t("Majoration", "الزيادة")} suffix="%" value={cfg.modifiers.night.pct} onChange={(n) => update((c) => void (c.modifiers.night.pct = n))} />
              <div className="space-y-1.5">
                <Label className="text-xs font-semibold text-muted-foreground">{t("De", "من")}</Label>
                <HourSelect disabled={dis} block value={cfg.modifiers.night.start_hour} onChange={(h) => update((c) => void (c.modifiers.night.start_hour = h))} />
              </div>
              <div className="space-y-1.5">
                <Label className="text-xs font-semibold text-muted-foreground">{t("À", "إلى")}</Label>
                <HourSelect disabled={dis} block value={cfg.modifiers.night.end_hour} onChange={(h) => update((c) => void (c.modifiers.night.end_hour = h))} />
              </div>
            </ModRow>

            <ModRow
              icon={<CalendarClock className="h-4 w-4" />}
              title={t("Week-end", "عطلة نهاية الأسبوع")}
              enabled={cfg.modifiers.weekend.enabled}
              disabled={dis}
              onToggle={(x) => update((c) => void (c.modifiers.weekend.enabled = x))}
            >
              <NumField disabled={dis} label={t("Majoration", "الزيادة")} suffix="%" value={cfg.modifiers.weekend.pct} onChange={(n) => update((c) => void (c.modifiers.weekend.pct = n))} />
              <div className="col-span-2 space-y-1.5">
                <Label className="text-xs font-semibold text-muted-foreground">{t("Jours", "الأيام")}</Label>
                <div className="flex flex-wrap gap-1">
                  {(lang === "ar" ? DAY_NAMES_AR : DAY_NAMES_FR).map((d, i) => {
                    const on = cfg.modifiers.weekend.days.includes(i);
                    return (
                      <button
                        key={i}
                        disabled={dis}
                        onClick={() =>
                          update((c) => {
                            c.modifiers.weekend.days = on ? c.modifiers.weekend.days.filter((x) => x !== i) : [...c.modifiers.weekend.days, i].sort();
                          })
                        }
                        className={cn("rounded-lg border px-2.5 py-1.5 text-xs font-semibold", on ? "border-primary bg-primary text-primary-foreground" : "bg-card text-muted-foreground")}
                      >
                        {d}
                      </button>
                    );
                  })}
                </div>
              </div>
            </ModRow>

            <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
              <NumField disabled={dis} label={t("Plafond total des majorations", "سقف مجموع الزيادات")} suffix="%" value={cfg.modifiers.cap_pct} onChange={(n) => update((c) => void (c.modifiers.cap_pct = n))} />
            </div>

            <ModRow
              icon={<Sun className="h-4 w-4" />}
              title={t("Remise en journée (hors pointe et nuit)", "تخفيض النهار (خارج الذروة والليل)")}
              enabled={cfg.promo.daytime.enabled}
              disabled={dis}
              onToggle={(x) => update((c) => void (c.promo.daytime.enabled = x))}
            >
              <NumField disabled={dis} label={t("Voiture", "سيارة")} suffix="%" value={cfg.promo.daytime.car_pct} onChange={(n) => update((c) => void (c.promo.daytime.car_pct = n))} />
              <NumField disabled={dis} label={t("Moto", "دراجة")} suffix="%" value={cfg.promo.daytime.moto_pct} onChange={(n) => update((c) => void (c.promo.daytime.moto_pct = n))} />
            </ModRow>
          </div>
        </Section>

        <Section icon={MapPin} title={t("Villes", "المدن")} subtitle={t("Coefficient appliqué au prix (1 = aucun effet)", "معامل يطبق على السعر (1 = بلا تأثير)")}>
          <div className="grid gap-2 md:grid-cols-2">
            {Object.entries(cfg.cities).map(([name, c]) => (
              <div key={name} className="flex items-center gap-3 rounded-xl border bg-card px-3 py-2">
                <Switch disabled={dis} checked={c.enabled} onCheckedChange={(x) => update((cc) => void (cc.cities[name].enabled = x))} />
                <span className="flex-1 font-semibold">{name}</span>
                <div className="w-28">
                  <NumField disabled={dis} label="" step={0.05} min={0.5} value={c.multiplier} suffix="×" onChange={(n) => update((cc) => void (cc.cities[name].multiplier = n))} />
                </div>
                {!dis && (
                  <button onClick={() => update((cc) => void delete cc.cities[name])} className="text-muted-foreground hover:text-destructive">
                    <Trash2 className="h-4 w-4" />
                  </button>
                )}
              </div>
            ))}
          </div>
          {!dis && (
            <div className="mt-3 flex gap-2">
              <Input value={newCity} onChange={(e) => setNewCity(e.target.value)} placeholder={t("Nouvelle ville (ex. Sétif)", "مدينة جديدة (مثلاً سطيف)")} className="h-10 max-w-xs rounded-xl" />
              <Button
                variant="outline"
                disabled={!newCity.trim() || newCity.trim() in cfg.cities}
                onClick={() => {
                  update((c) => void (c.cities[newCity.trim()] = { enabled: true, multiplier: 1 }));
                  setNewCity("");
                }}
              >
                <Plus className="h-4 w-4" />
                {t("Ajouter", "إضافة")}
              </Button>
            </div>
          )}
        </Section>

        <Section icon={SlidersHorizontal} title={t("Limites de négociation", "حدود التفاوض")} subtitle={t("En % de l'estimation serveur", "كنسبة من تقدير الخادم")}>
          <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
            <NumField disabled={dis} label={t("Passager min", "الراكب الأدنى")} suffix="%" value={cfg.negotiation.passenger_min_pct} onChange={(n) => update((c) => void (c.negotiation.passenger_min_pct = n))} />
            <NumField disabled={dis} label={t("Passager max", "الراكب الأقصى")} suffix="%" value={cfg.negotiation.passenger_max_pct} onChange={(n) => update((c) => void (c.negotiation.passenger_max_pct = n))} />
            <NumField disabled={dis} label={t("Chauffeur min", "السائق الأدنى")} suffix="%" value={cfg.negotiation.driver_min_pct} onChange={(n) => update((c) => void (c.negotiation.driver_min_pct = n))} />
            <NumField disabled={dis} label={t("Chauffeur max", "السائق الأقصى")} suffix="%" value={cfg.negotiation.driver_max_pct} onChange={(n) => update((c) => void (c.negotiation.driver_max_pct = n))} />
          </div>
        </Section>

        <Section icon={Package} title={t("Livraison", "التوصيل")} subtitle={t("Grille enregistrée — utilisée quand le module livraison sera ouvert", "جدول محفوظ — يُستخدم عند فتح وحدة التوصيل")}>
          <div className="grid gap-4 md:grid-cols-2">
            {(["food", "parcel"] as const).map((k) => (
              <div key={k} className="rounded-xl border bg-muted/30 p-3">
                <p className="mb-2 text-sm font-bold">{k === "food" ? t("Repas", "وجبات") : t("Colis", "طرود")}</p>
                <div className="grid grid-cols-3 gap-2">
                  <NumField disabled={dis} label={t("Base", "أساسي")} suffix={da} value={cfg.delivery[k].base_fare} onChange={(n) => update((c) => void (c.delivery[k].base_fare = n))} />
                  <NumField disabled={dis} label="/km" suffix={da} value={cfg.delivery[k].per_km} onChange={(n) => update((c) => void (c.delivery[k].per_km = n))} />
                  <NumField disabled={dis} label={t("Min", "أدنى")} suffix={da} value={cfg.delivery[k].min_fare} onChange={(n) => update((c) => void (c.delivery[k].min_fare = n))} />
                </div>
              </div>
            ))}
          </div>
        </Section>
      </div>

      {/* Sticky action panel */}
      <div className="space-y-4 xl:sticky xl:top-6 xl:self-start">
        <div className="kj-card overflow-hidden">
          <div className="bg-[hsl(225_64%_12%)] px-5 py-4 text-white">
            <p className="text-xs font-semibold uppercase tracking-wider text-white/60">{t("Aperçu en direct · 12 h, Alger", "معاينة مباشرة · 12 ظهرًا، الجزائر")}</p>
            <p className="mt-1 text-sm text-white/80">{t("Prix passager avant remise → après remise", "سعر الراكب قبل التخفيض ← بعده")}</p>
          </div>
          <div className="p-4">
            {preview.isFetching && !preview.data && <LoadingBlock />}
            {preview.error && <p className="rounded-xl bg-destructive/10 p-3 text-sm text-destructive">{errorMessage(preview.error)}</p>}
            {preview.data && (
              <table className={cn("w-full text-sm transition-opacity", preview.isFetching && "opacity-60")}>
                <thead>
                  <tr className="text-xs text-muted-foreground">
                    <th className="pb-2 text-start font-semibold">km</th>
                    <th className="pb-2 text-end font-semibold">{t("Voiture", "سيارة")}</th>
                    <th className="pb-2 text-end font-semibold">{t("Moto", "دراجة")}</th>
                  </tr>
                </thead>
                <tbody>
                  {preview.data.map((r) => (
                    <tr key={r.km} className="border-t">
                      <td className="kj-num py-2 font-semibold">{r.km}</td>
                      <td className="py-2 text-end">
                        <p className="kj-num font-bold">{money(r.car.price_before_discount)}</p>
                        {r.car.discount > 0 && <p className="kj-num text-xs text-success">→ {money(r.car.fare)}</p>}
                      </td>
                      <td className="py-2 text-end">
                        <p className="kj-num font-bold">{money(r.moto.price_before_discount)}</p>
                        {r.moto.discount > 0 && <p className="kj-num text-xs text-success">→ {money(r.moto.fare)}</p>}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        </div>

        {canManage ? (
          <div className="kj-card space-y-4 p-5">
            <div className="flex items-center justify-between">
              <p className="font-bold">{t("Modifications", "التعديلات")}</p>
              <Pill tone={changes.length ? "amber" : "gray"} dot={false}>
                {changes.length} {t("champ(s)", "حقل")}
              </Pill>
            </div>
            {changes.length > 0 && (
              <div className="max-h-40 space-y-1 overflow-y-auto rounded-xl bg-muted/50 p-2 text-xs">
                {changes.map((c) => (
                  <div key={c.path} className="flex items-center justify-between gap-2">
                    <span className="truncate font-mono text-muted-foreground">{c.path}</span>
                    <span className="kj-num shrink-0">
                      <span className="text-destructive line-through">{JSON.stringify(c.from) ?? "—"}</span>{" "}
                      <span className="font-semibold text-success">{JSON.stringify(c.to) ?? "—"}</span>
                    </span>
                  </div>
                ))}
              </div>
            )}
            <div className="space-y-1.5">
              <Label className="text-xs font-semibold text-muted-foreground">{t("Note de version", "ملاحظة النسخة")}</Label>
              <Textarea rows={2} value={note} onChange={(e) => setNote(e.target.value)} placeholder={t("Ex. Hausse carburant novembre", "مثال: زيادة الوقود نوفمبر")} />
            </div>
            <div className="grid gap-2">
              <Button disabled={!!busy || changes.length === 0} onClick={() => setConfirm("publish")} className="h-11 font-bold">
                {busy === "publish" ? <Loader2 className="h-4 w-4 animate-spin" /> : <Send className="h-4 w-4 rtl:-scale-x-100" />}
                {t("Publier maintenant", "نشر الآن")}
              </Button>
              <div className="flex gap-2">
                <Input type="datetime-local" value={scheduleAt} onChange={(e) => setScheduleAt(e.target.value)} className="h-10 flex-1 rounded-xl" />
                <Button variant="outline" disabled={!!busy || changes.length === 0} onClick={() => setConfirm("schedule")}>
                  {busy === "schedule" ? <Loader2 className="h-4 w-4 animate-spin" /> : <CalendarClock className="h-4 w-4" />}
                  {t("Programmer", "جدولة")}
                </Button>
              </div>
              <div className="flex gap-2">
                <Button variant="secondary" className="flex-1" disabled={!!busy || changes.length === 0} onClick={() => void save("draft")}>
                  {busy === "draft" ? <Loader2 className="h-4 w-4 animate-spin" /> : <Save className="h-4 w-4" />}
                  {t("Brouillon", "مسودة")}
                </Button>
                <Button variant="ghost" disabled={!!busy || (changes.length === 0 && base.id === active.id)} onClick={onReset}>
                  <Undo2 className="h-4 w-4" />
                  {t("Réinitialiser", "إعادة ضبط")}
                </Button>
              </div>
            </div>
            <p className="text-[11px] leading-relaxed text-muted-foreground">
              {t(
                "Les courses déjà acceptées gardent leur prix et leur instantané de grille. Les nouvelles estimations utilisent la version en vigueur.",
                "الرحلات المقبولة تحتفظ بسعرها ونسخة الجدول. التقديرات الجديدة تستخدم النسخة السارية.",
              )}
            </p>
          </div>
        ) : (
          <div className="kj-card p-5 text-sm text-muted-foreground">
            {t("Lecture seule : votre rôle ne permet pas de modifier les tarifs.", "قراءة فقط: دورك لا يسمح بتعديل الأسعار.")}
          </div>
        )}
      </div>

      <AlertDialog open={!!confirm} onOpenChange={(o) => !o && !busy && setConfirm(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>
              {confirm === "publish" ? t("Publier ces tarifs maintenant ?", "نشر هذه الأسعار الآن؟") : t("Programmer ce changement ?", "جدولة هذا التغيير؟")}
            </AlertDialogTitle>
            <AlertDialogDescription>
              {confirm === "publish"
                ? t(
                    `${changes.length} champ(s) modifié(s). Toutes les nouvelles estimations utiliseront cette grille immédiatement.`,
                    `${changes.length} حقل معدل. ستستخدم جميع التقديرات الجديدة هذا الجدول فورًا.`,
                  )
                : t(
                    `La grille entrera en vigueur le ${fromLocalInput(scheduleAt).toLocaleString("fr-DZ", { timeZone: "Africa/Algiers" })} (heure d'Alger).`,
                    `سيدخل الجدول حيز التنفيذ في ${fromLocalInput(scheduleAt).toLocaleString("ar-DZ", { timeZone: "Africa/Algiers" })} (توقيت الجزائر).`,
                  )}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={!!busy}>{t("Annuler", "إلغاء")}</AlertDialogCancel>
            <AlertDialogAction
              disabled={!!busy}
              onClick={(e) => {
                e.preventDefault();
                if (confirm) void save(confirm);
              }}
            >
              {busy && <Loader2 className="h-4 w-4 animate-spin" />}
              {t("Confirmer", "تأكيد")}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}

function ModRow({
  icon,
  title,
  enabled,
  disabled,
  onToggle,
  children,
}: {
  icon: ReactNode;
  title: string;
  enabled: boolean;
  disabled?: boolean;
  onToggle: (x: boolean) => void;
  children: ReactNode;
}) {
  return (
    <div className={cn("rounded-xl border p-3 transition-colors", enabled ? "bg-card" : "bg-muted/40")}>
      <div className="mb-3 flex items-center justify-between">
        <p className="flex items-center gap-2 text-sm font-bold">
          <span className="text-primary">{icon}</span>
          {title}
        </p>
        <Switch disabled={disabled} checked={enabled} onCheckedChange={onToggle} />
      </div>
      <div className={cn("grid grid-cols-2 gap-3 md:grid-cols-3", !enabled && "opacity-50")}>{children}</div>
    </div>
  );
}

function HourSelect({ value, onChange, disabled, block }: { value: number; onChange: (h: number) => void; disabled?: boolean; block?: boolean }) {
  return (
    <select
      disabled={disabled}
      value={value}
      onChange={(e) => onChange(Number(e.target.value))}
      className={cn("kj-num rounded-lg bg-transparent px-1 py-1 text-sm font-semibold outline-none", block && "h-10 w-full rounded-xl border bg-card px-3")}
    >
      {Array.from({ length: 25 }, (_, h) => (
        <option key={h} value={h}>
          {String(h).padStart(2, "0")}h
        </option>
      ))}
    </select>
  );
}

/* -------------------------------- Simulator -------------------------------- */

function Simulator({ draft, active }: { draft: PricingConfig; active: PricingVersion }) {
  const { t, money, num } = useI18n();
  const [distance, setDistance] = useState(10);
  const [vehicle, setVehicle] = useState<"car" | "moto">("car");
  const [city, setCity] = useState("Alger");
  const [at, setAt] = useState(() => toLocalInput(new Date()));
  const [commission, setCommission] = useState("");
  const [agreed, setAgreed] = useState("");

  const params = useDebounced({ distance, vehicle, city, at, commission }, 350);
  const commissionPct = params.commission.trim() === "" ? undefined : Number(params.commission);

  const q = useQuery({
    queryKey: ["simulate", JSON.stringify(draft), JSON.stringify(params)],
    enabled: params.distance > 0,
    queryFn: async () => {
      const when = fromLocalInput(params.at);
      const [d, a] = await Promise.all([
        simulate(draft, params.distance, params.vehicle, params.city, when, commissionPct),
        simulate(cloneConfig(active.config), params.distance, params.vehicle, params.city, when, commissionPct),
      ]);
      return { draft: d, active: a };
    },
    retry: false,
  });

  const r = q.data?.draft;
  const agreedNum = Number(agreed);
  const agreedValid = agreed.trim() !== "" && Number.isFinite(agreedNum) && agreedNum > 0;
  const commissionOnAgreed = (() => {
    if (!agreedValid) return null;
    const c = draft.commission;
    let amount = c.method === "fixed" ? c.fixed_amount : (agreedNum * (commissionPct ?? c.by_vehicle[vehicle])) / 100;
    amount = Math.max(amount, c.min_amount);
    if (c.max_amount > 0) amount = Math.min(amount, c.max_amount);
    amount = Math.min(amount, agreedNum);
    return Math.round(amount);
  })();
  const neg = draft.negotiation;

  return (
    <div className="grid gap-5 lg:grid-cols-[380px_1fr]">
      <div className="kj-card space-y-4 p-5">
        <p className="font-bold">{t("Paramètres", "المعطيات")}</p>
        <div className="space-y-1.5">
          <Label className="text-xs font-semibold text-muted-foreground">{t("Distance", "المسافة")}</Label>
          <div className="flex items-center gap-3">
            <input type="range" min={1} max={80} step={0.5} value={distance} onChange={(e) => setDistance(Number(e.target.value))} className="flex-1 accent-[hsl(var(--primary))]" />
            <Input type="number" value={distance} min={0.5} step={0.5} onChange={(e) => setDistance(Number(e.target.value) || 0)} className="kj-num h-10 w-24 rounded-xl" />
          </div>
        </div>
        <div className="grid grid-cols-2 gap-2">
          {(["car", "moto"] as const).map((v) => (
            <button
              key={v}
              onClick={() => setVehicle(v)}
              className={cn(
                "flex items-center justify-center gap-2 rounded-xl border py-2.5 text-sm font-semibold",
                vehicle === v ? "border-primary bg-accent text-primary" : "bg-card text-muted-foreground",
              )}
            >
              {v === "car" ? <CarFront className="h-4 w-4" /> : <Bike className="h-4 w-4" />}
              {v === "car" ? t("Voiture", "سيارة") : t("Moto", "دراجة")}
            </button>
          ))}
        </div>
        <div className="space-y-1.5">
          <Label className="text-xs font-semibold text-muted-foreground">{t("Ville", "المدينة")}</Label>
          <select value={city} onChange={(e) => setCity(e.target.value)} className="h-10 w-full rounded-xl border bg-card px-3 text-sm">
            {Object.keys(draft.cities).map((c) => (
              <option key={c}>{c}</option>
            ))}
          </select>
        </div>
        <div className="space-y-1.5">
          <Label className="text-xs font-semibold text-muted-foreground">{t("Date et heure (Alger)", "التاريخ والوقت (الجزائر)")}</Label>
          <Input type="datetime-local" value={at} onChange={(e) => setAt(e.target.value)} className="h-10 rounded-xl" />
        </div>
        <div className="space-y-1.5">
          <Label className="text-xs font-semibold text-muted-foreground">{t("Commission test (%)", "عمولة تجريبية (%)")}</Label>
          <Input type="number" value={commission} onChange={(e) => setCommission(e.target.value)} placeholder={t("Vide = valeur de la grille", "فارغ = قيمة الجدول")} className="kj-num h-10 rounded-xl" />
        </div>
        <div className="space-y-1.5">
          <Label className="text-xs font-semibold text-muted-foreground">{t("Prix convenu (négociation)", "السعر المتفق عليه (تفاوض)")}</Label>
          <Input type="number" value={agreed} onChange={(e) => setAgreed(e.target.value)} placeholder={r ? String(r.fare) : ""} className="kj-num h-10 rounded-xl" />
        </div>
      </div>

      <div className="space-y-5">
        {q.error && <ErrorBlock error={q.error} />}
        {!r && q.isFetching && <LoadingBlock />}
        {r && q.data && (
          <>
            <div className={cn("grid gap-4 md:grid-cols-3 transition-opacity", q.isFetching && "opacity-60")}>
              <div className="kj-card p-5 md:col-span-1">
                <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">{t("Le passager voit", "يرى الراكب")}</p>
                <p className="kj-num mt-3 text-3xl font-bold text-primary">{money(r.fare)}</p>
                {r.discount > 0 && (
                  <p className="mt-1 text-sm">
                    <span className="kj-num text-muted-foreground line-through">{money(r.price_before_discount)}</span>
                    <span className="ms-2 font-semibold text-success">−{money(r.discount)}</span>
                  </p>
                )}
                <p className="mt-3 text-xs text-muted-foreground">
                  {t("Proposition autorisée", "الاقتراح المسموح")} : {money(Math.ceil((r.fare * neg.passenger_min_pct) / 100))} – {money(Math.floor((r.fare * neg.passenger_max_pct) / 100))}
                </p>
              </div>
              <div className="kj-card p-5">
                <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">{t("Le chauffeur voit", "يرى السائق")}</p>
                <p className="kj-num mt-3 text-3xl font-bold text-success">{money(agreedValid ? agreedNum - (commissionOnAgreed ?? 0) : r.driver_net)}</p>
                <p className="mt-1 text-sm text-muted-foreground">{t("gain net sur", "صافي على")} {money(agreedValid ? agreedNum : r.fare)}</p>
                <p className="mt-3 text-xs text-muted-foreground">
                  {t("Offre autorisée", "العرض المسموح")} : {money(Math.ceil((r.fare * neg.driver_min_pct) / 100))} – {money(Math.floor((r.fare * neg.driver_max_pct) / 100))}
                </p>
              </div>
              <div className="kj-card p-5">
                <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">{t("KHERJA encaisse", "تحصل KHERJA على")}</p>
                <p className="kj-num mt-3 text-3xl font-bold text-bordeaux">{money(agreedValid ? commissionOnAgreed : r.commission)}</p>
                <p className="mt-1 text-sm text-muted-foreground">
                  {r.commission_method === "fixed" ? t("commission fixe", "عمولة ثابتة") : t("commission en %", "عمولة بالنسبة")}
                </p>
              </div>
            </div>

            <div className="kj-card p-5">
              <p className="mb-3 font-bold">{t("Détail du calcul (visible uniquement par l'admin)", "تفاصيل الحساب (للمسؤول فقط)")}</p>
              <div className="space-y-1.5 text-sm">
                {r.applied.map((a, i) => (
                  <div key={i} className="flex items-center justify-between rounded-lg bg-muted/40 px-3 py-2">
                    <span>{a.label}</span>
                    <span className="kj-num font-semibold">
                      {["base", "distance", "minimum", "maximum"].includes(a.rule)
                        ? money(a.value)
                        : a.rule === "city"
                          ? `× ${num(a.value, 2)}`
                          : a.rule === "promo"
                            ? `− ${num(a.value)} %`
                            : `+ ${num(a.value)} %`}
                    </span>
                  </div>
                ))}
                <div className="flex items-center justify-between px-3 pt-2 text-xs text-muted-foreground">
                  <span>
                    {r.peak && t("Heure de pointe · ", "ذروة · ")}
                    {r.night && t("Nuit · ", "ليل · ")}
                    {r.weekend && t("Week-end · ", "عطلة · ")}
                    {t(`Heure ${r.hour}h`, `الساعة ${r.hour}`)}
                  </span>
                  <span>{t(`Majoration totale ${num(r.adjustment_pct)} %`, `مجموع الزيادة ${num(r.adjustment_pct)}٪`)}</span>
                </div>
              </div>
            </div>

            <div className="kj-card flex flex-wrap items-center justify-between gap-3 p-5">
              <div>
                <p className="font-bold">{t(`Comparaison avec la version en vigueur (v${active.version})`, `مقارنة مع النسخة السارية (v${active.version})`)}</p>
                <p className="text-sm text-muted-foreground">{t("Même trajet, même heure", "نفس المسار، نفس الوقت")}</p>
              </div>
              <div className="flex items-center gap-4">
                <span className="kj-num text-lg text-muted-foreground">{money(q.data.active.fare)}</span>
                <span className="text-muted-foreground">→</span>
                <span className="kj-num text-lg font-bold">{money(r.fare)}</span>
                <DeltaPill from={q.data.active.fare} to={r.fare} />
              </div>
            </div>
          </>
        )}
      </div>
    </div>
  );
}

function DeltaPill({ from, to }: { from: number; to: number }) {
  if (from === to) return <Pill tone="gray" dot={false}>=</Pill>;
  const pct = from > 0 ? ((to - from) / from) * 100 : 0;
  return (
    <Pill tone={to > from ? "red" : "green"} dot={false}>
      {to > from ? "+" : ""}
      {pct.toFixed(1)} %
    </Pill>
  );
}

/* --------------------------------- History --------------------------------- */

function HistoryList({
  versions,
  states,
  active,
  canManage,
  adminName,
  onLoad,
  onChanged,
}: {
  versions: PricingVersion[];
  states: Map<string, VersionState>;
  active: PricingVersion;
  canManage: boolean;
  adminName: (id: string | null) => string;
  onLoad: (v: PricingVersion) => void;
  onChanged: () => Promise<unknown>;
}) {
  const { t, date } = useI18n();
  const [busy, setBusy] = useState<string | null>(null);
  const label: Record<VersionState, { text: string; tone: "green" | "blue" | "amber" | "gray" }> = {
    active: { text: t("En vigueur", "سارية"), tone: "green" },
    scheduled: { text: t("Programmée", "مجدولة"), tone: "blue" },
    draft: { text: t("Brouillon", "مسودة"), tone: "amber" },
    superseded: { text: t("Remplacée", "مستبدلة"), tone: "gray" },
    archived: { text: t("Archivée", "مؤرشفة"), tone: "gray" },
  };

  const act = async (id: string, fn: () => Promise<void>, ok: string) => {
    setBusy(id);
    try {
      await fn();
      toast.success(ok);
      await onChanged();
    } catch (e) {
      toast.error(errorMessage(e));
    } finally {
      setBusy(null);
    }
  };

  return (
    <div className="kj-card divide-y">
      {versions.map((v) => {
        const st = states.get(v.id) ?? "superseded";
        const changes = diffConfig(active.config, v.config).length;
        return (
          <div key={v.id} className="flex flex-wrap items-center gap-4 px-5 py-4">
            <span className={cn("grid h-11 w-11 shrink-0 place-items-center rounded-xl font-mono text-sm font-bold", st === "active" ? "bg-success text-white" : "bg-muted text-foreground")}>
              v{v.version}
            </span>
            <div className="min-w-0 flex-1">
              <div className="flex flex-wrap items-center gap-2">
                <Pill tone={label[st].tone}>{label[st].text}</Pill>
                {v.restored_from && (
                  <span className="text-xs text-muted-foreground">
                    {t("restaurée depuis", "مستعادة من")} v{versions.find((x) => x.id === v.restored_from)?.version ?? "?"}
                  </span>
                )}
                {st !== "active" && <span className="text-xs text-muted-foreground">{t(`${changes} différence(s) avec la version en vigueur`, `${changes} اختلاف مع النسخة السارية`)}</span>}
              </div>
              <p className="mt-1 truncate text-sm font-semibold">{v.note || t("Sans note", "بدون ملاحظة")}</p>
              <p className="text-xs text-muted-foreground">
                {t("Créée", "أنشئت")} {date(v.created_at)} · {adminName(v.created_by)}
                {v.effective_at && ` · ${t("effet", "سريان")} ${date(v.effective_at)}`}
              </p>
            </div>
            <div className="flex flex-wrap gap-2">
              <Button size="sm" variant="ghost" onClick={() => onLoad(v)}>
                <FileClock className="h-4 w-4" />
                {t("Ouvrir", "فتح")}
              </Button>
              {canManage && st === "draft" && (
                <Button
                  size="sm"
                  disabled={busy === v.id}
                  onClick={() => act(v.id, async () => void must(await supabase.rpc("admin_publish_pricing", { p_id: v.id })), t("Brouillon publié", "تم نشر المسودة"))}
                >
                  {busy === v.id ? <Loader2 className="h-4 w-4 animate-spin" /> : <Check className="h-4 w-4" />}
                  {t("Publier", "نشر")}
                </Button>
              )}
              {canManage && (st === "superseded" || st === "archived") && (
                <Button
                  size="sm"
                  variant="outline"
                  disabled={busy === v.id}
                  onClick={() =>
                    act(v.id, async () => void must(await supabase.rpc("admin_restore_pricing", { p_id: v.id })), t(`Version v${v.version} restaurée`, `تمت استعادة النسخة v${v.version}`))
                  }
                >
                  {busy === v.id ? <Loader2 className="h-4 w-4 animate-spin" /> : <RotateCcw className="h-4 w-4" />}
                  {t("Restaurer", "استعادة")}
                </Button>
              )}
            </div>
          </div>
        );
      })}
    </div>
  );
}
