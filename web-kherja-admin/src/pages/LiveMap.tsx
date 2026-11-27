import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { MapContainer, Marker, Polyline, Popup, TileLayer } from "react-leaflet";
import L from "leaflet";
import { CarFront, Clock, Radio } from "lucide-react";
import { supabase, must, type Profile, type Ride, type RideRequest } from "@/lib/supabase";
import { useI18n } from "@/lib/i18n";
import { rideStatus, vehicleLabel } from "@/lib/labels";
import { useRealtimeInvalidate } from "@/lib/useRealtime";
import { cn } from "@/lib/utils";
import { EmptyState, ErrorBlock, LoadingBlock, PageHeader, Pill } from "@/components/kj";
import { Sheet, SheetContent } from "@/components/ui/sheet";
import { RideDetail } from "./Rides";

const pin = (color: string, glyph: string, pulse = false) =>
  L.divIcon({
    className: "",
    iconSize: [34, 34],
    iconAnchor: [17, 17],
    html: `<div style="position:relative;width:34px;height:34px">
      ${pulse ? `<span style="position:absolute;inset:-6px;border-radius:999px;background:${color};opacity:.18;animation:ping 1.8s cubic-bezier(0,0,.2,1) infinite"></span>` : ""}
      <div style="position:relative;width:34px;height:34px;border-radius:999px;background:${color};border:3px solid #fff;box-shadow:0 6px 14px -4px ${color};display:grid;place-items:center;color:#fff;font:700 13px Figtree,sans-serif">${glyph}</div>
    </div>`,
  });

const ICONS = {
  driverFree: pin("#16A34A", "●", true),
  driverBusy: pin("#075BFF", "●"),
  pickup: pin("#075BFF", "A"),
  dest: pin("#85003F", "B"),
  request: pin("#D97706", "?", true),
};

