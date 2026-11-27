import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { ChevronDown, ScrollText } from "lucide-react";
import { supabase, must, type AuditLog } from "@/lib/supabase";
import { useAuth } from "@/lib/auth";
import { useI18n } from "@/lib/i18n";
import { auditAction } from "@/lib/labels";
import { diffConfig } from "@/lib/pricing";
import { cn } from "@/lib/utils";
import { EmptyState, ErrorBlock, LoadingBlock, PageHeader } from "@/components/kj";
import { Button } from "@/components/ui/button";

const PAGE = 50;

const ENTITY_TYPES = ["profile", "ride", "delivery_order", "pricing_version", "admin_user"];

export default function Audit() {
  const { t, date } = useI18n();
  const { can } = useAuth();
  const [entity, setEntity] = useState("");
  const [action, setAction] = useState("");
  const [limit, setLimit] = useState(PAGE);
  const [open, setOpen] = useState<number | null>(null);

  const logs = useQuery({
    queryKey: ["audit", entity, action, limit],
    queryFn: async () => {
      let q = supabase.from("audit_logs").select("*");
      if (entity) q = q.eq("entity_type", entity);
      if (action) q = q.eq("action", action);
      return must(await q.order("created_at", { ascending: false }).limit(limit)) as AuditLog[];
    },
  });
  const admins = useQuery({
    queryKey: ["admin-names"],
    enabled: can("admins.manage"),
    queryFn: async () => must(await supabase.from("admin_users").select("user_id,display_name")),
  });
  const actorName = (id: string | null) =>
    id ? admins.data?.find((a) => a.user_id === id)?.display_name ?? `${id.slice(0, 8)}…` : t("Système", "النظام");

  const actions = [
    "driver.approved",
    "driver.rejected",
    "driver.pending",
    "account.active",
    "account.suspended",
    "pricing.draft",
    "pricing.publish",
    "pricing.restore",
    "pricing.unschedule",
    "ride.cancel",
    "ride.adjust",
    "delivery.cancel",
    "admin.set",
    "admin.permissions",
  ];

  return (
    <div>
      <PageHeader
        title={t("Journal d'audit", "سجل التدقيق")}
        subtitle={t("Chaque action sensible est enregistrée avec son auteur, son motif et l'avant/après", "كل إجراء حساس مسجل مع منفذه وسببه وما قبله وما بعده")}
        actions={
          <div className="flex gap-2">
            <select value={entity} onChange={(e) => setEntity(e.target.value)} className="h-10 rounded-xl border bg-card px-3 text-sm">
              <option value="">{t("Toutes les entités", "كل الكيانات")}</option>
              {ENTITY_TYPES.map((e) => (
                <option key={e} value={e}>
                  {e}
                </option>
              ))}
            </select>
            <select value={action} onChange={(e) => setAction(e.target.value)} className="h-10 rounded-xl border bg-card px-3 text-sm">
              <option value="">{t("Toutes les actions", "كل الإجراءات")}</option>
              {actions.map((a) => (
                <option key={a} value={a}>
                  {auditAction(t, a)}
                </option>
              ))}
            </select>
          </div>
        }
      />

      <div className="kj-card divide-y">
        {logs.isLoading && <LoadingBlock />}
        {logs.error && <ErrorBlock error={logs.error} />}
        {logs.data?.length === 0 && <EmptyState icon={ScrollText} title={t("Aucune entrée", "لا توجد إدخالات")} />}
        {logs.data?.map((l) => {
          const changes = diffConfig(l.before_data ?? {}, l.after_data ?? {});
          const isOpen = open === l.id;
          return (
            <div key={l.id}>
              <button onClick={() => setOpen(isOpen ? null : l.id)} className="flex w-full items-center gap-4 px-5 py-3.5 text-start hover:bg-muted/40">
                <div className="min-w-0 flex-1">
                  <p className="font-semibold">{auditAction(t, l.action)}</p>
                  <p className="truncate text-xs text-muted-foreground">
                    {actorName(l.actor_id)} · {l.entity_type}
                    {l.entity_id && ` · ${l.entity_id.slice(0, 8)}…`}
                    {l.reason && ` · « ${l.reason} »`}
                  </p>
                </div>
                <span className="shrink-0 text-xs text-muted-foreground">{date(l.created_at)}</span>
                <ChevronDown className={cn("h-4 w-4 shrink-0 text-muted-foreground transition-transform", isOpen && "rotate-180")} />
              </button>
              {isOpen && (
                <div className="space-y-2 bg-muted/30 px-5 py-4 text-xs">
                  {l.reason && (
                    <p>
                      <span className="font-semibold">{t("Motif", "السبب")} :</span> {l.reason}
                    </p>
                  )}
                  {changes.length === 0 ? (
                    <p className="text-muted-foreground">{t("Aucune différence enregistrée", "لا توجد اختلافات مسجلة")}</p>
                  ) : (
                    <div className="max-h-72 space-y-1 overflow-y-auto">
                      {changes.map((c) => (
                        <div key={c.path} className="flex items-center justify-between gap-3 rounded-lg bg-card px-3 py-1.5">
                          <span className="truncate font-mono text-muted-foreground">{c.path}</span>
                          <span className="kj-num shrink-0">
                            <span className="text-destructive line-through">{JSON.stringify(c.from) ?? "—"}</span>{" "}
                            <span className="font-semibold text-success">{JSON.stringify(c.to) ?? "—"}</span>
                          </span>
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              )}
            </div>
          );
        })}
      </div>
      {logs.data && logs.data.length >= limit && (
        <div className="mt-4 flex justify-center">
          <Button variant="outline" onClick={() => setLimit((n) => n + PAGE)}>
            {t("Charger plus", "تحميل المزيد")}
          </Button>
        </div>
      )}
    </div>
  );
}
