import { useEffect } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { supabase } from "./supabase";

type Table = "rides" | "ride_requests" | "offers" | "profiles";

/** Invalidates the given query keys whenever one of the tables changes. */
export function useRealtimeInvalidate(channel: string, tables: Table[], keys: string[][]) {
  const qc = useQueryClient();
  const tablesKey = tables.join(",");
  const keysKey = JSON.stringify(keys);
  useEffect(() => {
    const parsed = JSON.parse(keysKey) as string[][];
    let timer: ReturnType<typeof setTimeout> | null = null;
    const bump = () => {
      if (timer) return;
      timer = setTimeout(() => {
        timer = null;
        parsed.forEach((k) => void qc.invalidateQueries({ queryKey: k }));
      }, 600);
    };
    const ch = supabase.channel(`${channel}-${Math.random().toString(36).slice(2)}`);
    tablesKey.split(",").forEach((table) => {
      ch.on("postgres_changes", { event: "*", schema: "public", table }, bump);
    });
    ch.subscribe();
    return () => {
      if (timer) clearTimeout(timer);
      void supabase.removeChannel(ch);
    };
  }, [channel, tablesKey, keysKey, qc]);
}
