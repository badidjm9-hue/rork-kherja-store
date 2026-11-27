import { useState, type FormEvent } from "react";
import { toast } from "sonner";
import { NavLink, Outlet } from "react-router-dom";
import {
  BadgeDollarSign,
  CarFront,
  ClipboardList,
  LayoutDashboard,
  LifeBuoy,
  LogOut,
  Package,
  Car,
  BarChart3,
  Bell,
  Settings,
  Map as MapIcon,
  Menu,
  Route,
  ShieldCheck,
  Users,
  type LucideIcon,
} from "lucide-react";
import { useAuth, type Permission } from "@/lib/auth";
import { useI18n } from "@/lib/i18n";
import { roleLabel } from "@/lib/labels";
import { cn } from "@/lib/utils";
import { Sheet, SheetContent } from "@/components/ui/sheet";
import { Avatar } from "@/components/kj";
import { supabase } from "@/lib/supabase";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";

interface NavItem {
  to: string;
  fr: string;
  ar: string;
  icon: LucideIcon;
  perm: Permission;
}

const NAV: NavItem[] = [
  { to: "/", fr: "Vue d'ensemble", ar: "نظرة عامة", icon: LayoutDashboard, perm: "overview.read" },
  { to: "/live", fr: "Carte en direct", ar: "الخريطة المباشرة", icon: MapIcon, perm: "rides.read" },
  { to: "/rides", fr: "Courses", ar: "الرحلات", icon: Route, perm: "rides.read" },
  { to: "/deliveries", fr: "Livraisons", ar: "التوصيل", icon: Package, perm: "deliveries.read" },
  { to: "/drivers", fr: "Chauffeurs", ar: "السائقون", icon: CarFront, perm: "drivers.read" },
  { to: "/vehicles", fr: "Véhicules", ar: "المركبات", icon: Car, perm: "vehicles.read" },
  { to: "/passengers", fr: "Passagers", ar: "الركاب", icon: Users, perm: "users.read" },
  { to: "/pricing", fr: "Tarifs & commissions", ar: "الأسعار والعمولات", icon: BadgeDollarSign, perm: "pricing.read" },
  { to: "/reports", fr: "Rapports", ar: "التقارير", icon: BarChart3, perm: "reports.read" },
  { to: "/notifications", fr: "Notifications", ar: "الإشعارات", icon: Bell, perm: "notifications.read" },
  { to: "/settings", fr: "Paramètres", ar: "الإعدادات", icon: Settings, perm: "settings.read" },
  { to: "/admins", fr: "Administrateurs", ar: "المسؤولون", icon: ShieldCheck, perm: "admins.manage" },
  { to: "/support", fr: "Support & SOS", ar: "الدعم وSOS", icon: LifeBuoy, perm: "support.read" },
  { to: "/audit", fr: "Journal d'audit", ar: "سجل التدقيق", icon: ClipboardList, perm: "audit.read" },
];

export function allowedNav(can: (p: Permission) => boolean) {
  return NAV.filter((n) => can(n.perm));
}

