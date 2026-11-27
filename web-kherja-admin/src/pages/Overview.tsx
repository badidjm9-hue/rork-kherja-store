import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Area, AreaChart, Bar, BarChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import {
  Activity,
  BadgeDollarSign,
  CarFront,
  CircleCheck,
  CircleX,
  Clock,
  HandCoins,
  Radio,
  UserCheck,
  UserX,
  Users,
  Wallet,
} from "lucide-react";
import { supabase, must } from "@/lib/supabase";
import { useI18n } from "@/lib/i18n";
import { ErrorBlock, LoadingBlock, PageHeader, StatCard } from "@/components/kj";
import { cn } from "@/lib/utils";
import { Input } from "@/components/ui/input";

interface OverviewData {
  passengers: number;
  drivers: number;
  drivers_online: number;
  drivers_pending: number;
  suspended: number;
  deleted: number;
  open_requests: number;
  active_rides: number;
  completed: number;
  cancelled: number;
  requests: number;
  gross: number;
  commission: number;
  driver_net: number;
  refunds: number;
  avg_fare: number;
  by_vehicle: Record<string, number>;
  series: { day: string; rides: number; gross: number; commission: number }[];
}

type Preset = "today" | "7d" | "30d" | "custom";

function startOfDayAlgiers(d: Date) {
  // Algeria is UTC+1 all year (no DST).
  const local = new Date(d.getTime() + 3600_000);
  local.setUTCHours(0, 0, 0, 0);
  return new Date(local.getTime() - 3600_000);
}

function toInputDate(d: Date) {
  return new Date(d.getTime() + 3600_000).toISOString().slice(0, 10);
}

