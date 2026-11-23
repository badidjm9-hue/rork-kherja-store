import { useMemo, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { Ban, Check, CircleSlash, Phone, RotateCcw, Search, Star, UserX, Users, X } from "lucide-react";
import { supabase, must, errorMessage, type Profile, type Ride } from "@/lib/supabase";
import { useAuth } from "@/lib/auth";
import { useI18n } from "@/lib/i18n";
import { driverStatus, rideStatus, vehicleLabel } from "@/lib/labels";
import { cn } from "@/lib/utils";
import { Avatar, EmptyState, ErrorBlock, LoadingBlock, Pill, ReasonDialog } from "@/components/kj";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Sheet, SheetContent, SheetHeader, SheetTitle } from "@/components/ui/sheet";

type Action = { kind: "approve" | "reject" | "pending" | "suspend" | "activate"; person: Profile };

export default function PeopleTable({ role }: { role: "driver" | "passenger" }) {
  const { t, num, date, relative, dir } = useI18n();
  const { can } = useAuth();
  const qc = useQueryClient();
  const [search, setSearch] = useState("");
  const [filter, setFilter] = useState<string>(role === "driver" ? "pending" : "all");
  const [action, setAction] = useState<Action | null>(null);
  const [selected, setSelected] = useState<Profile | null>(null);

  const q = useQuery({
    queryKey: ["people", role],
    queryFn: async () =>
      must(
        await supabase.from("profiles").select("*").eq("role", role).order("created_at", { ascending: false }).limit(1000),
      ),
    refetchInterval: 20_000,
  });

  const counts = useMemo(() => {
    const list = q.data ?? [];
    return {
      all: list.length,
      pending: list.filter((p) => p.driver_status === "pending").length,
      approved: list.filter((p) => p.driver_status === "approved").length,
      rejected: list.filter((p) => p.driver_status === "rejected").length,
      online: list.filter((p) => p.is_online).length,
      suspended: list.filter((p) => p.account_status === "suspended").length,
    };
  }, [q.data]);

  const rows = useMemo(() => {
    const s = search.trim().toLowerCase();
    return (q.data ?? []).filter((p) => {
      if (filter === "pending" && p.driver_status !== "pending") return false;
      if (filter === "approved" && p.driver_status !== "approved") return false;
      if (filter === "rejected" && p.driver_status !== "rejected") return false;
      if (filter === "online" && !p.is_online) return false;
      if (filter === "suspended" && p.account_status !== "suspended") return false;
      if (!s) return true;
      return [p.name, p.phone, p.vehicle_plate, p.city, p.vehicle_make, p.vehicle_model]
        .filter(Boolean)
        .some((v) => String(v).toLowerCase().includes(s));
    });
  }, [q.data, search, filter]);

  const tabs =
    role === "driver"
      ? [
          { id: "pending", label: t("À valider", "بانتظار التحقق"), n: counts.pending },
          { id: "approved", label: t("Validés", "مقبولون"), n: counts.approved },
          { id: "online", label: t("En ligne", "متصلون"), n: counts.online },
          { id: "rejected", label: t("Refusés", "مرفوضون"), n: counts.rejected },
          { id: "suspended", label: t("Suspendus", "معلقون"), n: counts.suspended },
          { id: "all", label: t("Tous", "الكل"), n: counts.all },
        ]
      : [
          { id: "all", label: t("Tous", "الكل"), n: counts.all },
          { id: "suspended", label: t("Suspendus", "معلقون"), n: counts.suspended },
        ];

  const canApprove = can("drivers.approve");
  const canSuspend = role === "driver" ? can("drivers.manage") : can("users.manage");

  const run = async (a: Action, reason: string) => {
    try {
      if (a.kind === "approve" || a.kind === "reject" || a.kind === "pending") {
        const status = a.kind === "approve" ? "approved" : a.kind === "reject" ? "rejected" : "pending";
        must(await supabase.rpc("admin_set_driver_status", { p_user: a.person.id, p_status: status, p_reason: reason || undefined }));
      } else {
        must(
          await supabase.rpc("admin_set_account_status", {
            p_user: a.person.id,
            p_status: a.kind === "suspend" ? "suspended" : "active",
            p_reason: reason || undefined,
          }),
        );
      }
      toast.success(t("Modification enregistrée", "تم حفظ التعديل"));
      await qc.invalidateQueries({ queryKey: ["people", role] });
      setSelected(null);
    } catch (e) {
      toast.error(errorMessage(e));
      throw e;
    }
  };

  const actionCopy: Record<Action["kind"], { title: string; confirm: string; destructive?: boolean; requireReason: boolean }> = {
    approve: { title: t("Valider ce chauffeur ?", "قبول هذا السائق؟"), confirm: t("Valider", "قبول"), requireReason: false },
    reject: { title: t("Refuser ce chauffeur ?", "رفض هذا السائق؟"), confirm: t("Refuser", "رفض"), destructive: true, requireReason: true },
    pending: { title: t("Remettre en attente ?", "إعادة إلى الانتظار؟"), confirm: t("Remettre en attente", "إعادة"), requireReason: true },
    suspend: { title: t("Suspendre ce compte ?", "تعليق هذا الحساب؟"), confirm: t("Suspendre", "تعليق"), destructive: true, requireReason: true },
    activate: { title: t("Réactiver ce compte ?", "إعادة تفعيل هذا الحساب؟"), confirm: t("Réactiver", "إعادة التفعيل"), requireReason: false },
  };

  const ActionButtons = ({ p, compact }: { p: Profile; compact?: boolean }) => (
    <div className={cn("flex flex-wrap items-center gap-1.5", compact && "justify-end")}>
      {role === "driver" && canApprove && p.driver_status !== "approved" && (
        <Button size="sm" className="h-8 bg-success hover:bg-success/90" onClick={() => setAction({ kind: "approve", person: p })}>
          <Check className="h-4 w-4" />
          {t("Valider", "قبول")}
        </Button>
      )}
      {role === "driver" && canApprove && p.driver_status === "pending" && (
        <Button size="sm" variant="outline" className="h-8 text-destructive" onClick={() => setAction({ kind: "reject", person: p })}>
          <X className="h-4 w-4" />
          {t("Refuser", "رفض")}
        </Button>
      )}
      {role === "driver" && canApprove && p.driver_status === "approved" && !compact && (
        <Button size="sm" variant="outline" className="h-8" onClick={() => setAction({ kind: "pending", person: p })}>
          <CircleSlash className="h-4 w-4" />
          {t("Retirer la validation", "سحب القبول")}
        </Button>
      )}
      {canSuspend &&
        (p.account_status === "suspended" ? (
          <Button size="sm" variant="outline" className="h-8" onClick={() => setAction({ kind: "activate", person: p })}>
            <RotateCcw className="h-4 w-4" />
            {t("Réactiver", "تفعيل")}
          </Button>
        ) : (
          <Button size="sm" variant="ghost" className="h-8 text-destructive hover:bg-destructive/10 hover:text-destructive" onClick={() => setAction({ kind: "suspend", person: p })}>
            <Ban className="h-4 w-4" />
            {!compact && t("Suspendre", "تعليق")}
          </Button>
        ))}
    </div>
  );

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex flex-wrap gap-1.5">
          {tabs.map((tab) => (
            <button
              key={tab.id}
              onClick={() => setFilter(tab.id)}
              className={cn(
                "flex items-center gap-2 rounded-full border px-3.5 py-1.5 text-sm font-semibold transition-colors",
                filter === tab.id ? "border-primary bg-primary text-primary-foreground" : "bg-card text-muted-foreground hover:text-foreground",
              )}
            >
              {tab.label}
              <span className={cn("kj-num rounded-full px-1.5 text-xs", filter === tab.id ? "bg-white/20" : "bg-muted")}>{tab.n}</span>
            </button>
          ))}
        </div>
        <div className="relative w-full sm:w-72">
          <Search className="pointer-events-none absolute start-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder={role === "driver" ? t("Nom, téléphone, plaque…", "الاسم، الهاتف، اللوحة…") : t("Nom, téléphone…", "الاسم، الهاتف…")}
            className="h-10 rounded-xl bg-card ps-9"
          />
        </div>
      </div>

      <div className="kj-card overflow-hidden">
        {q.isLoading && <LoadingBlock />}
        {q.error && <div className="p-4"><ErrorBlock error={q.error} /></div>}
        {q.data && rows.length === 0 && (
          <EmptyState
            icon={role === "driver" ? UserX : Users}
            title={t("Aucun résultat", "لا توجد نتائج")}
            body={
              filter === "pending"
                ? t("Aucun chauffeur en attente de validation.", "لا يوجد سائق بانتظار التحقق.")
                : t("Aucun compte ne correspond à ce filtre.", "لا يوجد حساب مطابق لهذا الفلتر.")
            }
          />
        )}
        {rows.length > 0 && (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[820px] text-sm">
              <thead>
                <tr className="border-b bg-muted/40 text-start text-xs font-semibold uppercase tracking-wider text-muted-foreground">
                  <th className="px-4 py-3 text-start">{role === "driver" ? t("Chauffeur", "السائق") : t("Passager", "الراكب")}</th>
                  {role === "driver" && <th className="px-4 py-3 text-start">{t("Véhicule", "المركبة")}</th>}
                  <th className="px-4 py-3 text-start">{t("Ville", "المدينة")}</th>
                  <th className="px-4 py-3 text-start">{t("Courses / note", "رحلات / تقييم")}</th>
                  <th className="px-4 py-3 text-start">{t("Statut", "الحالة")}</th>
                  <th className="px-4 py-3 text-end">{t("Actions", "إجراءات")}</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((p) => {
                  const ds = driverStatus(t, p.driver_status);
                  return (
                    <tr key={p.id} className="border-b last:border-0 transition-colors hover:bg-accent/40">
                      <td className="px-4 py-3">
                        <button className="flex items-center gap-3 text-start" onClick={() => setSelected(p)}>
                          <div className="relative">
                            <Avatar name={p.name || "?"} />
                            {p.is_online && <span className="absolute -bottom-0.5 -end-0.5 h-3 w-3 rounded-full border-2 border-card bg-success" />}
                          </div>
                          <div className="min-w-0">
                            <p className="truncate font-bold hover:text-primary">{p.name || t("Sans nom", "بدون اسم")}</p>
                            <p className="kj-num text-xs text-muted-foreground" dir="ltr">{p.phone ?? "—"}</p>
                          </div>
                        </button>
                      </td>
                      {role === "driver" && (
                        <td className="px-4 py-3">
                          <p className="font-semibold">{[p.vehicle_make, p.vehicle_model].filter(Boolean).join(" ") || "—"}</p>
                          <p className="text-xs text-muted-foreground">
                            {[p.vehicle_color, p.vehicle_plate].filter(Boolean).join(" · ") || t("Non renseigné", "غير محدد")}
                          </p>
                        </td>
                      )}
                      <td className="px-4 py-3">{p.city}</td>
                      <td className="px-4 py-3">
                        <span className="kj-num font-semibold">{num(p.trips_count)}</span>
                        <span className="mx-2 text-muted-foreground">·</span>
                        <span className="inline-flex items-center gap-1">
                          <Star className="h-3.5 w-3.5 fill-warning text-warning" />
                          <span className="kj-num">{p.rating_count > 0 ? num(p.rating_avg, 1) : "—"}</span>
                        </span>
                      </td>
                      <td className="px-4 py-3">
                        <div className="flex flex-wrap gap-1.5">
                          {role === "driver" && <Pill tone={ds.tone}>{ds.label}</Pill>}
                          {p.account_status === "suspended" && <Pill tone="red">{t("Suspendu", "معلق")}</Pill>}
                          {role === "passenger" && p.account_status !== "suspended" && <Pill tone="green">{t("Actif", "نشط")}</Pill>}
                        </div>
                      </td>
                      <td className="px-4 py-3">
                        <ActionButtons p={p} compact />
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>

      <Sheet open={!!selected} onOpenChange={(o) => !o && setSelected(null)}>
        <SheetContent side={dir === "rtl" ? "left" : "right"} className="w-full overflow-y-auto sm:max-w-lg">
          {selected && (
            <PersonDetail
              p={selected}
              role={role}
              actions={<ActionButtons p={selected} />}
              fmt={{ t, num, date, relative }}
            />
          )}
        </SheetContent>
      </Sheet>

      {action && (
        <ReasonDialog
          open={!!action}
          onOpenChange={(o) => !o && setAction(null)}
          title={actionCopy[action.kind].title}
          description={action.person.name}
          confirmLabel={actionCopy[action.kind].confirm}
          destructive={actionCopy[action.kind].destructive}
          requireReason={actionCopy[action.kind].requireReason}
          onConfirm={(reason) => run(action, reason)}
        />
      )}
    </div>
  );
}

function PersonDetail({
  p,
  role,
  actions,
  fmt,
}: {
  p: Profile;
  role: "driver" | "passenger";
  actions: React.ReactNode;
  fmt: Pick<ReturnType<typeof useI18n>, "t" | "num" | "date" | "relative">;
}) {
  const { t, num, date, relative } = fmt;
  const { money } = useI18n();
  const { can } = useAuth();
  const rides = useQuery({
    queryKey: ["person-rides", p.id],
    enabled: can("rides.read"),
    queryFn: async () =>
      must(
        await supabase
          .from("rides")
          .select("*")
          .eq(role === "driver" ? "driver_id" : "passenger_id", p.id)
          .order("created_at", { ascending: false })
          .limit(20),
      ) as Ride[],
  });

  const ds = driverStatus(t, p.driver_status);
  return (
    <div className="space-y-6">
      <SheetHeader>
        <SheetTitle className="flex items-center gap-3 text-start">
          <Avatar name={p.name || "?"} className="h-12 w-12 text-base" />
          <div>
            <p className="text-lg font-extrabold">{p.name || t("Sans nom", "بدون اسم")}</p>
            <p className="kj-num flex items-center gap-1.5 text-sm font-normal text-muted-foreground" dir="ltr">
              <Phone className="h-3.5 w-3.5" />
              {p.phone ?? "—"}
            </p>
          </div>
        </SheetTitle>
      </SheetHeader>

      <div className="flex flex-wrap gap-1.5">
        {role === "driver" && <Pill tone={ds.tone}>{ds.label}</Pill>}
        <Pill tone={p.account_status === "suspended" ? "red" : "green"}>
          {p.account_status === "suspended" ? t("Suspendu", "معلق") : t("Actif", "نشط")}
        </Pill>
        {role === "driver" && <Pill tone={p.is_online ? "blue" : "gray"}>{p.is_online ? t("En ligne", "متصل") : t("Hors ligne", "غير متصل")}</Pill>}
      </div>

      {p.status_reason && (
        <div className="rounded-xl bg-muted p-3 text-sm">
          <p className="text-xs font-semibold uppercase text-muted-foreground">{t("Dernier motif", "آخر سبب")}</p>
          <p className="mt-1">{p.status_reason}</p>
        </div>
      )}

      <dl className="grid grid-cols-2 gap-3 text-sm">
        {[
          [t("Ville", "المدينة"), p.city],
          [t("Langue", "اللغة"), p.language === "ar" ? "العربية" : "Français"],
          [t("Courses", "الرحلات"), num(p.trips_count)],
          [t("Note", "التقييم"), p.rating_count > 0 ? `${num(p.rating_avg, 1)} (${p.rating_count})` : "—"],
          [t("Inscription", "التسجيل"), date(p.created_at, false)],
          ...(role === "driver"
            ? [
                [t("Véhicule", "المركبة"), [p.vehicle_make, p.vehicle_model, p.vehicle_color].filter(Boolean).join(" ") || "—"],
                [t("Plaque", "اللوحة"), p.vehicle_plate ?? "—"],
                [t("Dernière position", "آخر موقع"), relative(p.location_updated_at)],
              ]
            : []),
        ].map(([k, v]) => (
          <div key={k} className="rounded-xl border bg-card p-3">
            <dt className="text-xs text-muted-foreground">{k}</dt>
            <dd className="mt-0.5 font-semibold">{v}</dd>
          </div>
        ))}
      </dl>

      {actions}

      {can("rides.read") && (
        <div>
          <p className="mb-2 font-bold">{t("Dernières courses", "آخر الرحلات")}</p>
          {rides.isLoading && <LoadingBlock />}
          {rides.data && rides.data.length === 0 && (
            <p className="rounded-xl bg-muted p-4 text-sm text-muted-foreground">{t("Aucune course pour l'instant.", "لا توجد رحلات بعد.")}</p>
          )}
          <div className="space-y-2">
            {rides.data?.map((r) => {
              const st = rideStatus(t, r.status);
              return (
                <div key={r.id} className="rounded-xl border bg-card p-3 text-sm">
                  <div className="flex items-center justify-between gap-2">
                    <Pill tone={st.tone}>{st.label}</Pill>
                    <span className="kj-num font-semibold">{money(r.fare)}</span>
                  </div>
                  <p className="mt-2 truncate">{r.pickup_label} → {r.dest_label}</p>
                  <p className="mt-0.5 text-xs text-muted-foreground">
                    {vehicleLabel(t, r.vehicle)} · {date(r.created_at)}
                  </p>
                </div>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
}
