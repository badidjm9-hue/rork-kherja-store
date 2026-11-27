import { useMemo, useState } from "react";
import { toast } from "sonner";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Ban, Package, Phone, Search } from "lucide-react";
import { supabase, must, errorMessage, type DeliveryOrder, type Profile } from "@/lib/supabase";
import { useAuth } from "@/lib/auth";
import { useI18n } from "@/lib/i18n";
import { deliveryStatus, vehicleLabel } from "@/lib/labels";
import { EmptyState, ErrorBlock, LoadingBlock, PageHeader, Pill, ReasonDialog } from "@/components/kj";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";

const PAGE = 50;
const STATUSES = ["open", "accepted", "picked_up", "delivered", "cancelled", "expired"];

export default function Deliveries() {
  const { t, date, money, num } = useI18n();
  const { can } = useAuth();
  const qc = useQueryClient();
  const canManage = can("deliveries.manage");
  const [target, setTarget] = useState<DeliveryOrder | null>(null);
  const [status, setStatus] = useState("");
  const [search, setSearch] = useState("");
  const [limit, setLimit] = useState(PAGE);

  const orders = useQuery({
    queryKey: ["deliveries", status, limit],
    refetchInterval: 15000,
    queryFn: async () => {
      let q = supabase.from("delivery_orders").select("*");
      if (status) q = q.eq("status", status);
      return must(await q.order("created_at", { ascending: false }).limit(limit)) as DeliveryOrder[];
    },
  });

  const ids = useMemo(() => {
    const s = new Set<string>();
    orders.data?.forEach((o) => {
      s.add(o.passenger_id);
      if (o.driver_id) s.add(o.driver_id);
    });
    return [...s].sort();
  }, [orders.data]);

  const people = useQuery({
    queryKey: ["delivery-people", ids],
    enabled: ids.length > 0,
    queryFn: async () =>
      must(await supabase.from("profiles").select("id,name,phone").in("id", ids)) as Pick<Profile, "id" | "name" | "phone">[],
  });
  const person = (id: string | null) => {
    if (!id) return "—";
    const p = people.data?.find((x) => x.id === id);
    return p?.name || p?.phone || `${id.slice(0, 8)}…`;
  };

  const applyAdminCancel = async (reason: string) => {
    if (!target) return;
    try {
      must(await supabase.rpc("admin_cancel_delivery", { p_order_id: target.id, p_reason: reason }));
      toast.success(t("Livraison annulée", "تم إلغاء طلب التوصيل"));
      await qc.invalidateQueries({ queryKey: ["deliveries"] });
      setTarget(null);
    } catch (e) {
      toast.error(errorMessage(e));
      throw e;
    }
  };

  const needle = search.trim().toLowerCase();
  const rows = (orders.data ?? []).filter((o) => {
    if (!needle) return true;
    return [o.package_description, o.recipient_name, o.recipient_phone, o.pickup_label, o.dest_label, person(o.passenger_id), person(o.driver_id)]
      .join(" ")
      .toLowerCase()
      .includes(needle);
  });

  return (
    <div>
      <PageHeader
        title={t("Livraisons", "التوصيل")}
        subtitle={t(
          "Colis, paiement à la livraison. Le téléphone du destinataire n'est visible que pour le support.",
          "الطرود، الدفع عند التسليم. رقم المستلم ظاهر للدعم فقط.",
        )}
      />

      <div className="mb-4 flex flex-wrap items-center gap-2">
        <div className="relative min-w-[220px] flex-1">
          <Search className="pointer-events-none absolute start-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <Input value={search} onChange={(e) => setSearch(e.target.value)} placeholder={t("Rechercher…", "بحث…")} className="ps-9" />
        </div>
        <Button size="sm" variant={status === "" ? "default" : "outline"} onClick={() => setStatus("")}>
          {t("Toutes", "الكل")}
        </Button>
        {STATUSES.map((s) => (
          <Button key={s} size="sm" variant={status === s ? "default" : "outline"} onClick={() => setStatus(s)}>
            {deliveryStatus(t, s).label}
          </Button>
        ))}
      </div>

      {orders.isLoading && <LoadingBlock />}
      {orders.error && <ErrorBlock error={orders.error} />}
      {orders.data && rows.length === 0 && (
        <EmptyState icon={Package} title={t("Aucune livraison", "لا توجد طلبات توصيل")} body={t("Aucun résultat pour ces filtres.", "لا نتائج لهذه التصفية.")} />
      )}

      <div className="space-y-3">
        {rows.map((o) => {
          const st = deliveryStatus(t, o.status);
          return (
            <div key={o.id} className="rounded-2xl border bg-card p-4 text-sm">
              <div className="flex flex-wrap items-center justify-between gap-2">
                <div className="flex items-center gap-2">
                  <Pill tone={st.tone}>{st.label}</Pill>
                  <span className="text-xs text-muted-foreground">{vehicleLabel(t, o.vehicle)} · {num(o.distance_km, 1)} km</span>
                </div>
                <div className="flex items-center gap-2">
                  <span className="kj-num text-base font-extrabold">{money(o.delivery_fee)}</span>
                  {canManage && ["open", "accepted", "picked_up"].includes(o.status) && (
                    <Button size="sm" variant="destructive" onClick={() => setTarget(o)}>
                      <Ban className="h-4 w-4" /> {t("Annuler", "إلغاء")}
                    </Button>
                  )}
                </div>
              </div>
              <p className="mt-2 font-semibold">{o.package_description}</p>
              <p className="mt-1 text-muted-foreground">{o.pickup_label} → {o.dest_label}</p>
              <dl className="mt-3 grid grid-cols-1 gap-2 sm:grid-cols-3">
                <div className="rounded-xl bg-muted p-2.5">
                  <dt className="text-xs text-muted-foreground">{t("Expéditeur", "المرسل")}</dt>
                  <dd className="font-semibold">{person(o.passenger_id)}</dd>
                </div>
                <div className="rounded-xl bg-muted p-2.5">
                  <dt className="text-xs text-muted-foreground">{t("Chauffeur", "السائق")}</dt>
                  <dd className="font-semibold">{person(o.driver_id)}</dd>
                </div>
                <div className="rounded-xl bg-muted p-2.5">
                  <dt className="text-xs text-muted-foreground">{t("Destinataire", "المستلم")}</dt>
                  <dd className="font-semibold">{o.recipient_name}</dd>
                  <dd className="kj-num flex items-center gap-1 text-xs text-muted-foreground" dir="ltr">
                    <Phone className="h-3 w-3" />
                    {o.recipient_phone}
                  </dd>
                </div>
              </dl>
              {o.sender_note && <p className="mt-2 rounded-lg bg-muted p-2 text-xs">{o.sender_note}</p>}
              <p className="mt-2 text-xs text-muted-foreground">
                {t("Créée", "أُنشئ")} {date(o.created_at)}
                {o.delivered_at ? ` · ${t("Livrée", "سُلّم")} ${date(o.delivered_at)}` : ""}
              </p>
            </div>
          );
        })}
      </div>

      {orders.data && orders.data.length >= limit && (
        <div className="mt-4 text-center">
          <Button variant="outline" onClick={() => setLimit((l) => l + PAGE)}>
            {t("Charger plus", "عرض المزيد")}
          </Button>
        </div>
      )}
      <ReasonDialog
        open={!!target}
        onOpenChange={(open) => !open && setTarget(null)}
        title={t("Annuler cette livraison ?", "إلغاء طلب التوصيل؟")}
        description={t("Le motif sera enregistré dans le journal d'audit et les participants seront informés.", "سيُسجل السبب في سجل التدقيق وسيتم إعلام الأطراف.")}
        confirmLabel={t("Confirmer l'annulation", "تأكيد الإلغاء")}
        destructive
        requireReason
        onConfirm={applyAdminCancel}
      />
    </div>
  );
}