export default function Overview() {
  const { t, money, num, lang } = useI18n();
  const [preset, setPreset] = useState<Preset>("7d");
  const [customFrom, setCustomFrom] = useState(() => toInputDate(new Date(Date.now() - 14 * 86400_000)));
  const [customTo, setCustomTo] = useState(() => toInputDate(new Date()));

  const customRangeInvalid = preset === "custom" && (!customFrom || !customTo || customFrom > customTo);

  const range = useMemo(() => {
    const now = new Date();
    const today = startOfDayAlgiers(now);
    if (preset === "today") return { from: today, to: now };
    if (preset === "7d") return { from: new Date(today.getTime() - 6 * 86400_000), to: now };
    if (preset === "30d") return { from: new Date(today.getTime() - 29 * 86400_000), to: now };
    // Keep the query key valid while the custom range is incomplete or reversed.
    if (!customFrom || !customTo || customFrom > customTo) return { from: today, to: now };
    const from = new Date(`${customFrom}T00:00:00+01:00`);
    const to = new Date(`${customTo}T23:59:59+01:00`);
    return { from, to };
  }, [preset, customFrom, customTo]);

  const q = useQuery({
    enabled: !customRangeInvalid,
    queryKey: ["overview", range.from.toISOString(), preset === "custom" ? range.to.toISOString() : preset],
    queryFn: async () =>
      must(await supabase.rpc("admin_overview", { p_from: range.from.toISOString(), p_to: range.to.toISOString() })) as unknown as OverviewData,
    refetchInterval: 30_000,
  });

  const presets: { id: Preset; label: string }[] = [
    { id: "today", label: t("Aujourd'hui", "اليوم") },
    { id: "7d", label: t("7 jours", "7 أيام") },
    { id: "30d", label: t("30 jours", "30 يومًا") },
    { id: "custom", label: t("Période", "فترة") },
  ];

  const d = q.data;
  const series = (d?.series ?? []).map((s) => ({
    ...s,
    label: new Intl.DateTimeFormat(lang === "ar" ? "ar-DZ-u-nu-latn" : "fr-DZ", { day: "2-digit", month: "short" }).format(
      new Date(s.day),
    ),
  }));
  const completionRate = d && d.completed + d.cancelled > 0 ? (d.completed / (d.completed + d.cancelled)) * 100 : null;

  return (
    <div>
      <PageHeader
        title={t("Vue d'ensemble", "نظرة عامة")}
        subtitle={t("Activité réelle de la plateforme, actualisée toutes les 30 s.", "نشاط المنصة الفعلي، يُحدّث كل 30 ثانية.")}
        actions={
          <div className="flex flex-wrap items-center gap-2">
            <div className="flex rounded-xl border bg-card p-1">
              {presets.map((p) => (
                <button
                  key={p.id}
                  onClick={() => setPreset(p.id)}
                  className={cn(
                    "rounded-lg px-3 py-1.5 text-sm font-semibold transition-colors",
                    preset === p.id ? "bg-primary text-primary-foreground" : "text-muted-foreground hover:text-foreground",
                  )}
                >
                  {p.label}
                </button>
              ))}
            </div>
            {preset === "custom" && (
              <div className="flex items-center gap-2">
                <Input type="date" value={customFrom} onChange={(e) => setCustomFrom(e.target.value)} className="h-9 w-40" />
                <span className="text-muted-foreground">→</span>
                <Input type="date" value={customTo} onChange={(e) => setCustomTo(e.target.value)} className="h-9 w-40" />
              </div>
            )}
          </div>
        }
      />

      {customRangeInvalid && (
        <div role="alert" className="kj-card border border-destructive/30 p-4 text-sm text-destructive">
          {t("La date de début doit précéder ou égaler la date de fin.", "يجب أن يكون تاريخ البداية قبل تاريخ النهاية أو مساوياً له.")}
        </div>
      )}
      {q.isLoading && <LoadingBlock />}
      {q.error && <ErrorBlock error={q.error} />}

      {d && (
        <div className="space-y-6">
          <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            <StatCard label={t("Chiffre d'affaires", "إجمالي المداخيل")} value={money(d.gross)} icon={Wallet} hint={t("Courses terminées", "رحلات مكتملة")} />
            <StatCard label={t("Commissions", "العمولات")} value={money(d.commission)} icon={HandCoins} tone="bordeaux" />
            <StatCard label={t("Gains chauffeurs", "أرباح السائقين")} value={money(d.driver_net)} icon={BadgeDollarSign} tone="green" />
            <StatCard label={t("Prix moyen", "متوسط السعر")} value={money(d.avg_fare)} icon={Activity} tone="gray" />
          </div>

          <div className="grid gap-4 lg:grid-cols-3">
            <div className="kj-card p-5 lg:col-span-2">
              <div className="mb-4 flex items-center justify-between">
                <p className="font-bold">{t("Revenus par jour", "المداخيل اليومية")}</p>
                <div className="flex items-center gap-4 text-xs font-semibold text-muted-foreground">
                  <span className="flex items-center gap-1.5"><span className="h-2 w-2 rounded-full bg-primary" />{t("Brut", "إجمالي")}</span>
                  <span className="flex items-center gap-1.5"><span className="h-2 w-2 rounded-full bg-bordeaux" />{t("Commission", "عمولة")}</span>
                </div>
              </div>
              <div className="h-64" dir="ltr">
                <ResponsiveContainer width="100%" height="100%">
                  <AreaChart data={series} margin={{ left: 0, right: 8, top: 4 }}>
                    <defs>
                      <linearGradient id="gGross" x1="0" y1="0" x2="0" y2="1">
                        <stop offset="0%" stopColor="hsl(219.7 100% 51.4%)" stopOpacity={0.35} />
                        <stop offset="100%" stopColor="hsl(219.7 100% 51.4%)" stopOpacity={0} />
                      </linearGradient>
                      <linearGradient id="gCom" x1="0" y1="0" x2="0" y2="1">
                        <stop offset="0%" stopColor="hsl(331.6 100% 26.1%)" stopOpacity={0.3} />
                        <stop offset="100%" stopColor="hsl(331.6 100% 26.1%)" stopOpacity={0} />
                      </linearGradient>
                    </defs>
                    <CartesianGrid vertical={false} stroke="hsl(226 32% 92%)" />
                    <XAxis dataKey="label" tickLine={false} axisLine={false} fontSize={12} />
                    <YAxis tickLine={false} axisLine={false} fontSize={12} width={60} />
                    <Tooltip formatter={(v: number) => money(v)} contentStyle={{ borderRadius: 12, border: "1px solid hsl(226 32% 90%)" }} />
                    <Area type="monotone" dataKey="gross" name={t("Brut", "إجمالي")} stroke="hsl(219.7 100% 51.4%)" strokeWidth={2.5} fill="url(#gGross)" />
                    <Area type="monotone" dataKey="commission" name={t("Commission", "عمولة")} stroke="hsl(331.6 100% 26.1%)" strokeWidth={2} fill="url(#gCom)" />
                  </AreaChart>
                </ResponsiveContainer>
              </div>
            </div>
            <div className="kj-card p-5">
              <p className="mb-4 font-bold">{t("Courses terminées par jour", "الرحلات المكتملة يوميًا")}</p>
              <div className="h-64" dir="ltr">
                <ResponsiveContainer width="100%" height="100%">
                  <BarChart data={series} margin={{ left: -20, right: 4, top: 4 }}>
                    <CartesianGrid vertical={false} stroke="hsl(226 32% 92%)" />
                    <XAxis dataKey="label" tickLine={false} axisLine={false} fontSize={11} />
                    <YAxis allowDecimals={false} tickLine={false} axisLine={false} fontSize={12} />
                    <Tooltip contentStyle={{ borderRadius: 12, border: "1px solid hsl(226 32% 90%)" }} />
                    <Bar dataKey="rides" name={t("Courses", "رحلات")} fill="hsl(219.7 100% 51.4%)" radius={[6, 6, 0, 0]} />
                  </BarChart>
                </ResponsiveContainer>
              </div>
            </div>
          </div>

          <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            <StatCard label={t("Courses actives", "رحلات جارية")} value={num(d.active_rides)} icon={Radio} hint={t("En ce moment", "الآن")} />
            <StatCard label={t("Demandes ouvertes", "طلبات مفتوحة")} value={num(d.open_requests)} icon={Clock} tone="amber" hint={t("En ce moment", "الآن")} />
            <StatCard
              label={t("Terminées / annulées", "مكتملة / ملغاة")}
              value={`${num(d.completed)} / ${num(d.cancelled)}`}
              icon={CircleCheck}
              tone="green"
              hint={completionRate === null ? t("Aucune course sur la période", "لا توجد رحلات في الفترة") : t(`Taux de réussite ${num(completionRate, 1)} %`, `نسبة النجاح ${num(completionRate, 1)}٪`)}
            />
            <StatCard label={t("Demandes créées", "طلبات منشأة")} value={num(d.requests)} icon={Activity} tone="gray" />
            <StatCard label={t("Passagers", "الركاب")} value={num(d.passengers)} icon={Users} tone="gray" />
            <StatCard
              label={t("Chauffeurs", "السائقون")}
              value={num(d.drivers)}
              icon={CarFront}
              hint={t(`${num(d.drivers_online)} en ligne`, `${num(d.drivers_online)} متصل`)}
            />
            <StatCard label={t("Chauffeurs à valider", "سائقون بانتظار التحقق")} value={num(d.drivers_pending)} icon={UserCheck} tone="amber" />
            <StatCard label={t("Comptes suspendus", "حسابات معلقة")} value={num(d.suspended)} icon={CircleX} tone="red" />
            <StatCard label={t("Comptes supprimés", "حسابات محذوفة")} value={num(d.deleted ?? 0)} icon={UserX} tone="gray" />
          </div>
        </div>
      )}
    </div>
  );
}
