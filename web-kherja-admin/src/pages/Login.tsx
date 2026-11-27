import { useState } from "react";
import { toast } from "sonner";
import { Loader2, Lock, Mail, ShieldAlert } from "lucide-react";
import { useAuth } from "@/lib/auth";
import { useI18n } from "@/lib/i18n";
import { supabaseConfigured } from "@/lib/supabase";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { cn } from "@/lib/utils";

export default function Login() {
  const { signIn, signOut, denied, session } = useAuth();
  const { t, lang, setLang } = useI18n();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [resetBusy, setResetBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const resetPassword = async () => {
    const address = email.trim().toLowerCase();
    if (!address) {
      setError(t("Saisissez d'abord votre adresse email.", "أدخل بريدك الإلكتروني أولاً."));
      return;
    }
    setResetBusy(true);
    setError(null);
    const { error: resetError } = await supabase.auth.resetPasswordForEmail(address, {
      redirectTo: window.location.origin,
    });
    setResetBusy(false);
    if (resetError) {
      setError(resetError.message);
      return;
    }
    toast.success(t("Si ce compte existe, un lien de réinitialisation sera envoyé.", "إذا كان الحساب موجوداً فسيتم إرسال رابط إعادة تعيين كلمة المرور."));
  };

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      await signIn(email, password);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      setError(
        /invalid login/i.test(msg)
          ? t("Email ou mot de passe incorrect.", "البريد الإلكتروني أو كلمة المرور غير صحيحة.")
          : msg,
      );
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="grid min-h-screen lg:grid-cols-[1.1fr_1fr]">
      <div className="relative hidden overflow-hidden bg-[hsl(225_64%_12%)] lg:block">
        <div className="absolute inset-0 bg-[radial-gradient(circle_at_20%_20%,hsl(219.7_100%_51.4%/0.55),transparent_45%),radial-gradient(circle_at_85%_90%,hsl(331.6_100%_26.1%/0.7),transparent_50%)]" />
        <svg className="absolute inset-0 h-full w-full opacity-[0.12]" aria-hidden>
          <defs>
            <pattern id="roads" width="120" height="120" patternUnits="userSpaceOnUse">
              <path d="M0 60 H120 M60 0 V120" stroke="white" strokeWidth="1" />
              <path d="M0 0 L120 120" stroke="white" strokeWidth="0.5" strokeDasharray="4 6" />
            </pattern>
          </defs>
          <rect width="100%" height="100%" fill="url(#roads)" />
        </svg>
        <div className="relative flex h-full flex-col justify-between p-14 text-white">
          <div className="inline-flex w-fit items-center gap-3 rounded-2xl bg-white px-4 py-3">
            <img src="/brand/kj-logo.png" alt="KHERJA" className="h-10 w-auto" />
          </div>
          <div>
            <p className="text-sm font-bold uppercase tracking-[0.25em] text-white/60">KHERJA ADMIN</p>
            <h1 className="mt-4 max-w-md text-5xl font-extrabold leading-[1.05] tracking-tight">
              {t("Pilotez chaque course, en temps réel.", "تحكّم في كل رحلة، في الوقت الحقيقي.")}
            </h1>
            <p className="mt-5 max-w-md text-base text-white/70">
              {t(
                "Validation des chauffeurs, tarification, commissions et opérations — sur une seule console sécurisée.",
                "التحقق من السائقين، التسعير، العمولات والعمليات — في لوحة تحكم آمنة واحدة.",
              )}
            </p>
          </div>
          <p className="text-xs text-white/40">© KHERJA · {t("Algérie", "الجزائر")}</p>
        </div>
      </div>

      <div className="flex flex-col bg-background">
        <div className="flex justify-end p-5">
          <div className="flex rounded-xl bg-muted p-1 text-xs font-bold">
            {(["fr", "ar"] as const).map((l) => (
              <button
                key={l}
                onClick={() => setLang(l)}
                className={cn(
                  "rounded-lg px-3 py-1.5",
                  lang === l ? "bg-card text-primary shadow-sm" : "text-muted-foreground",
                )}
              >
                {l === "fr" ? "FR" : "عربي"}
              </button>
            ))}
          </div>
        </div>
        <div className="flex flex-1 items-center justify-center px-6 pb-16">
          <div className="w-full max-w-sm">
            <img src="/brand/kj-logo.png" alt="KHERJA" className="mb-8 h-14 w-auto lg:hidden" />
            <h2 className="text-3xl font-extrabold tracking-tight">{t("Connexion", "تسجيل الدخول")}</h2>
            <p className="mt-2 text-sm text-muted-foreground">
              {t("Accès réservé à l'équipe KHERJA.", "الدخول مخصص لفريق KHERJA فقط.")}
            </p>

            {!supabaseConfigured && (
              <div className="mt-6 rounded-xl bg-destructive/10 p-3 text-sm text-destructive">
                {t("Configuration du serveur manquante.", "إعدادات الخادم مفقودة.")}
              </div>
            )}

            {denied && session ? (
              <div className="mt-8 space-y-4">
                <div className="flex gap-3 rounded-2xl border border-bordeaux/20 bg-bordeaux-soft p-4 text-sm text-bordeaux">
                  <ShieldAlert className="h-5 w-5 shrink-0" />
                  <div>
                    <p className="font-bold">{t("Accès refusé", "تم رفض الدخول")}</p>
                    <p className="mt-1 opacity-80">
                      {t(
                        `Le compte ${session.user.email ?? ""} n'a pas de rôle administrateur actif.`,
                        `الحساب ${session.user.email ?? ""} ليس لديه دور إداري نشط.`,
                      )}
                    </p>
                  </div>
                </div>
                <Button variant="outline" className="w-full" onClick={() => void signOut()}>
                  {t("Utiliser un autre compte", "استخدام حساب آخر")}
                </Button>
              </div>
            ) : (
              <form onSubmit={submit} className="mt-8 space-y-5">
                <div className="space-y-2">
                  <Label htmlFor="email">{t("Email", "البريد الإلكتروني")}</Label>
                  <div className="relative">
                    <Mail className="pointer-events-none absolute start-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
                    <Input
                      id="email"
                      type="email"
                      autoComplete="username"
                      required
                      dir="ltr"
                      value={email}
                      onChange={(e) => setEmail(e.target.value)}
                      className="h-12 rounded-xl ps-10"
                    />
                  </div>
                </div>
                <div className="space-y-2">
                  <Label htmlFor="password">{t("Mot de passe", "كلمة المرور")}</Label>
                  <div className="relative">
                    <Lock className="pointer-events-none absolute start-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
                    <Input
                      id="password"
                      type="password"
                      autoComplete="current-password"
                      required
                      dir="ltr"
                      value={password}
                      onChange={(e) => setPassword(e.target.value)}
                      className="h-12 rounded-xl ps-10"
                    />
                  </div>
                </div>
                <div className="flex justify-end">
                  <button type="button" onClick={() => void resetPassword()} disabled={resetBusy || busy}
                    className="text-xs font-semibold text-primary hover:underline disabled:opacity-50">
                    {resetBusy ? t("Envoi…", "جارٍ الإرسال…") : t("Mot de passe oublié ?", "نسيت كلمة المرور؟")}
                  </button>
                </div>
                {error && <p className="rounded-xl bg-destructive/10 p-3 text-sm text-destructive">{error}</p>}
                <Button type="submit" disabled={busy} className="h-12 w-full rounded-xl text-base font-bold">
                  {busy && <Loader2 className="h-4 w-4 animate-spin" />}
                  {t("Se connecter", "دخول")}
                </Button>
              </form>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
