import { useMemo, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { LifeBuoy, MapPin, ShieldAlert } from "lucide-react";
import { supabase, must, errorMessage, type Profile, type SosAlert, type SupportTicket } from "@/lib/supabase";
import { useAuth } from "@/lib/auth";
import { useI18n } from "@/lib/i18n";
import { EmptyState, ErrorBlock, LoadingBlock, PageHeader, Pill } from "@/components/kj";
import { Button } from "@/components/ui/button";

type Tone = "blue" | "bordeaux" | "green" | "amber" | "red" | "gray";

const CATEGORY: Record<string, [string, string]> = {
  ride: ["Course", "رحلة"],
  payment: ["Paiement", "الدفع"],
  account: ["Compte", "الحساب"],
  safety: ["Sécurité", "السلامة"],
  other: ["Autre", "أخرى"],
};

const TICKET_STATUS: Record<string, { fr: string; ar: string; tone: Tone }> = {
  open: { fr: "Ouverte", ar: "مفتوح", tone: "amber" },
  in_progress: { fr: "En cours", ar: "قيد المعالجة", tone: "blue" },
  resolved: { fr: "Résolue", ar: "تمت المعالجة", tone: "green" },
};

const SOS_STATUS: Record<string, { fr: string; ar: string; tone: Tone }> = {
  open: { fr: "Nouvelle", ar: "جديد", tone: "red" },
  acknowledged: { fr: "Prise en charge", ar: "قيد المتابعة", tone: "amber" },
  resolved: { fr: "Clôturée", ar: "مغلق", tone: "green" },
};

export default function Support() {
  const { t, date } = useI18n();
  const { can } = useAuth();
  const qc = useQueryClient();
  const canManage = can("support.manage");
  const [tab, setTab] = useState<"sos" | "tickets">("sos");
  const [busy, setBusy] = useState<string | null>(null);

  const sos = useQuery({
    queryKey: ["sos"],
    refetchInterval: 10000,
    queryFn: async () => must(await supabase.from("sos_alerts").select("*").order("created_at", { ascending: false }).limit(100)) as SosAlert[],
  });
  const tickets = useQuery({
    queryKey: ["tickets"],
    refetchInterval: 20000,
    queryFn: async () => must(await supabase.from("support_tickets").select("*").order("created_at", { ascending: false }).limit(100)) as SupportTicket[],
  });

  const ids = useMemo(() => {
    const s = new Set<string>();
    sos.data?.forEach((a) => s.add(a.user_id));
    tickets.data?.forEach((x) => s.add(x.user_id));
    return [...s].sort();
  }, [sos.data, tickets.data]);

  const people = useQuery({
    queryKey: ["support-people", ids],
    enabled: ids.length > 0,
    queryFn: async () => must(await supabase.from("profiles").select("id,name,phone").in("id", ids)) as Pick<Profile, "id" | "name" | "phone">[],
  });
  const who = (id: string) => {
    const p = people.data?.find((x) => x.id === id);
    return p?.name || p?.phone || `${id.slice(0, 8)}…`;
  };

  const run = async (key: string, fn: () => PromiseLike<{ data: unknown; error: unknown }>, done: string) => {
    setBusy(key);
    try {
      must(await fn());
      toast.success(done);
      qc.invalidateQueries({ queryKey: ["sos"] });
      qc.invalidateQueries({ queryKey: ["tickets"] });
      qc.invalidateQueries({ queryKey: ["audit"] });
    } catch (e) {
      toast.error(errorMessage(e));
    } finally {
      setBusy(null);
    }
  };

  const openSos = (sos.data ?? []).filter((a) => a.status === "open").length;
  const openTickets = (tickets.data ?? []).filter((ticket) => ticket.status !== "resolved").length;

  return (
    <div>
      <PageHeader
        title={t("Support & SOS", "الدعم وSOS")}
        subtitle={t("Alertes de sécurité et demandes d'assistance des passagers et chauffeurs.", "تنبيهات السلامة وطلبات المساعدة من الركاب والسائقين.")}
      />
      <div className="mb-4 flex gap-2">
        <Button size="sm" variant={tab === "sos" ? "default" : "outline"} onClick={() => setTab("sos")}>
          <ShieldAlert className="me-1 h-4 w-4" />
          SOS {openSos > 0 ? `(${openSos})` : ""}
        </Button>
        <Button size="sm" variant={tab === "tickets" ? "default" : "outline"} onClick={() => setTab("tickets")}>
          <LifeBuoy className="me-1 h-4 w-4" />
          {t("Demandes", "الطلبات")} {openTickets > 0 ? `(${openTickets})` : ""}
        </Button>
      </div>

      {tab === "sos" && (
        <>
          {sos.isLoading && <LoadingBlock />}
          {sos.error && <ErrorBlock error={sos.error} />}
          {sos.data && sos.data.length === 0 && (
            <EmptyState icon={ShieldAlert} title={t("Aucune alerte SOS", "لا توجد تنبيهات SOS")} body={t("Les alertes envoyées apparaîtront ici.", "ستظهر هنا التنبيهات المرسلة.")} />
          )}
          <div className="space-y-3">
            {(sos.data ?? []).map((a) => {
              const st = SOS_STATUS[a.status] ?? SOS_STATUS.open;
              return (
                <div key={a.id} className="rounded-2xl border bg-card p-4 text-sm">
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <Pill tone={st.tone}>{t(st.fr, st.ar)}</Pill>
                    <span className="text-xs text-muted-foreground">{date(a.created_at)}</span>
                  </div>
                  <p className="mt-2 font-semibold">{who(a.user_id)}</p>
                  {a.lat != null && a.lng != null ? (
                    <a
                      className="mt-1 inline-flex items-center gap-1 text-primary underline"
                      dir="ltr"
                      href={`https://www.openstreetmap.org/?mlat=${a.lat}&mlon=${a.lng}#map=17/${a.lat}/${a.lng}`}
                      target="_blank"
                      rel="noreferrer"
                    >
                      <MapPin className="h-3.5 w-3.5" />
                      {a.lat.toFixed(5)}, {a.lng.toFixed(5)}
                    </a>
                  ) : (
                    <p className="mt-1 text-xs text-muted-foreground">{t("Position indisponible", "الموقع غير متاح")}</p>
                  )}
                  {a.ride_id && <p className="mt-1 text-xs text-muted-foreground">{t("Course", "رحلة")} {a.ride_id.slice(0, 8)}</p>}
                  {canManage && a.status !== "resolved" && (
                    <div className="mt-3 flex gap-2">
                      {a.status === "open" && (
                        <Button size="sm" variant="outline" disabled={busy === a.id}
                          onClick={() => run(a.id, () => supabase.rpc("admin_set_sos_status", { p_id: a.id, p_status: "acknowledged" }), t("Alerte prise en charge", "تم التكفل بالتنبيه"))}>
                          {t("Prendre en charge", "تكفل")}
                        </Button>
                      )}
                      <Button size="sm" disabled={busy === a.id}
                        onClick={() => run(a.id, () => supabase.rpc("admin_set_sos_status", { p_id: a.id, p_status: "resolved" }), t("Alerte clôturée", "تم إغلاق التنبيه"))}>
                        {t("Clôturer", "إغلاق")}
                      </Button>
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        </>
      )}

      {tab === "tickets" && (
        <>
          {tickets.isLoading && <LoadingBlock />}
          {tickets.error && <ErrorBlock error={tickets.error} />}
          {tickets.data && tickets.data.length === 0 && (
            <EmptyState icon={LifeBuoy} title={t("Aucune demande", "لا توجد طلبات")} body={t("Les demandes de support apparaîtront ici.", "ستظهر هنا طلبات الدعم.")} />
          )}
          <div className="space-y-3">
            {(tickets.data ?? []).map((x) => {
              const st = TICKET_STATUS[x.status] ?? TICKET_STATUS.open;
              const cat = CATEGORY[x.category] ?? CATEGORY.other;
              return (
                <div key={x.id} className="rounded-2xl border bg-card p-4 text-sm">
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <div className="flex items-center gap-2">
                      <Pill tone={st.tone}>{t(st.fr, st.ar)}</Pill>
                      <span className="text-xs text-muted-foreground">{t(cat[0], cat[1])}</span>
                    </div>
                    <span className="text-xs text-muted-foreground">{date(x.created_at)}</span>
                  </div>
                  <p className="mt-2 font-semibold">{who(x.user_id)}</p>
                  <p className="mt-1 whitespace-pre-wrap">{x.message}</p>
                  {x.ride_id && <p className="mt-1 text-xs text-muted-foreground">{t("Course", "رحلة")} {x.ride_id.slice(0, 8)}</p>}
                  {canManage && x.status !== "resolved" && (
                    <div className="mt-3 flex gap-2">
                      {x.status === "open" && (
                        <Button size="sm" variant="outline" disabled={busy === x.id}
                          onClick={() => run(x.id, () => supabase.rpc("admin_set_ticket_status", { p_id: x.id, p_status: "in_progress" }), t("Demande en cours", "الطلب قيد المعالجة"))}>
                          {t("En cours", "قيد المعالجة")}
                        </Button>
                      )}
                      <Button size="sm" disabled={busy === x.id}
                        onClick={() => run(x.id, () => supabase.rpc("admin_set_ticket_status", { p_id: x.id, p_status: "resolved" }), t("Demande résolue", "تمت المعالجة"))}>
                        {t("Résoudre", "تم الحل")}
                      </Button>
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        </>
      )}
    </div>
  );
}
