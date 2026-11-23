import { useMemo, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { Ban, Bike, CarFront, Coins, Route as RouteIcon, Search } from "lucide-react";
import { supabase, must, errorMessage, type Ride, type RideRequest } from "@/lib/supabase";
import { useAuth } from "@/lib/auth";
import { useI18n } from "@/lib/i18n";
import { rideStatus, vehicleLabel } from "@/lib/labels";
import { useProfiles } from "@/lib/useProfiles";
import { useRealtimeInvalidate } from "@/lib/useRealtime";
import { cn } from "@/lib/utils";
import { EmptyState, ErrorBlock, LoadingBlock, PageHeader, Pill, ReasonDialog } from "@/components/kj";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Sheet, SheetContent, SheetHeader, SheetTitle } from "@/components/ui/sheet";

type Tab = "active" | "requests" | "completed" | "cancelled" | "all";

export default function Rides() {
  const { t, money, date, relative, num, dir } = useI18n();
  const [tab, setTab] = useState<Tab>("active");
  const [search, setSearch] = useState("");
  const [selected, setSelected] = useState<string | null>(null);

  useRealtimeInvalidate("rides-page", ["rides", "ride_requests", "offers"], [["rides-list"], ["requests-list"], ["ride-detail"]]);

  const rides = useQuery({
    queryKey: ["rides-list", tab],
    enabled: tab !== "requests",
    queryFn: async () => {
      let qb = supabase.from("rides").select("*").order("created_at", { ascending: false }).limit(300);
      if (tab === "active") qb = qb.in("status", ["en_route", "arrived", "started"]);
      if (tab === "completed") qb = qb.eq("status", "completed");
      if (tab === "cancelled") qb = qb.eq("status", "cancelled");
      return must(await qb) as Ride[];
    },
  });

  const requests = useQuery({
    queryKey: ["requests-list"],
    enabled: tab === "requests",
    queryFn: async () =>
      must(
        await supabase
          .from("ride_requests")
          .select("*")
          .in("status", ["open", "negotiating"])
          .gt("expires_at", new Date().toISOString())
          .order("created_at", { ascending: false })
          .limit(200),
      ) as RideRequest[],
    refetchInterval: 15_000,
  });

  const ids = useMemo(
    () => [
      ...(rides.data ?? []).flatMap((r) => [r.driver_id, r.passenger_id]),
      ...(requests.data ?? []).map((r) => r.passenger_id),
    ],
    [rides.data, requests.data],
  );
  const people = useProfiles(ids);

  const filteredRides = useMemo(() => {
    const s = search.trim().toLowerCase();
    if (!s) return rides.data ?? [];
    return (rides.data ?? []).filter((r) => {
      const d = people.data?.get(r.driver_id);
      const p = people.data?.get(r.passenger_id);
      return [r.pickup_label, r.dest_label, r.city, d?.name, d?.phone, p?.name, p?.phone, r.id]
        .filter(Boolean)
        .some((v) => String(v).toLowerCase().includes(s));
    });
  }, [rides.data, search, people.data]);

  const tabs: { id: Tab; label: string }[] = [
    { id: "active", label: t("En cours", "جارية") },
    { id: "requests", label: t("Demandes ouvertes", "طلبات مفتوحة") },
    { id: "completed", label: t("Terminées", "مكتملة") },
    { id: "cancelled", label: t("Annulées", "ملغاة") },
    { id: "all", label: t("Toutes", "الكل") },
  ];

  const loading = tab === "requests" ? requests.isLoading : rides.isLoading;
  const error = tab === "requests" ? requests.error : rides.error;

  return (
    <div>
      <PageHeader title={t("Courses", "الرحلات")} subtitle={t("Mises à jour en temps réel.", "تحديث في الوقت الحقيقي.")} />
      <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
        <div className="flex flex-wrap gap-1.5">
          {tabs.map((x) => (
            <button
              key={x.id}
              onClick={() => setTab(x.id)}
              className={cn(
                "rounded-full border px-3.5 py-1.5 text-sm font-semibold transition-colors",
                tab === x.id ? "border-primary bg-primary text-primary-foreground" : "bg-card text-muted-foreground hover:text-foreground",
              )}
            >
              {x.label}
            </button>
          ))}
        </div>
        {tab !== "requests" && (
          <div className="relative w-full sm:w-72">
            <Search className="pointer-events-none absolute start-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
            <Input
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder={t("Adresse, nom, téléphone…", "العنوان، الاسم، الهاتف…")}
              className="h-10 rounded-xl bg-card ps-9"
            />
          </div>
        )}
      </div>

      <div className="kj-card overflow-hidden">
        {loading && <LoadingBlock />}
        {error && <div className="p-4"><ErrorBlock error={error} /></div>}

        {tab === "requests" && requests.data && (
          requests.data.length === 0 ? (
            <EmptyState icon={RouteIcon} title={t("Aucune demande ouverte", "لا توجد طلبات مفتوحة")} />
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full min-w-[760px] text-sm">
                <thead>
                  <tr className="border-b bg-muted/40 text-xs font-semibold uppercase tracking-wider text-muted-foreground">
                    <th className="px-4 py-3 text-start">{t("Passager", "الراكب")}</th>
                    <th className="px-4 py-3 text-start">{t("Trajet", "المسار")}</th>
                    <th className="px-4 py-3 text-start">{t("Estimation / proposé", "التقدير / المقترح")}</th>
                    <th className="px-4 py-3 text-start">{t("Statut", "الحالة")}</th>
                    <th className="px-4 py-3 text-start">{t("Expire", "تنتهي")}</th>
                  </tr>
                </thead>
                <tbody>
                  {requests.data.map((r) => {
                    const st = rideStatus(t, r.status);
                    return (
                      <tr key={r.id} className="border-b last:border-0">
                        <td className="px-4 py-3 font-semibold">{people.data?.get(r.passenger_id)?.name ?? "—"}</td>
                        <td className="max-w-[320px] px-4 py-3">
                          <p className="truncate">{r.pickup_label}</p>
                          <p className="truncate text-muted-foreground">→ {r.dest_label}</p>
                        </td>
                        <td className="px-4 py-3">
                          <span className="kj-num text-muted-foreground">{money(r.estimated_fare)}</span>
                          <span className="mx-1.5 text-muted-foreground">/</span>
                          <span className="kj-num font-semibold">{money(r.proposed_fare)}</span>
                        </td>
                        <td className="px-4 py-3"><Pill tone={st.tone}>{st.label}</Pill></td>
                        <td className="px-4 py-3 text-muted-foreground">{relative(r.expires_at)}</td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )
        )}

        {tab !== "requests" && rides.data && (
          filteredRides.length === 0 ? (
            <EmptyState icon={RouteIcon} title={t("Aucune course", "لا توجد رحلات")} body={t("Rien à afficher pour ce filtre.", "لا شيء لعرضه لهذا الفلتر.")} />
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full min-w-[900px] text-sm">
                <thead>
                  <tr className="border-b bg-muted/40 text-xs font-semibold uppercase tracking-wider text-muted-foreground">
                    <th className="px-4 py-3 text-start">{t("Date", "التاريخ")}</th>
                    <th className="px-4 py-3 text-start">{t("Trajet", "المسار")}</th>
                    <th className="px-4 py-3 text-start">{t("Passager → chauffeur", "الراكب ← السائق")}</th>
                    <th className="px-4 py-3 text-end">{t("Prix", "السعر")}</th>
                    <th className="px-4 py-3 text-end">{t("Commission", "العمولة")}</th>
                    <th className="px-4 py-3 text-start">{t("Statut", "الحالة")}</th>
                  </tr>
                </thead>
                <tbody>
                  {filteredRides.map((r) => {
                    const st = rideStatus(t, r.status);
                    const VIcon = r.vehicle === "moto" ? Bike : CarFront;
                    return (
                      <tr key={r.id} onClick={() => setSelected(r.id)} className="cursor-pointer border-b last:border-0 transition-colors hover:bg-accent/40">
                        <td className="whitespace-nowrap px-4 py-3 text-muted-foreground">{date(r.created_at)}</td>
                        <td className="max-w-[300px] px-4 py-3">
                          <div className="flex items-center gap-2">
                            <VIcon className="h-4 w-4 shrink-0 text-primary" />
                            <p className="truncate">{r.pickup_label} → {r.dest_label}</p>
                          </div>
                          <p className="ps-6 text-xs text-muted-foreground">{r.city}{r.distance_km ? ` · ${num(r.distance_km, 1)} km` : ""}</p>
                        </td>
                        <td className="px-4 py-3">
                          <p className="truncate font-semibold">{people.data?.get(r.passenger_id)?.name ?? "—"}</p>
                          <p className="truncate text-xs text-muted-foreground">{people.data?.get(r.driver_id)?.name ?? "—"}</p>
                        </td>
                        <td className="kj-num px-4 py-3 text-end font-semibold">{money(r.fare)}</td>
                        <td className="kj-num px-4 py-3 text-end text-bordeaux">{r.commission != null ? money(r.commission) : "—"}</td>
                        <td className="px-4 py-3"><Pill tone={st.tone}>{st.label}</Pill></td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )
        )}
      </div>

      <Sheet open={!!selected} onOpenChange={(o) => !o && setSelected(null)}>
        <SheetContent side={dir === "rtl" ? "left" : "right"} className="w-full overflow-y-auto sm:max-w-xl">
          {selected && <RideDetail id={selected} />}
        </SheetContent>
      </Sheet>
    </div>
  );
}

interface Snapshot {
  version?: number;
  commission?: { method?: string; by_vehicle?: Record<string, number>; fixed_amount?: number };
}

export function RideDetail({ id }: { id: string }) {
  const { t, money, date, num } = useI18n();
  const { can } = useAuth();
  const qc = useQueryClient();
  const [cancelOpen, setCancelOpen] = useState(false);
  const [adjustOpen, setAdjustOpen] = useState(false);

  const q = useQuery({
    queryKey: ["ride-detail", id],
    queryFn: async () => {
      const ride = must(await supabase.from("rides").select("*").eq("id", id).single()) as Ride;
      const [offers, history, tx] = await Promise.all([
        supabase.from("offers").select("*").eq("request_id", ride.request_id).order("created_at"),
        supabase.from("ride_status_history").select("*").eq("ride_id", id).order("created_at"),
        can("finance.read")
          ? supabase.from("transactions").select("*").eq("ride_id", id).order("created_at")
          : Promise.resolve({ data: [], error: null }),
      ]);
      return { ride, offers: must(offers), history: must(history), tx: must(tx) };
    },
  });
  const people = useProfiles(q.data ? [q.data.ride.driver_id, q.data.ride.passenger_id, ...q.data.offers.map((o) => o.driver_id)] : []);

  if (q.isLoading) return <LoadingBlock />;
  if (q.error) return <ErrorBlock error={q.error} />;
  if (!q.data) return null;
  const { ride: r, offers, history, tx } = q.data;
  const st = rideStatus(t, r.status);
  const snap = (r.pricing_snapshot ?? {}) as Snapshot;
  const closed = r.status === "completed" || r.status === "cancelled";
  const driver = people.data?.get(r.driver_id);
  const passenger = people.data?.get(r.passenger_id);

  const refresh = async () => {
    await qc.invalidateQueries({ queryKey: ["ride-detail", id] });
    await qc.invalidateQueries({ queryKey: ["rides-list"] });
  };

  return (
    <div className="space-y-6">
      <SheetHeader>
        <SheetTitle className="flex items-center justify-between gap-3 text-start">
          <span className="text-lg font-extrabold">{t("Détails de la course", "تفاصيل الرحلة")}</span>
          <Pill tone={st.tone}>{st.label}</Pill>
        </SheetTitle>
        <p className="kj-num text-xs text-muted-foreground" dir="ltr">#{r.id.slice(0, 8)}</p>
      </SheetHeader>

      <div className="relative rounded-2xl border bg-card p-4">
        <div className="absolute bottom-9 start-[23px] top-9 w-px border-s-2 border-dashed border-primary/30" />
        <div className="flex items-start gap-3">
          <span className="mt-1 h-3 w-3 shrink-0 rounded-full bg-primary ring-4 ring-primary/15" />
          <div>
            <p className="text-xs text-muted-foreground">{t("Départ", "الانطلاق")}</p>
            <p className="font-semibold">{r.pickup_label}</p>
          </div>
        </div>
        <div className="mt-4 flex items-start gap-3">
          <span className="mt-1 h-3 w-3 shrink-0 rounded-full bg-bordeaux ring-4 ring-bordeaux/15" />
          <div>
            <p className="text-xs text-muted-foreground">{t("Destination", "الوجهة")}</p>
            <p className="font-semibold">{r.dest_label}</p>
          </div>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-3 text-sm">
        <Info k={t("Passager", "الراكب")} v={passenger?.name ?? "—"} sub={passenger?.phone ?? undefined} />
        <Info k={t("Chauffeur", "السائق")} v={driver?.name ?? "—"} sub={driver?.phone ?? undefined} />
        <Info k={t("Véhicule", "المركبة")} v={vehicleLabel(t, r.vehicle)} sub={[driver?.vehicle_make, driver?.vehicle_model, driver?.vehicle_plate].filter(Boolean).join(" · ") || undefined} />
        <Info k={t("Distance", "المسافة")} v={r.distance_km != null ? `${num(r.distance_km, 1)} km` : "—"} sub={r.city} />
      </div>

      <div className="rounded-2xl border bg-card p-4">
        <p className="mb-3 font-bold">{t("Prix (verrouillé à l'acceptation)", "السعر (مثبت عند القبول)")}</p>
        <div className="space-y-2 text-sm">
          <Row k={t("Estimation serveur", "تقدير الخادم")} v={money(r.estimated_fare)} />
          <Row k={t("Prix convenu", "السعر المتفق عليه")} v={money(r.fare)} strong />
          <Row
            k={`${t("Commission", "العمولة")}${snap.commission?.method === "percent" && snap.commission.by_vehicle?.[r.vehicle] != null ? ` (${snap.commission.by_vehicle[r.vehicle]} %)` : snap.commission?.method === "fixed" ? ` (${t("fixe", "ثابتة")})` : ""}`}
            v={r.commission != null ? money(r.commission) : "—"}
            tone="text-bordeaux"
          />
          <Row k={t("Gain net chauffeur", "صافي ربح السائق")} v={r.driver_net != null ? money(r.driver_net) : "—"} tone="text-success" />
          {snap.version != null && (
            <p className="pt-1 text-xs text-muted-foreground">{t(`Grille tarifaire v${snap.version}`, `جدول الأسعار v${snap.version}`)}</p>
          )}
        </div>
      </div>

      {r.cancel_reason && (
        <div className="rounded-xl bg-destructive/5 p-3 text-sm text-destructive">
          <p className="text-xs font-semibold uppercase">{t("Motif d'annulation", "سبب الإلغاء")}</p>
          <p className="mt-1">{r.cancel_reason}</p>
        </div>
      )}

      <div className="flex flex-wrap gap-2">
        {can("rides.manage") && !closed && (
          <Button variant="destructive" onClick={() => setCancelOpen(true)}>
            <Ban className="h-4 w-4" />
            {t("Annuler la course", "إلغاء الرحلة")}
          </Button>
        )}
        {can("finance.adjust") && r.status === "completed" && (
          <Button variant="outline" onClick={() => setAdjustOpen(true)}>
            <Coins className="h-4 w-4" />
            {t("Ajustement / remboursement", "تعديل / استرداد")}
          </Button>
        )}
      </div>

      <div>
        <p className="mb-2 font-bold">{t("Chronologie", "التسلسل الزمني")}</p>
        <ol className="space-y-2">
          <li className="flex items-center justify-between rounded-xl bg-muted/60 px-3 py-2 text-sm">
            <span>{t("Course créée", "إنشاء الرحلة")}</span>
            <span className="text-xs text-muted-foreground">{date(r.created_at)}</span>
          </li>
          {history.map((h) => {
            const hs = rideStatus(t, h.status);
            return (
              <li key={h.id} className="flex items-center justify-between rounded-xl bg-muted/60 px-3 py-2 text-sm">
                <span className="flex items-center gap-2">
                  <Pill tone={hs.tone}>{hs.label}</Pill>
                  {h.note && <span className="text-xs text-muted-foreground">{h.note}</span>}
                </span>
                <span className="text-xs text-muted-foreground">{date(h.created_at)}</span>
              </li>
            );
          })}
        </ol>
      </div>

      <div>
        <p className="mb-2 font-bold">{t("Négociation", "التفاوض")}</p>
        {offers.length === 0 ? (
          <p className="text-sm text-muted-foreground">—</p>
        ) : (
          <div className="space-y-2">
            {offers.map((o) => {
              const os = rideStatus(t, o.status);
              return (
                <div key={o.id} className="flex items-center justify-between rounded-xl border px-3 py-2 text-sm">
                  <div>
                    <p className="font-semibold">{people.data?.get(o.driver_id)?.name ?? "—"}</p>
                    <p className="text-xs text-muted-foreground">
                      {o.kind === "counter" ? t("Contre-offre", "عرض مضاد") : t("Offre", "عرض")} · {date(o.created_at)}
                    </p>
                  </div>
                  <div className="flex items-center gap-2">
                    <span className="kj-num font-semibold">{money(o.price)}</span>
                    <Pill tone={os.tone}>{os.label}</Pill>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>

      {can("finance.read") && (
        <div>
          <p className="mb-2 font-bold">{t("Transactions", "المعاملات")}</p>
          {tx.length === 0 ? (
            <p className="text-sm text-muted-foreground">{t("Aucune transaction.", "لا توجد معاملات.")}</p>
          ) : (
            <div className="space-y-2">
              {tx.map((x) => (
                <div key={x.id} className="flex items-center justify-between rounded-xl border px-3 py-2 text-sm">
                  <div>
                    <p className="font-semibold">{x.label ?? x.kind}</p>
                    <p className="text-xs text-muted-foreground">
                      {people.data?.get(x.user_id)?.name ?? "—"} · {date(x.created_at)}
                    </p>
                  </div>
                  <span className={cn("kj-num font-semibold", x.amount < 0 ? "text-destructive" : "text-success")}>
                    {x.amount > 0 ? "+" : ""}
                    {money(x.amount)}
                  </span>
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      <ReasonDialog
        open={cancelOpen}
        onOpenChange={setCancelOpen}
        title={t("Annuler cette course ?", "إلغاء هذه الرحلة؟")}
        description={t("Le passager et le chauffeur verront la course annulée immédiatement.", "سيرى الراكب والسائق الإلغاء فورًا.")}
        confirmLabel={t("Annuler la course", "إلغاء الرحلة")}
        destructive
        onConfirm={async (reason) => {
          try {
            must(await supabase.rpc("admin_cancel_ride", { p_ride_id: r.id, p_reason: reason }));
            toast.success(t("Course annulée", "تم إلغاء الرحلة"));
            await refresh();
          } catch (e) {
            toast.error(errorMessage(e));
            throw e;
          }
        }}
      />
      <ReasonDialog
        open={adjustOpen}
        onOpenChange={setAdjustOpen}
        title={t("Ajustement de course", "تعديل الرحلة")}
        description={t(
          "Montant positif = remboursement au passager. Montant négatif = débit. Limité au prix de la course.",
          "مبلغ موجب = استرداد للراكب. مبلغ سالب = خصم. محدود بسعر الرحلة.",
        )}
        confirmLabel={t("Enregistrer", "حفظ")}
        amountField={{ label: t("Montant (DA)", "المبلغ (دج)"), hint: t(`Maximum ${money(r.fare)}`, `الحد الأقصى ${money(r.fare)}`) }}
        onConfirm={async (reason, amount) => {
          try {
            must(await supabase.rpc("admin_adjust_ride", { p_ride_id: r.id, p_amount: Math.round(amount ?? 0), p_reason: reason }));
            toast.success(t("Ajustement enregistré", "تم حفظ التعديل"));
            await refresh();
          } catch (e) {
            toast.error(errorMessage(e));
            throw e;
          }
        }}
      />
    </div>
  );
}

function Info({ k, v, sub }: { k: string; v: string; sub?: string }) {
  return (
    <div className="rounded-xl border bg-card p-3">
      <p className="text-xs text-muted-foreground">{k}</p>
      <p className="mt-0.5 truncate font-semibold">{v}</p>
      {sub && <p className="truncate text-xs text-muted-foreground" dir="auto">{sub}</p>}
    </div>
  );
}

function Row({ k, v, strong, tone }: { k: string; v: string; strong?: boolean; tone?: string }) {
  return (
    <div className="flex items-center justify-between">
      <span className="text-muted-foreground">{k}</span>
      <span className={cn("kj-num", strong && "text-base font-bold", tone)}>{v}</span>
    </div>
  );
}
