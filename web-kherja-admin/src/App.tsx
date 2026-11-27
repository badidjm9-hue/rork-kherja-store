import { lazy, Suspense, type ReactNode } from "react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Navigate, Route, Routes } from "react-router-dom";
import { ShieldOff } from "lucide-react";

import { Toaster } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { I18nProvider, useI18n } from "@/lib/i18n";
import { AuthProvider, useAuth, type Permission } from "@/lib/auth";
import Layout, { allowedNav } from "@/components/Layout";
import { EmptyState, Spinner } from "@/components/kj";

const Login = lazy(() => import("./pages/Login"));
const Overview = lazy(() => import("./pages/Overview"));
const LiveMap = lazy(() => import("./pages/LiveMap"));
const Rides = lazy(() => import("./pages/Rides"));
const Drivers = lazy(() => import("./pages/Drivers"));
const Passengers = lazy(() => import("./pages/Passengers"));
const Pricing = lazy(() => import("./pages/Pricing"));
const Admins = lazy(() => import("./pages/Admins"));
const Audit = lazy(() => import("./pages/Audit"));
const Deliveries = lazy(() => import("./pages/Deliveries"));
const Vehicles = lazy(() => import("./pages/Vehicles"));
const Reports = lazy(() => import("./pages/Reports"));
const Notifications = lazy(() => import("./pages/Notifications"));
const SettingsPage = lazy(() => import("./pages/Settings"));
const Support = lazy(() => import("./pages/Support"));
const NotFound = lazy(() => import("./pages/NotFound"));

const queryClient = new QueryClient({
  defaultOptions: { queries: { retry: 1, refetchOnWindowFocus: false } },
});

function Guard({ perm, children }: { perm: Permission; children: ReactNode }) {
  const { can } = useAuth();
  const { t } = useI18n();
  if (!can(perm)) {
    return (
      <EmptyState
        icon={ShieldOff}
        title={t("Accès non autorisé", "غير مصرح بالدخول")}
        body={t("Votre rôle ne permet pas d'ouvrir cette section.", "دورك لا يسمح بفتح هذا القسم.")}
      />
    );
  }
  return <>{children}</>;
}

function HomeRedirect() {
  const { can } = useAuth();
  if (can("overview.read")) return <Overview />;
  const first = allowedNav(can)[0];
  return first ? <Navigate to={first.to} replace /> : <NotFound />;
}

function RouteLoading() {
  const { t } = useI18n();
  return (
    <div className="grid min-h-[50vh] place-items-center" role="status" aria-label={t("Chargement", "جارٍ التحميل")}>
      <Spinner className="h-6 w-6" />
    </div>
  );
}

function Shell() {
  const { session, admin, loading, denied, signOut } = useAuth();
  const { t } = useI18n();
  if (loading) {
    return (
      <div className="grid min-h-screen place-items-center bg-background">
        <div className="flex flex-col items-center gap-4">
          <img src="/brand/kj-logo.png" alt="KHERJA" className="h-14 w-auto" />
          <Spinner />
        </div>
      </div>
    );
  }
  if (session && denied) {
    return (
      <div className="grid min-h-screen place-items-center bg-background p-6">
        <div className="kj-card w-full max-w-md space-y-4 p-7 text-center">
          <ShieldOff className="mx-auto h-10 w-10 text-destructive" />
          <h1 className="text-xl font-bold">{t("Accès non autorisé", "غير مصرح بالدخول")}</h1>
          <p className="text-sm text-muted-foreground">{t("Ce compte ne dispose pas d'un accès actif à l'administration.", "هذا الحساب لا يملك صلاحية دخول لوحة الإدارة.")}</p>
          <button onClick={() => void signOut()} className="h-11 w-full rounded-xl bg-primary px-4 font-semibold text-primary-foreground">{t("Se déconnecter", "تسجيل الخروج")}</button>
        </div>
      </div>
    );
  }
  if (!session || !admin) {
    return (
      <Suspense fallback={<RouteLoading />}>
        <Login />
      </Suspense>
    );
  }
  return (
    <Suspense fallback={<RouteLoading />}>
      <Routes>
        <Route element={<Layout />}>
          <Route path="/" element={<HomeRedirect />} />
          <Route path="/live" element={<Guard perm="rides.read"><LiveMap /></Guard>} />
          <Route path="/rides" element={<Guard perm="rides.read"><Rides /></Guard>} />
          <Route path="/deliveries" element={<Guard perm="deliveries.read"><Deliveries /></Guard>} />
          <Route path="/vehicles" element={<Guard perm="vehicles.read"><Vehicles /></Guard>} />
          <Route path="/reports" element={<Guard perm="reports.read"><Reports /></Guard>} />
          <Route path="/notifications" element={<Guard perm="notifications.read"><Notifications /></Guard>} />
          <Route path="/settings" element={<Guard perm="settings.read"><SettingsPage /></Guard>} />
          <Route path="/drivers" element={<Guard perm="drivers.read"><Drivers /></Guard>} />
          <Route path="/passengers" element={<Guard perm="users.read"><Passengers /></Guard>} />
          <Route path="/pricing" element={<Guard perm="pricing.read"><Pricing /></Guard>} />
          <Route path="/admins" element={<Guard perm="admins.manage"><Admins /></Guard>} />
          <Route path="/support" element={<Guard perm="support.read"><Support /></Guard>} />
          <Route path="/audit" element={<Guard perm="audit.read"><Audit /></Guard>} />
          <Route path="*" element={<NotFound />} />
        </Route>
      </Routes>
    </Suspense>
  );
}

const App = () => (
  <QueryClientProvider client={queryClient}>
    <I18nProvider>
      <AuthProvider>
        <TooltipProvider>
          <Toaster richColors position="top-center" />
          <BrowserRouter>
            <Shell />
          </BrowserRouter>
        </TooltipProvider>
      </AuthProvider>
    </I18nProvider>
  </QueryClientProvider>
);

export default App;