function SidebarBody({ onNavigate }: { onNavigate?: () => void }) {
  const { admin, can, signOut } = useAuth();
  const { t, lang, setLang } = useI18n();
  const [passwordOpen, setPasswordOpen] = useState(false);
  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [passwordBusy, setPasswordBusy] = useState(false);

  const changePassword = async (e: FormEvent) => {
    e.preventDefault();
    if (newPassword.length < 8) {
      toast.error(t("Le mot de passe doit contenir au moins 8 caractères.", "يجب أن تتكون كلمة المرور من 8 أحرف على الأقل."));
      return;
    }
    if (newPassword !== confirmPassword) {
      toast.error(t("Les mots de passe ne correspondent pas.", "كلمتا المرور غير متطابقتين."));
      return;
    }
    setPasswordBusy(true);
    const { error } = await supabase.auth.updateUser({ password: newPassword });
    setPasswordBusy(false);
    if (error) {
      toast.error(error.message);
      return;
    }
    toast.success(t("Mot de passe mis à jour.", "تم تحديث كلمة المرور."));
    setPasswordOpen(false);
    setNewPassword("");
    setConfirmPassword("");
  };
  return (
    <div className="flex h-full flex-col">
      <div className="flex items-center gap-3 px-5 pb-4 pt-6">
        <img src="/brand/kj-logo.png" alt="KHERJA" className="h-11 w-auto" />
        <span className="rounded-md bg-bordeaux px-1.5 py-0.5 text-[10px] font-bold tracking-[0.18em] text-white">
          ADMIN
        </span>
      </div>
      <nav className="flex-1 space-y-1 overflow-y-auto px-3 py-2">
        {allowedNav(can).map((item) => (
          <NavLink
            key={item.to}
            to={item.to}
            end={item.to === "/"}
            onClick={onNavigate}
            className={({ isActive }) =>
              cn(
                "group flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-semibold transition-all",
                isActive
                  ? "bg-primary text-primary-foreground shadow-[0_8px_20px_-10px_hsl(var(--primary))]"
                  : "text-sidebar-foreground hover:bg-sidebar-accent hover:text-sidebar-accent-foreground",
              )
            }
          >
            <item.icon className="h-[18px] w-[18px] shrink-0" />
            <span className="truncate">{t(item.fr, item.ar)}</span>
          </NavLink>
        ))}
      </nav>
      <div className="space-y-3 border-t border-sidebar-border p-4">
        <div className="flex rounded-xl bg-muted p-1 text-xs font-bold">
          {(["fr", "ar"] as const).map((l) => (
            <button
              key={l}
              onClick={() => setLang(l)}
              className={cn(
                "flex-1 rounded-lg py-1.5 transition-colors",
                lang === l ? "bg-card text-primary shadow-sm" : "text-muted-foreground hover:text-foreground",
              )}
            >
              {l === "fr" ? "Français" : "العربية"}
            </button>
          ))}
        </div>
        {admin && (
          <div className="flex items-center gap-3">
            <Avatar name={admin.display_name} />
            <div className="min-w-0 flex-1">
              <p className="truncate text-sm font-bold">{admin.display_name}</p>
              <p className="truncate text-xs text-muted-foreground">{roleLabel(t, admin.role)}</p>
            </div>
            <div className="flex items-center gap-1">
              <Button size="sm" variant="ghost" className="h-8 px-2 text-xs" onClick={() => setPasswordOpen(true)}>
                {t("Mot de passe", "كلمة المرور")}
              </Button>
              <button
                onClick={() => void signOut()}
                title={t("Se déconnecter", "تسجيل الخروج")}
                className="grid h-9 w-9 place-items-center rounded-lg text-muted-foreground transition-colors hover:bg-destructive/10 hover:text-destructive"
              >
                <LogOut className="h-4 w-4 rtl:rotate-180" />
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
      <Dialog open={passwordOpen} onOpenChange={setPasswordOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{t("Changer le mot de passe", "تغيير كلمة المرور")}</DialogTitle>
            <DialogDescription>{t("Utilisez au moins 8 caractères. Cette option permet aussi aux employés invités de définir leur mot de passe après activation.", "استعمل 8 أحرف على الأقل. تتيح هذه الخاصية للموظفين المدعوين تعيين كلمة مرورهم بعد تفعيل الحساب.")}</DialogDescription>
          </DialogHeader>
          <form onSubmit={changePassword} className="space-y-4">
            <div className="space-y-1.5">
              <Label>{t("Nouveau mot de passe", "كلمة المرور الجديدة")}</Label>
              <Input type="password" autoComplete="new-password" minLength={8} required value={newPassword} onChange={e=>setNewPassword(e.target.value)} />
            </div>
            <div className="space-y-1.5">
              <Label>{t("Confirmer le mot de passe", "تأكيد كلمة المرور")}</Label>
              <Input type="password" autoComplete="new-password" minLength={8} required value={confirmPassword} onChange={e=>setConfirmPassword(e.target.value)} />
            </div>
            <Button type="submit" disabled={passwordBusy} className="w-full">
              {passwordBusy ? t("Enregistrement…", "جارٍ الحفظ…") : t("Enregistrer", "حفظ")}
            </Button>
          </form>
        </DialogContent>
      </Dialog>
  );
}

export default function Layout() {
  const [open, setOpen] = useState(false);
  const { dir } = useI18n();
  return (
    <div className="min-h-screen kj-grid-bg">
      <aside className="fixed inset-y-0 start-0 z-30 hidden w-64 border-e border-sidebar-border bg-sidebar lg:block">
        <SidebarBody />
      </aside>
      <header className="sticky top-0 z-20 flex items-center justify-between border-b bg-card/90 px-4 py-3 backdrop-blur lg:hidden">
        <img src="/brand/kj-logo.png" alt="KHERJA" className="h-8 w-auto" />
        <button onClick={() => setOpen(true)} className="grid h-10 w-10 place-items-center rounded-xl bg-muted">
          <Menu className="h-5 w-5" />
        </button>
      </header>
      <Sheet open={open} onOpenChange={setOpen}>
        <SheetContent side={dir === "rtl" ? "right" : "left"} className="w-72 p-0">
          <SidebarBody onNavigate={() => setOpen(false)} />
        </SheetContent>
      </Sheet>
      <main className="lg:ps-64">
        <div className="mx-auto max-w-[1400px] px-4 py-6 sm:px-6 lg:px-10 lg:py-9">
          <Outlet />
        </div>
      </main>
    </div>
  );
}
