import { useQuery } from "@tanstack/react-query";
import { supabase, must, type Profile } from "./supabase";

/** Loads the profiles for a set of user ids, keyed by id. */
export function useProfiles(ids: (string | null | undefined)[]) {
  const unique = Array.from(new Set(ids.filter((x): x is string => Boolean(x)))).sort();
  return useQuery({
    queryKey: ["profiles-by-id", unique.join(",")],
    enabled: unique.length > 0,
    queryFn: async () => {
      const map = new Map<string, Profile>();
      for (let i = 0; i < unique.length; i += 150) {
        const chunk = unique.slice(i, i + 150);
        const rows = must(await supabase.from("profiles").select("*").in("id", chunk));
        rows.forEach((p) => map.set(p.id, p));
      }
      return map;
    },
    staleTime: 60_000,
  });
}