export default function LiveMap() {
  const { t, money, relative, dir } = useI18n();
  const [selected, setSelected] = useState<string | null>(null);
  const [layer, setLayer] = useState({ drivers: true, rides: true, requests: true });

  useRealtimeInvalidate("live-map", ["rides", "ride_requests", "profiles"], [["live"]]);

  const q = useQuery({
    queryKey: ["live"],
    queryFn: async () => {
      const [drivers, rides, requests] = await Promise.all([
        supabase.from("profiles").select("*").eq("role", "driver").eq("is_online", true).not("current_lat", "is", null).not("current_lng", "is", null),
        supabase.from("rides").select("*").in("status", ["en_route", "arrived", "started"]).order("created_at", { ascending: false }),
        supabase
          .from("ride_requests")
          .select("*")
          .in("status", ["open", "negotiating"])
          .gt("expires_at", new Date().toISOString()),
      ]);
      return {
        drivers: must(drivers) as Profile[],
        rides: must(rides) as Ride[],
        requests: must(requests) as RideRequest[],
      };
    },
    refetchInterval: 15_000,
  });

  const busyDrivers = useMemo(() => new Set((q.data?.rides ?? []).map((r) => r.driver_id)), [q.data]);
  const names = useMemo(() => new Map((q.data?.drivers ?? []).map((d) => [d.id, d])), [q.data]);

  const toggles: { id: keyof typeof layer; label: string; n: number; color: string }[] = [
    { id: "drivers", label: t("Chauffeurs en ligne", "سائقون متصلون"), n: q.data?.drivers.length ?? 0, color: "bg-success" },
    { id: "rides", label: t("Courses actives", "رحلات جارية"), n: q.data?.rides.length ?? 0, color: "bg-primary" },
    { id: "requests", label: t("Demandes ouvertes", "طلبات مفتوحة"), n: q.data?.requests.length ?? 0, color: "bg-warning" },
  ];

  return (
    <div>
      <style>{`@keyframes ping{75%,100%{transform:scale(1.9);opacity:0}}`}</style>
      <PageHeader
        title={t("Carte en direct", "الخريطة المباشرة")}
        subtitle={t("Positions réelles envoyées par l'app chauffeur.", "المواقع الفعلية المرسلة من تطبيق السائق.")}
        actions={
          <div className="flex flex-wrap gap-1.5">
            {toggles.map((x) => (
              <button
                key={x.id}
                onClick={() => setLayer((l) => ({ ...l, [x.id]: !l[x.id] }))}
                className={cn(
                  "flex items-center gap-2 rounded-full border bg-card px-3 py-1.5 text-sm font-semibold transition-opacity",
                  !layer[x.id] && "opacity-45",
                )}
              >
                <span className={cn("h-2.5 w-2.5 rounded-full", x.color)} />
                {x.label}
                <span className="kj-num rounded-full bg-muted px-1.5 text-xs">{x.n}</span>
              </button>
            ))}
          </div>
        }
      />
      {q.error && <ErrorBlock error={q.error} />}
      <div className="grid gap-4 xl:grid-cols-[1fr_340px]">
        <div className="kj-card relative h-[calc(100vh-220px)] min-h-[460px] overflow-hidden p-0" dir="ltr">
          {q.isLoading && (
            <div className="absolute inset-0 z-[1000] flex items-center justify-center bg-background/65 backdrop-blur-[2px]">
              <LoadingBlock />
            </div>
          )}
          <MapContainer center={[36.7538, 3.0588]} zoom={11} className="h-full w-full" scrollWheelZoom>
            <TileLayer
              attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> &copy; <a href="https://carto.com/">CARTO</a>'
              url="https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png"
            />
            {layer.drivers &&
              q.data?.drivers.map((d) => (
                <Marker key={d.id} position={[d.current_lat!, d.current_lng!]} icon={busyDrivers.has(d.id) ? ICONS.driverBusy : ICONS.driverFree}>
                  <Popup>
                    <div dir={dir} className="space-y-0.5">
                      <p className="font-bold">{d.name}</p>
                      <p className="text-xs">{[d.vehicle_make, d.vehicle_model, d.vehicle_plate].filter(Boolean).join(" · ")}</p>
                      <p className="text-xs opacity-70">{busyDrivers.has(d.id) ? t("En course", "في رحلة") : t("Disponible", "متاح")} · {relative(d.location_updated_at)}</p>
                    </div>
                  </Popup>
                </Marker>
              ))}
            {layer.rides &&
              q.data?.rides.map((r) => (
                <div key={r.id}>
                  <Polyline positions={[[r.pickup_lat, r.pickup_lng], [r.dest_lat, r.dest_lng]]} pathOptions={{ color: "#075BFF", weight: 3, dashArray: "6 8", opacity: 0.7 }} />
                  <Marker position={[r.pickup_lat, r.pickup_lng]} icon={ICONS.pickup} eventHandlers={{ click: () => setSelected(r.id) }} />
                  <Marker position={[r.dest_lat, r.dest_lng]} icon={ICONS.dest} eventHandlers={{ click: () => setSelected(r.id) }} />
                </div>
              ))}
            {layer.requests &&
              q.data?.requests.map((r) => (
                <Marker key={r.id} position={[r.pickup_lat, r.pickup_lng]} icon={ICONS.request}>
                  <Popup>
                    <div dir={dir} className="space-y-0.5">
                      <p className="font-bold">{r.pickup_label}</p>
                      <p className="text-xs">→ {r.dest_label}</p>
                      <p className="text-xs">{vehicleLabel(t, r.vehicle)} · {money(r.proposed_fare)}</p>
                    </div>
                  </Popup>
                </Marker>
              ))}
          </MapContainer>
        </div>

        <div className="kj-card flex max-h-[calc(100vh-220px)] min-h-[300px] flex-col overflow-hidden">
          <div className="border-b px-4 py-3">
            <p className="flex items-center gap-2 font-bold"><Radio className="h-4 w-4 text-primary" />{t("Courses actives", "رحلات جارية")}</p>
          </div>
          <div className="flex-1 space-y-2 overflow-y-auto p-3">
            {q.isLoading && <LoadingBlock />}
            {q.data && q.data.rides.length === 0 && q.data.requests.length === 0 && (
              <EmptyState icon={Radio} title={t("Aucune course ni demande active", "لا توجد رحلات أو طلبات نشطة")} body={t("Les courses et demandes actives apparaîtront ici. Les chauffeurs connectés restent visibles sur la carte.", "ستظهر هنا الرحلات والطلبات النشطة، بينما يبقى السائقون المتصلون ظاهرين على الخريطة.")} />
            )}
            {q.data?.rides.map((r) => {
              const st = rideStatus(t, r.status);
              return (
                <button key={r.id} onClick={() => setSelected(r.id)} className="w-full rounded-xl border bg-card p-3 text-start text-sm transition-colors hover:border-primary/40 hover:bg-accent/40">
                  <div className="flex items-center justify-between">
                    <Pill tone={st.tone}>{st.label}</Pill>
                    <span className="kj-num font-semibold">{money(r.fare)}</span>
                  </div>
                  <p className="mt-2 truncate">{r.pickup_label}</p>
                  <p className="truncate text-muted-foreground">→ {r.dest_label}</p>
                  <p className="mt-1 flex items-center gap-1 text-xs text-muted-foreground">
                    <CarFront className="h-3 w-3" />
                    {names.get(r.driver_id)?.name ?? t("Chauffeur hors carte", "سائق خارج الخريطة")}
                  </p>
                </button>
              );
            })}
            {q.data && q.data.requests.length > 0 && (
              <>
                <p className="flex items-center gap-2 px-1 pt-3 text-xs font-bold uppercase tracking-wider text-muted-foreground">
                  <Clock className="h-3.5 w-3.5" />
                  {t("Demandes en attente", "طلبات في الانتظار")}
                </p>
                {q.data.requests.map((r) => (
                  <div key={r.id} className="rounded-xl border border-warning/30 bg-warning-soft/50 p-3 text-sm">
                    <div className="flex items-center justify-between">
                      <span className="font-semibold">{vehicleLabel(t, r.vehicle)}</span>
                      <span className="kj-num font-semibold">{money(r.proposed_fare)}</span>
                    </div>
                    <p className="mt-1 truncate">{r.pickup_label} → {r.dest_label}</p>
                    <p className="text-xs text-muted-foreground">{t("Expire", "تنتهي")} {relative(r.expires_at)}</p>
                  </div>
                ))}
              </>
            )}
          </div>
        </div>
      </div>

      <Sheet open={!!selected} onOpenChange={(o) => !o && setSelected(null)}>
        <SheetContent side={dir === "rtl" ? "left" : "right"} className="w-full overflow-y-auto sm:max-w-xl">
          {selected && <RideDetail id={selected} />}
        </SheetContent>
      </Sheet>
    </div>
  );
}
