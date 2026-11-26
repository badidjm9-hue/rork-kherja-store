import { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { Check, ExternalLink, FileText, X } from "lucide-react";
import { supabase, must, errorMessage, type DriverDocument } from "@/lib/supabase";
import { useAuth } from "@/lib/auth";
import { useI18n } from "@/lib/i18n";
import { DOC_TYPES, docTypeLabel, driverStatus } from "@/lib/labels";
import { ErrorBlock, LoadingBlock, Pill, ReasonDialog } from "@/components/kj";
import { Button } from "@/components/ui/button";

const BUCKET = "driver-documents";
const SIGNED_URL_SECONDS = 300;

type Row = DriverDocument & { url: string | null };

/** Review panel for one driver's uploaded documents (private bucket, short-lived signed links). */
export default function DriverDocuments({ driverId }: { driverId: string }) {
  const { t, date } = useI18n();
  const { can } = useAuth();
  const qc = useQueryClient();
  const canReview = can("drivers.approve");
  const [rejecting, setRejecting] = useState<DriverDocument | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);

  const docs = useQuery({
    queryKey: ["driver-docs", driverId],
    queryFn: async (): Promise<Row[]> => {
      const rows = must(
        await supabase.from("driver_documents").select("*").eq("driver_id", driverId).order("uploaded_at", { ascending: false }),
      ) as DriverDocument[];
      return Promise.all(
        rows.map(async (d) => {
          const { data } = await supabase.storage.from(BUCKET).createSignedUrl(d.storage_path, SIGNED_URL_SECONDS);
          return { ...d, url: data?.signedUrl ?? null };
        }),
      );
    },
  });

  const refresh = () => {
    qc.invalidateQueries({ queryKey: ["driver-docs", driverId] });
    qc.invalidateQueries({ queryKey: ["audit"] });
  };

  const review = async (d: DriverDocument, status: "approved" | "rejected", reason?: string) => {
    setBusyId(d.id);
    try {
      must(await supabase.rpc("admin_review_document", { p_id: d.id, p_status: status, p_reason: reason || undefined }));
      toast.success(status === "approved" ? t("Document validé", "تم قبول الوثيقة") : t("Document refusé", "تم رفض الوثيقة"));
      refresh();
    } catch (e) {
      toast.error(errorMessage(e));
    } finally {
      setBusyId(null);
    }
  };

  return (
    <div>
      <p className="mb-2 font-bold">{t("Documents", "الوثائق")}</p>
      {docs.isLoading && <LoadingBlock />}
      {docs.error && <ErrorBlock error={docs.error} />}
      {docs.data && (
        <div className="space-y-2">
          {DOC_TYPES.map((type) => {
            const d = docs.data.find((x) => x.doc_type === type);
            if (!d) {
              return (
                <div key={type} className="flex items-center justify-between rounded-xl border border-dashed bg-card p-3 text-sm">
                  <span>{docTypeLabel(t, type)}</span>
                  <Pill tone="gray">{t("Non envoyé", "لم يُرسل")}</Pill>
                </div>
              );
            }
            const st = driverStatus(t, d.status);
            const isImage = d.mime_type.startsWith("image/");
            return (
              <div key={type} className="rounded-xl border bg-card p-3 text-sm">
                <div className="flex items-center justify-between gap-2">
                  <span className="font-semibold">{docTypeLabel(t, type)}</span>
                  <Pill tone={st.tone}>{st.label}</Pill>
                </div>
                <p className="mt-0.5 text-xs text-muted-foreground">{t("Envoyé le", "أُرسل في")} {date(d.uploaded_at)}</p>
                {d.url ? (
                  <a href={d.url} target="_blank" rel="noopener noreferrer" className="mt-2 block">
                    {isImage ? (
                      <img src={d.url} alt={docTypeLabel(t, type)} className="max-h-48 w-full rounded-lg border object-contain" loading="lazy" />
                    ) : (
                      <span className="inline-flex items-center gap-1.5 text-primary underline">
                        <FileText className="h-4 w-4" />
                        {t("Ouvrir le fichier", "فتح الملف")}
                        <ExternalLink className="h-3.5 w-3.5" />
                      </span>
                    )}
                  </a>
                ) : (
                  <p className="mt-2 text-xs text-destructive">{t("Fichier introuvable.", "الملف غير موجود.")}</p>
                )}
                {d.status === "rejected" && d.reason && (
                  <p className="mt-2 rounded-lg bg-muted p-2 text-xs">{d.reason}</p>
                )}
                {canReview && d.status === "pending" && (
                  <div className="mt-3 flex gap-2">
                    <Button size="sm" className="h-8 bg-success hover:bg-success/90" disabled={busyId === d.id} onClick={() => review(d, "approved")}>
                      <Check className="me-1 h-4 w-4" />
                      {t("Valider", "قبول")}
                    </Button>
                    <Button size="sm" variant="outline" className="h-8 text-destructive" disabled={busyId === d.id} onClick={() => setRejecting(d)}>
                      <X className="me-1 h-4 w-4" />
                      {t("Refuser", "رفض")}
                    </Button>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}
      <ReasonDialog
        open={!!rejecting}
        onOpenChange={(o) => !o && setRejecting(null)}
        title={t("Refuser ce document", "رفض هذه الوثيقة")}
        description={t("Le motif sera visible par le chauffeur et conservé dans le journal d'audit.", "سيظهر السبب للسائق ويُحفظ في سجل التدقيق.")}
        confirmLabel={t("Refuser", "رفض")}
        destructive
        onConfirm={async (reason) => {
          if (rejecting) await review(rejecting, "rejected", reason);
          setRejecting(null);
        }}
      />
    </div>
  );
}
