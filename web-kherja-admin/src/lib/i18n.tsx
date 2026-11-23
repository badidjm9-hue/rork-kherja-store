import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from "react";

export type Lang = "fr" | "ar";

interface I18nValue {
  lang: Lang;
  dir: "ltr" | "rtl";
  setLang: (l: Lang) => void;
  /** Pick the French or Arabic string for the current language. */
  t: (fr: string, ar: string) => string;
  money: (n: number | null | undefined) => string;
  num: (n: number | null | undefined, digits?: number) => string;
  date: (iso: string | null | undefined, withTime?: boolean) => string;
  relative: (iso: string | null | undefined) => string;
}

const I18nContext = createContext<I18nValue | null>(null);

export function I18nProvider({ children }: { children: ReactNode }) {
  const [lang, setLangState] = useState<Lang>(() => (localStorage.getItem("kj-admin-lang") === "ar" ? "ar" : "fr"));
  const dir = lang === "ar" ? "rtl" : "ltr";

  useEffect(() => {
    document.documentElement.lang = lang;
    document.documentElement.dir = dir;
  }, [lang, dir]);

  const setLang = useCallback((l: Lang) => {
    localStorage.setItem("kj-admin-lang", l);
    setLangState(l);
  }, []);

  const value = useMemo<I18nValue>(() => {
    const locale = lang === "ar" ? "ar-DZ-u-nu-latn" : "fr-DZ";
    const nf = new Intl.NumberFormat(locale, { maximumFractionDigits: 0 });
    return {
      lang,
      dir,
      setLang,
      t: (fr, ar) => (lang === "ar" ? ar : fr),
      money: (n) => `${nf.format(Math.round(n ?? 0))} ${lang === "ar" ? "دج" : "DA"}`,
      num: (n, digits = 0) =>
        new Intl.NumberFormat(locale, { maximumFractionDigits: digits, minimumFractionDigits: 0 }).format(n ?? 0),
      date: (iso, withTime = true) => {
        if (!iso) return "—";
        const d = new Date(iso);
        return new Intl.DateTimeFormat(locale, {
          day: "2-digit",
          month: "short",
          year: "numeric",
          ...(withTime ? { hour: "2-digit", minute: "2-digit" } : {}),
          timeZone: "Africa/Algiers",
        }).format(d);
      },
      relative: (iso) => {
        if (!iso) return "—";
        const diff = (new Date(iso).getTime() - Date.now()) / 1000;
        const rtf = new Intl.RelativeTimeFormat(locale, { numeric: "auto" });
        const abs = Math.abs(diff);
        if (abs < 60) return rtf.format(Math.round(diff), "second");
        if (abs < 3600) return rtf.format(Math.round(diff / 60), "minute");
        if (abs < 86400) return rtf.format(Math.round(diff / 3600), "hour");
        return rtf.format(Math.round(diff / 86400), "day");
      },
    };
  }, [lang, dir, setLang]);

  return <I18nContext.Provider value={value}>{children}</I18nContext.Provider>;
}

export function useI18n() {
  const ctx = useContext(I18nContext);
  if (!ctx) throw new Error("useI18n must be used inside I18nProvider");
  return ctx;
}
