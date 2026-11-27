import { useMemo, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { Car, Search } from "lucide-react";
import { supabase, must, errorMessage, type Vehicle, type Profile } from "@/lib/supabase";
import { useAuth } from "@/lib/auth";
import { useI18n } from "@/lib/i18n";
import { vehicleLabel } from "@/lib/labels";
import { EmptyState, ErrorBlock, LoadingBlock, PageHeader, Pill, ReasonDialog } from "@/components/kj";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";

const PAGE = 50;

export default function Vehicles() {
  const { t, date } = useI18n();
  const { can } = useAuth();
  const qc = useQueryClient();
  const canManage = can("vehicles.manage");
  const [status, setStatus] = useState("");
  const [category, setCategory] = useState("");
  const [search, setSearch] = useState("");
  const [limit, setLimit] = useState(PAGE);
  const [target, setTarget] = useState<{ v: Vehicle; to: "active" | "suspended" } | null>(null);

  const vehicles = useQuery({
    queryKey: ["vehicles", status, category, limit],
    queryFn: async () => {
      let q = supabase.from("vehicles").select("*");
      if (status) q = q.eq("status", status);
      if (category) q = q.eq("category", category);
      return must(await q.order("created_at", { ascending: false }).limit(limit)) as Vehicle[];
    },
  });

  const ids = useMemo(() => [...new Set((vehicles.data ?? []).map((v) => v.driver_id))].sort(), [vehicles.data]);
  const people = useQuery({
    queryKey: ["vehicle-drivers", ids],
    enabled: ids.length > 0,
    queryFn: async () => must(await supabase.from("profiles").select("id,name,phone").in("id", ids)) as Pick<Profile, "id" | "name" | "phone">[],
  });
  const owner = (id: string) => {
    const p = people.data?.find((x) => x.id === id);
    return p?.name || p?.phone || `${id.slice(0, 8)}…`;
  };

  const needle = search.trim().toLowerCase();
  const rows = (vehicles.data ?? []).filter(
    (v) => !needle || [v.make, v.model, v.plate, v.color, owner(v.driver_id)].join(" ").toLowerCase().includes(needle),
  );

  const apply = async (reason: string) => {
    if (!target) return;
    try {
      must(await supabase.rpc("admin_set_vehicle_status", { p_id: target.v.id, p_status: target.to, p_reason: reason || undefined }));
      toast.success(target.to === "suspended" ? t("Véhicule suspendu", "تم تعليق المركبة") : t("Véhicule réactivé", "تم تفعيل المركبة"));
      qc.invalidateQueries({ queryKey: ["vehicles"] });
      qc.invalidateQueries({ queryKey: ["audit"] });
    } catch (e) {
      toast.error(errorMessage(e));
      throw e;
    }
  };

  return (
    <div>
      <PageHeader
        title={t("Véhicules", "المركبات")}
        subtitle={t("Véhicules enregistrés par les chauffeurs. Une suspension retire le véhicule du service.", "المركبات المسجلة من السائقين. التعليق يوقف المركبة عن الخدمة.")}
      />
      <div className="mb-4 flex flex-wrap items-center gap-2">
        <div className="relative min-w-[220px] flex-1">
          <Search className="pointer-events-none absolute start-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <Input value={search} onChange={(e) => setSearch(e.target.value)} placeholder={t("Plaque, marque, chauffeur…", "اللوحة، الماركة، السائق…")} className="ps-9" />
        </div>
        {[["", t("Tous", "الكل")], ["active", t("Actifs", "نشطة")], ["suspended", t("Suspendus", "معلّقة")]].map(([v, l]) => (
          <Button key={v} size="sm" variant={status === v ? "default" : "outline"} onClick={() => setStatus(v)}>{l}</Button>
        ))}
        {[["", t("Tout type", "كل الأنواع")], ["car", vehicleLabel(t, "car")], ["moto", vehicleLabel(t, "moto")]].map(([v, l]) => (
          <Button key={"c" + v} size="sm" variant={category === v ? "default" : "outline"} onClick={() => setCategory(v)}>{l}</Button>
        ))}
      </div>

      {vehicles.isLoading && <LoadingBlock />}
      {vehicles.error && <ErrorBlock error={vehicles.error} />}
      {people.isLoading && <LoadingBlock />}
      {people.error && <ErrorBlock error={people.error} />}
      {vehicles.data && rows.length === 0 && (
        <EmptyState icon={Car} title={t("Aucun véhicule", "لا توجد مركبات")} body={t("Aucun résultat pour ces filtres.", "لا نتائج لهذه التصفية.")} />
      )}
      <div className="space-y-3">
        {rows.map((v) => (
          <div key={v.id} className="rounded-2xl border bg-card p-4 text-sm">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <div className="flex flex-wrap items-center gap-2">
                <span className="text-base font-bold">{v.make} {v.model}{v.year ? ` · ${v.year}` : ""}</span>
                <Pill tone={v.status === "active" ? "green" : "red"}>{v.status === "active" ? t("Actif", "نشطة") : t("Suspendu", "معلّقة")}</Pill>
                {v.is_primary && <Pill tone="blue">{t("Principal", "أساسية")}</Pill>}
              </div>
              {canManage && (
                v.status === "active" ? (
                  <Button size="sm" variant="outline" className="text-destructive" onClick={() => setTarget({ v, to: "suspended" })}>{t("Suspendre", "تعليق")}</Button>
                ) : (
                  <Button size="sm" variant="outline" onClick={() => setTarget({ v, to: "active" })}>{t("Réactiver", "تفعيل")}</Button>
                )
              )}
            </div>
            <p className="mt-1 text-muted-foreground">
              <span className="kj-num font-semibold text-foreground" dir="ltr">{v.plate}</span> · {vehicleLabel(t, v.category)} · {v.color || "—"} · {v.seats} {t("places", "مقاعد")}
            </p>
            <p className="mt-1 text-xs text-muted-foreground">{t("Chauffeur", "السائق")}: {owner(v.driver_id)} · {t("Ajouté", "أُضيفت")} {date(v.created_at)}</p>
            {v.status === "suspended" && v.suspended_reason && <p className="mt-2 rounded-lg bg-muted p-2 text-xs">{v.suspended_reason}</p>}
          </div>
        ))}
      </div>
      {vehicles.data && vehicles.data.length >= limit && (
        <div className="mt-4 text-center">
          <Button variant="outline" onClick={() => setLimit((l) => l + PAGE)}>{t("Charger plus", "عرض المزيد")}</Button>
        </div>
      )}
      <ReasonDialog
        open={!!target}
        onOpenChange={(o) => !o && setTarget(null)}
        title={target?.to === "suspended" ? t("Suspendre ce véhicule", "تعليق هذه المركبة") : t("Réactiver ce véhicule", "تفعيل هذه المركبة")}
        description={t("Action enregistrée dans le journal d'audit.", "يُسجل الإجراء في سجل التدقيق.")}
        confirmLabel={target?.to === "suspended" ? t("Suspendre", "تعليق") : t("Réactiver", "تفعيل")}
        destructive={target?.to === "suspended"}
        requireReason={target?.to === "suspended"}
        onConfirm={apply}
      />
    </div>
  );
}
