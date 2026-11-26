import type { ReactNode } from "react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Navigate, Route, Routes } from "react-router-dom";
import { ShieldOff } from "lucide-react";

import { Toaster } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { I18nProvider, useI18n } from "@/lib/i18n";
import { AuthProvider, useAuth, type Permission } from "@/lib/auth";
import Layout, { allowedNav } from "@/components/Layout";
import { EmptyState, Spinner } from "@/components/kj";

import Login from "./pages/Login";
import Overview from "./pages/Overview";
import LiveMap from "./pages/LiveMap";
import Rides from "./pages/Rides";
import Drivers from "./pages/Drivers";
import Passengers from "./pages/Passengers";
import Pricing from "./pages/Pricing";
import Admins from "./pages/Admins";
import Audit from "./pages/Audit";
import Deliveries from "./pages/Deliveries";
import NotFound from "./pages/NotFound";

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

function Shell() {
  const { session, admin, loading } = useAuth();
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
  if (!session || !admin) return <Login />;
  return (
    <Routes>
      <Route element={<Layout />}>
        <Route path="/" element={<HomeRedirect />} />
        <Route path="/live" element={<Guard perm="rides.read"><LiveMap /></Guard>} />
        <Route path="/rides" element={<Guard perm="rides.read"><Rides /></Guard>} />
        <Route path="/deliveries" element={<Guard perm="deliveries.read"><Deliveries /></Guard>} />
        <Route path="/drivers" element={<Guard perm="drivers.read"><Drivers /></Guard>} />
        <Route path="/passengers" element={<Guard perm="users.read"><Passengers /></Guard>} />
        <Route path="/pricing" element={<Guard perm="pricing.read"><Pricing /></Guard>} />
        <Route path="/admins" element={<Guard perm="admins.manage"><Admins /></Guard>} />
        <Route path="/audit" element={<Guard perm="audit.read"><Audit /></Guard>} />
        <Route path="*" element={<NotFound />} />
      </Route>
    </Routes>
  );
}

const App = () => (
  <QueryClientProvider client={queryClient}>
    <I18nProvider>
      <AuthProvider>
        <TooltipProvider>
          <Toaster richColors position="top-center" />
          <BrowserRouter future={{ v7_startTransition: true, v7_relativeSplatPath: true }}>
            <Shell />
          </BrowserRouter>
        </TooltipProvider>
      </AuthProvider>
    </I18nProvider>
  </QueryClientProvider>
);

export default App;
