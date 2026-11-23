import { useState, type ReactNode } from "react";
import type { LucideIcon } from "lucide-react";
import { Loader2 } from "lucide-react";
import { cn } from "@/lib/utils";
import type { Tone } from "@/lib/labels";
import { useI18n } from "@/lib/i18n";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

const toneClass: Record<Tone, string> = {
  blue: "bg-accent text-accent-foreground ring-primary/15",
  bordeaux: "bg-bordeaux-soft text-bordeaux ring-bordeaux/15",
  green: "bg-success-soft text-success ring-success/20",
  amber: "bg-warning-soft text-warning ring-warning/20",
  red: "bg-destructive/10 text-destructive ring-destructive/20",
  gray: "bg-muted text-muted-foreground ring-border",
};

export function Pill({ tone, children, dot = true }: { tone: Tone; children: ReactNode; dot?: boolean }) {
  return (
    <span
      className={cn(
        "inline-flex items-center gap-1.5 whitespace-nowrap rounded-full px-2.5 py-0.5 text-xs font-semibold ring-1 ring-inset",
        toneClass[tone],
      )}
    >
      {dot && <span className="h-1.5 w-1.5 rounded-full bg-current" />}
      {children}
    </span>
  );
}

export function PageHeader({
  title,
  subtitle,
  actions,
}: {
  title: string;
  subtitle?: string;
  actions?: ReactNode;
}) {
  return (
    <div className="mb-6 flex flex-wrap items-end justify-between gap-4">
      <div>
        <h1 className="text-[26px] font-extrabold tracking-tight text-foreground">{title}</h1>
        {subtitle && <p className="mt-1 text-sm text-muted-foreground">{subtitle}</p>}
      </div>
      {actions && <div className="flex flex-wrap items-center gap-2">{actions}</div>}
    </div>
  );
}

export function StatCard({
  label,
  value,
  icon: Icon,
  tone = "blue",
  hint,
}: {
  label: string;
  value: ReactNode;
  icon: LucideIcon;
  tone?: Tone;
  hint?: ReactNode;
}) {
  return (
    <div className="kj-card group relative overflow-hidden p-5 transition-transform duration-200 hover:-translate-y-0.5">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">{label}</p>
          <p className="kj-num mt-2 truncate text-2xl font-semibold text-foreground">{value}</p>
          {hint && <p className="mt-1 text-xs text-muted-foreground">{hint}</p>}
        </div>
        <span className={cn("grid h-10 w-10 shrink-0 place-items-center rounded-xl ring-1 ring-inset", toneClass[tone])}>
          <Icon className="h-5 w-5" />
        </span>
      </div>
    </div>
  );
}

export function EmptyState({ icon: Icon, title, body }: { icon: LucideIcon; title: string; body?: string }) {
  return (
    <div className="flex flex-col items-center justify-center px-6 py-16 text-center">
      <span className="grid h-14 w-14 place-items-center rounded-2xl bg-accent text-primary">
        <Icon className="h-6 w-6" />
      </span>
      <p className="mt-4 font-semibold text-foreground">{title}</p>
      {body && <p className="mt-1 max-w-sm text-sm text-muted-foreground">{body}</p>}
    </div>
  );
}

export function Spinner({ className }: { className?: string }) {
  return <Loader2 className={cn("h-5 w-5 animate-spin text-primary", className)} />;
}

export function LoadingBlock() {
  return (
    <div className="flex items-center justify-center py-16">
      <Spinner className="h-6 w-6" />
    </div>
  );
}

export function ErrorBlock({ error }: { error: unknown }) {
  const { t } = useI18n();
  const msg = error instanceof Error ? error.message : String(error);
  return (
    <div className="rounded-xl border border-destructive/30 bg-destructive/5 p-4 text-sm text-destructive">
      <p className="font-semibold">{t("Impossible de charger les données", "تعذر تحميل البيانات")}</p>
      <p className="mt-1 opacity-80">{msg}</p>
    </div>
  );
}

/** Confirmation dialog that can require a written reason (stored in the audit log). */
export function ReasonDialog({
  open,
  onOpenChange,
  title,
  description,
  confirmLabel,
  destructive,
  requireReason = true,
  amountField,
  onConfirm,
}: {
  open: boolean;
  onOpenChange: (o: boolean) => void;
  title: string;
  description?: string;
  confirmLabel: string;
  destructive?: boolean;
  requireReason?: boolean;
  amountField?: { label: string; hint?: string };
  onConfirm: (reason: string, amount: number | null) => Promise<void>;
}) {
  const { t } = useI18n();
  const [reason, setReason] = useState("");
  const [amount, setAmount] = useState("");
  const [busy, setBusy] = useState(false);
  const amountNum = amount.trim() === "" ? null : Number(amount);
  const amountOk = !amountField || (amountNum !== null && Number.isFinite(amountNum) && amountNum !== 0);
  const ok = (!requireReason || reason.trim().length >= 3) && amountOk;

  return (
    <Dialog
      open={open}
      onOpenChange={(o) => {
        if (!busy) {
          onOpenChange(o);
          if (!o) {
            setReason("");
            setAmount("");
          }
        }
      }}
    >
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>{title}</DialogTitle>
          {description && <DialogDescription>{description}</DialogDescription>}
        </DialogHeader>
        <div className="space-y-4">
          {amountField && (
            <div className="space-y-1.5">
              <Label>{amountField.label}</Label>
              <Input
                type="number"
                inputMode="numeric"
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
                className="kj-num"
              />
              {amountField.hint && <p className="text-xs text-muted-foreground">{amountField.hint}</p>}
            </div>
          )}
          <div className="space-y-1.5">
            <Label>
              {t("Motif", "السبب")}
              {!requireReason && <span className="text-muted-foreground"> · {t("facultatif", "اختياري")}</span>}
            </Label>
            <Textarea
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              rows={3}
              placeholder={t("Expliquez la raison (enregistrée dans le journal d'audit)", "اشرح السبب (يُسجل في سجل التدقيق)")}
            />
          </div>
        </div>
        <DialogFooter className="gap-2">
          <Button variant="outline" disabled={busy} onClick={() => onOpenChange(false)}>
            {t("Annuler", "إلغاء")}
          </Button>
          <Button
            variant={destructive ? "destructive" : "default"}
            disabled={!ok || busy}
            onClick={async () => {
              setBusy(true);
              try {
                await onConfirm(reason.trim(), amountNum);
                setReason("");
                setAmount("");
                onOpenChange(false);
              } finally {
                setBusy(false);
              }
            }}
          >
            {busy && <Loader2 className="h-4 w-4 animate-spin" />}
            {confirmLabel}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

export function Avatar({ name, className }: { name: string; className?: string }) {
  const initials =
    name
      .split(/\s+/)
      .filter(Boolean)
      .slice(0, 2)
      .map((p) => p[0]?.toUpperCase())
      .join("") || "?";
  return (
    <span
      className={cn(
        "grid h-9 w-9 shrink-0 place-items-center rounded-full bg-gradient-to-br from-primary to-[hsl(219.7_100%_38%)] text-xs font-bold text-white",
        className,
      )}
    >
      {initials}
    </span>
  );
}
