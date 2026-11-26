import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Banknote, Bike, Download, Route, UserPlus, Users } from "lucide-react";
import { supabase, must } from "@/lib/supabase";
import { useI18n } from "@/lib/i18n";
import { deliveryStatus, rideStatus } from "@/lib/labels";
import { ErrorBlock, LoadingBlock, PageHeader, Pill, StatCard } from "@/components/kj";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { buildCsv, isoDay, parseReport, type ReportData } from "@/lib/report";

export default function Reports() {
  const { t, money, num, date } = useI18n();
  const today = new Date();
  const [from, setFrom] = useState(isoDay(new Date(today.getTime() - 29 * 86400000)));
  const [to, setTo] = useState(isoDay(today));
  const rangeOk = from !== "" && to !== "" && from <= to && (new Date(to).getTime() - new Date(from).getTime()) / 86400000 <= 366;

  const report = useQuery({
    queryKey: ["report", from, to],
    enabled: rangeOk,
    queryFn: async (): Promise<ReportData> => parseReport(must(await supabase.rpc("admin_report_summary", { p_from: from, p_to: to }))),
  });

  const preset = (days: number) => {
    const end = new Date();
    setTo(isoDay(end));
    setFrom(isoDay(new Date(end.getTime() - (days - 1) * 86400000)));
  };

  const d = report.data;
  const maxRides = useMemo(() => Math.max(1, ...(d?.daily.map((x) => x.rides) ?? [1])), [d]);
  const totalRides = d ? Object.values(d.ridesByStatus).reduce((a, b) => a + b, 0) : 0;

  const exportCsv = () => {
    if (!d) return;
    const blob = new Blob(["﻿" + buildCsv(d)], { type: "text/csv;charset=utf-8" });
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = `kherja-report-${from}_${to}.csv`;
    a.click();
    URL.revokeObjectURL(a.href);
  };

  return (
    <div>
      <PageHeader
        title={t("Rapports", "التقارير")}
        subtitle={t("Courses, livraisons et croissance sur la période choisie.", "الرحلات والتوصيل والنمو في الفترة المختارة.")}
        actions={
          <Button variant="outline" size="sm" disabled={!d} onClick={exportCsv}>
            <Download className="me-2 h-4 w-4" />
            {t("Exporter CSV", "تصدير CSV")}
          </Button>
        }
      />
      <div className="mb-5 flex flex-wrap items-end gap-3">
        <div className="space-y-1">
          <Label htmlFor="rf">{t("Du", "من")}</Label>
          <Input id="rf" type="date" value={from} max={to} onChange={(e) => setFrom(e.target.value)} className="kj-num" />
        </div>
        <div className="space-y-1">
          <Label htmlFor="rt">{t("Au", "إلى")}</Label>
          <Input id="rt" type="date" value={to} min={from} onChange={(e) => setTo(e.target.value)} className="kj-num" />
        </div>
        {[7, 30, 90].map((n) => (
          <Button key={n} size="sm" variant="outline" onClick={() => preset(n)}>{n} {t("jours", "يوم")}</Button>
        ))}
      </div>
      {!rangeOk && <p className="text-sm text-destructive">{t("Période invalide (maximum 366 jours).", "فترة غير صالحة (الحد الأقصى 366 يوماً).")}</p>}
      {report.isLoading && <LoadingBlock />}
      {report.error && <ErrorBlock error={report.error} />}
      {d && (
        <div className="space-y-6">
          <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
            <StatCard label={t("Courses", "الرحلات")} value={num(totalRides)} icon={Route} hint={`${num(d.ridesByStatus.completed ?? 0)} ${t("terminées", "مكتملة")}`} />
            <StatCard label={t("Chiffre d'affaires courses", "إيرادات الرحلات")} value={money(d.ridesRevenue)} icon={Banknote} tone="green" hint={`${t("Moyenne", "المتوسط")} ${money(d.ridesAvgFare)}`} />
            <StatCard label={t("Chiffre d'affaires livraisons", "إيرادات التوصيل")} value={money(d.deliveriesRevenue)} icon={Bike} tone="bordeaux" hint={`${num(d.deliveriesByStatus.delivered ?? 0)} ${t("livrées", "سُلّمت")}`} />
            <StatCard label={t("Nouveaux passagers", "ركاب جدد")} value={num(d.newPassengers)} icon={UserPlus} />
            <StatCard label={t("Nouveaux chauffeurs", "سائقون جدد")} value={num(d.newDrivers)} icon={UserPlus} tone="bordeaux" />
            <StatCard label={t("Chauffeurs actifs", "سائقون نشطون")} value={num(d.activeDrivers)} icon={Users} tone="amber" />
          </div>

          <div className="kj-card p-5">
            <h2 className="mb-3 font-bold">{t("Courses par jour", "الرحلات حسب اليوم")}</h2>
            {d.daily.every((x) => x.rides === 0) ? (
              <p className="text-sm text-muted-foreground">{t("Aucune course sur la période.", "لا توجد رحلات في الفترة.")}</p>
            ) : (
              <div className="flex h-40 items-end gap-1" role="img" aria-label={t("Graphique des courses par jour", "مخطط الرحلات حسب اليوم")} dir="ltr">
                {d.daily.map((x) => (
                  <div key={x.day} className="group relative flex-1" title={`${x.day}: ${x.rides} · ${money(x.revenue)}`}>
                    <div className="w-full rounded-t bg-primary/80 transition-colors group-hover:bg-primary" style={{ height: `${Math.max(2, (x.rides / maxRides) * 100)}%` }} />
                  </div>
                ))}
              </div>
            )}
            <p className="mt-2 text-xs text-muted-foreground">{date(d.daily[0]?.day, false)} → {date(d.daily[d.daily.length - 1]?.day, false)}</p>
          </div>

          <div className="grid gap-4 lg:grid-cols-2">
            <div className="kj-card p-5">
              <h2 className="mb-3 font-bold">{t("Courses par statut", "الرحلات حسب الحالة")}</h2>
              <ul className="space-y-2 text-sm">
                {Object.entries(d.ridesByStatus).map(([s, n]) => {
                  const st = rideStatus(t, s);
                  return <li key={s} className="flex items-center justify-between"><Pill tone={st.tone}>{st.label}</Pill><span className="kj-num font-semibold">{num(n)}</span></li>;
                })}
                {totalRides === 0 && <li className="text-muted-foreground">—</li>}
              </ul>
              <h2 className="mb-3 mt-5 font-bold">{t("Livraisons par statut", "التوصيل حسب الحالة")}</h2>
              <ul className="space-y-2 text-sm">
                {Object.entries(d.deliveriesByStatus).map(([s, n]) => {
                  const st = deliveryStatus(t, s);
                  return <li key={s} className="flex items-center justify-between"><Pill tone={st.tone}>{st.label}</Pill><span className="kj-num font-semibold">{num(n)}</span></li>;
                })}
                {Object.keys(d.deliveriesByStatus).length === 0 && <li className="text-muted-foreground">—</li>}
              </ul>
            </div>
            <div className="kj-card p-5">
              <h2 className="mb-3 font-bold">{t("Meilleurs chauffeurs", "أفضل السائقين")}</h2>
              {d.topDrivers.length === 0 ? (
                <p className="text-sm text-muted-foreground">{t("Aucune course terminée.", "لا توجد رحلات مكتملة.")}</p>
              ) : (
                <ol className="space-y-2 text-sm">
                  {d.topDrivers.map((x, i) => (
                    <li key={x.driverId} className="flex items-center justify-between gap-3">
                      <span className="truncate"><span className="kj-num me-2 text-muted-foreground">{i + 1}.</span>{x.name || x.driverId.slice(0, 8)}</span>
                      <span className="kj-num shrink-0 font-semibold">{num(x.trips)} · {money(x.revenue)}</span>
                    </li>
                  ))}
                </ol>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
