import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { Bell, Loader2, Send } from "lucide-react";
import { supabase, must, errorMessage, type Broadcast } from "@/lib/supabase";
import { useAuth } from "@/lib/auth";
import { useI18n } from "@/lib/i18n";
import { EmptyState, ErrorBlock, LoadingBlock, PageHeader, Pill } from "@/components/kj";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription,
  AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from "@/components/ui/alert-dialog";

const TITLE_MAX = 80;
const BODY_MAX = 500;
type Audience = "all" | "passengers" | "drivers";
type Kind = "system" | "promo";

export default function Notifications() {
  const { t, date, num } = useI18n();
  const { can } = useAuth();
  const qc = useQueryClient();
  const canSend = can("notifications.manage");
  const [audience, setAudience] = useState<Audience>("all");
  const [kind, setKind] = useState<Kind>("system");
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [confirm, setConfirm] = useState(false);

  const audienceLabel = (a: string) =>
    a === "passengers" ? t("Passagers", "الركاب") : a === "drivers" ? t("Chauffeurs", "السائقون") : t("Tous", "الجميع");
  const kindLabel = (k: string) => (k === "promo" ? t("Promotion", "عرض ترويجي") : t("Information", "معلومة"));

  const history = useQuery({
    queryKey: ["broadcasts"],
    queryFn: async () =>
      must(await supabase.from("notification_broadcasts").select("*").order("created_at", { ascending: false }).limit(50)) as Broadcast[],
  });

  const send = useMutation({
    mutationFn: async () =>
      must(await supabase.rpc("admin_send_broadcast", { p_audience: audience, p_kind: kind, p_title: title.trim(), p_body: body.trim() })),
    onSuccess: (n) => {
      toast.success(t(`Envoyée à ${num(n as number)} destinataire(s)`, `أُرسلت إلى ${num(n as number)} مستلم`));
      setTitle("");
      setBody("");
      qc.invalidateQueries({ queryKey: ["broadcasts"] });
      qc.invalidateQueries({ queryKey: ["audit"] });
    },
    onError: (e) => toast.error(errorMessage(e)),
  });

  const valid = title.trim().length > 0 && body.trim().length > 0;

  return (
    <div>
      <PageHeader
        title={t("Notifications", "الإشعارات")}
        subtitle={t(
          "Messages envoyés à tous les utilisateurs. Les promotions respectent le choix de chaque utilisateur.",
          "رسائل ترسل للمستخدمين. العروض الترويجية تحترم اختيار كل مستخدم.",
        )}
      />
      {canSend && (
        <div className="kj-card mb-6 space-y-4 p-5">
          <div className="grid gap-4 sm:grid-cols-2">
            <div className="space-y-1.5">
              <Label>{t("Destinataires", "المستلمون")}</Label>
              <div className="flex flex-wrap gap-2">
                {(["all", "passengers", "drivers"] as Audience[]).map((a) => (
                  <Button key={a} size="sm" variant={audience === a ? "default" : "outline"} onClick={() => setAudience(a)}>{audienceLabel(a)}</Button>
                ))}
              </div>
            </div>
            <div className="space-y-1.5">
              <Label>{t("Type", "النوع")}</Label>
              <div className="flex flex-wrap gap-2">
                {(["system", "promo"] as Kind[]).map((k) => (
                  <Button key={k} size="sm" variant={kind === k ? "default" : "outline"} onClick={() => setKind(k)}>{kindLabel(k)}</Button>
                ))}
              </div>
            </div>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="nt">{t("Titre", "العنوان")}</Label>
            <Input id="nt" value={title} maxLength={TITLE_MAX} onChange={(e) => setTitle(e.target.value)} />
            <p className="text-xs text-muted-foreground">{title.length}/{TITLE_MAX}</p>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="nb">{t("Message", "الرسالة")}</Label>
            <Textarea id="nb" rows={4} value={body} maxLength={BODY_MAX} onChange={(e) => setBody(e.target.value)} />
            <p className="text-xs text-muted-foreground">{body.length}/{BODY_MAX}</p>
          </div>
          <Button disabled={!valid || send.isPending} onClick={() => setConfirm(true)}>
            {send.isPending ? <Loader2 className="me-2 h-4 w-4 animate-spin" /> : <Send className="me-2 h-4 w-4" />}
            {t("Envoyer", "إرسال")}
          </Button>
        </div>
      )}

      <h2 className="mb-3 text-lg font-bold">{t("Historique", "السجل")}</h2>
      {history.isLoading && <LoadingBlock />}
      {history.error && <ErrorBlock error={history.error} />}
      {history.data && history.data.length === 0 && (
        <EmptyState icon={Bell} title={t("Aucun envoi", "لا توجد رسائل مرسلة")} body={t("Les notifications envoyées apparaîtront ici.", "ستظهر الإشعارات المرسلة هنا.")} />
      )}
      <div className="space-y-3">
        {history.data?.map((b) => (
          <div key={b.id} className="rounded-2xl border bg-card p-4 text-sm">
            <div className="flex flex-wrap items-center gap-2">
              <span className="font-bold">{b.title}</span>
              <Pill tone={b.kind === "promo" ? "bordeaux" : "blue"}>{kindLabel(b.kind)}</Pill>
              <Pill tone="gray" dot={false}>{audienceLabel(b.audience)}</Pill>
            </div>
            <p className="mt-1 whitespace-pre-line text-muted-foreground">{b.body}</p>
            <p className="mt-2 text-xs text-muted-foreground">{date(b.created_at)} · {num(b.recipients)} {t("destinataires", "مستلم")}</p>
          </div>
        ))}
      </div>

      <AlertDialog open={confirm} onOpenChange={setConfirm}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{t("Envoyer cette notification ?", "إرسال هذا الإشعار؟")}</AlertDialogTitle>
            <AlertDialogDescription>
              {audienceLabel(audience)} · {kindLabel(kind)} — {t("l'envoi ne peut pas être annulé.", "لا يمكن التراجع عن الإرسال.")}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>{t("Annuler", "إلغاء")}</AlertDialogCancel>
            <AlertDialogAction onClick={() => send.mutate()}>{t("Envoyer", "إرسال")}</AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
