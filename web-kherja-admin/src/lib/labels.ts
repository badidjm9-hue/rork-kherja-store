type T = (fr: string, ar: string) => string;
export type Tone = "blue" | "bordeaux" | "green" | "amber" | "red" | "gray";

export function rideStatus(t: T, s: string): { label: string; tone: Tone } {
  switch (s) {
    case "en_route":
      return { label: t("En route", "في الطريق"), tone: "blue" };
    case "arrived":
      return { label: t("Arrivé", "وصل"), tone: "amber" };
    case "started":
      return { label: t("En course", "جارية"), tone: "bordeaux" };
    case "completed":
      return { label: t("Terminée", "مكتملة"), tone: "green" };
    case "cancelled":
      return { label: t("Annulée", "ملغاة"), tone: "red" };
    case "open":
      return { label: t("Ouverte", "مفتوحة"), tone: "blue" };
    case "negotiating":
      return { label: t("Négociation", "تفاوض"), tone: "amber" };
    case "accepted":
      return { label: t("Acceptée", "مقبولة"), tone: "green" };
    case "expired":
      return { label: t("Expirée", "منتهية"), tone: "gray" };
    case "pending":
      return { label: t("En attente", "قيد الانتظار"), tone: "amber" };
    case "rejected":
      return { label: t("Refusée", "مرفوضة"), tone: "red" };
    default:
      return { label: s, tone: "gray" };
  }
}

export function driverStatus(t: T, s: string): { label: string; tone: Tone } {
  switch (s) {
    case "approved":
      return { label: t("Validé", "مقبول"), tone: "green" };
    case "pending":
      return { label: t("À valider", "بانتظار التحقق"), tone: "amber" };
    case "rejected":
      return { label: t("Refusé", "مرفوض"), tone: "red" };
    default:
      return { label: t("—", "—"), tone: "gray" };
  }
}

export function vehicleLabel(t: T, v: string) {
  return v === "moto" ? t("Moto", "دراجة نارية") : t("Voiture", "سيارة");
}

export const ROLE_CODES = [
  "super_admin",
  "operations_manager",
  "support_agent",
  "financial_manager",
  "pricing_manager",
] as const;

export function roleLabel(t: T, r: string) {
  switch (r) {
    case "super_admin":
      return t("Super admin", "مدير عام");
    case "operations_manager":
      return t("Responsable opérations", "مسؤول العمليات");
    case "support_agent":
      return t("Agent support", "وكيل الدعم");
    case "financial_manager":
      return t("Responsable financier", "المسؤول المالي");
    case "pricing_manager":
      return t("Responsable tarification", "مسؤول التسعير");
    default:
      return r;
  }
}

export function auditAction(t: T, a: string) {
  const map: Record<string, [string, string]> = {
    "driver.approved": ["Chauffeur validé", "قبول سائق"],
    "driver.rejected": ["Chauffeur refusé", "رفض سائق"],
    "driver.pending": ["Chauffeur remis en attente", "إعادة السائق للانتظار"],
    "account.active": ["Compte réactivé", "إعادة تفعيل حساب"],
    "account.suspended": ["Compte suspendu", "تعليق حساب"],
    "pricing.draft": ["Brouillon de tarifs enregistré", "حفظ مسودة تسعير"],
    "pricing.publish": ["Tarifs publiés", "نشر التسعير"],
    "pricing.restore": ["Version restaurée", "استعادة نسخة"],
    "pricing.unschedule": ["Programmation annulée", "إلغاء الجدولة"],
    "ride.cancel": ["Course annulée", "إلغاء رحلة"],
    "ride.adjust": ["Ajustement de course", "تعديل رحلة"],
    "admin.set": ["Accès admin modifié", "تعديل صلاحيات مسؤول"],
    "admin.permissions": ["Permissions d'employé modifiées", "تعديل صلاحيات موظف"],
    "delivery.cancel": ["Livraison annulée par l'administration", "إلغاء طلب توصيل من الإدارة"],
  };
  const v = map[a];
  return v ? t(v[0], v[1]) : a;
}

export function deliveryStatus(t: T, s: string): { label: string; tone: Tone } {
  switch (s) {
    case "open":
      return { label: t("En attente", "في الانتظار"), tone: "blue" };
    case "accepted":
      return { label: t("Acceptée", "مقبول"), tone: "amber" };
    case "picked_up":
      return { label: t("Colis récupéré", "تم استلام الطرد"), tone: "bordeaux" };
    case "delivered":
      return { label: t("Livrée", "تم التسليم"), tone: "green" };
    case "cancelled":
      return { label: t("Annulée", "ملغى"), tone: "red" };
    case "expired":
      return { label: t("Expirée", "منتهي"), tone: "gray" };
    default:
      return { label: s, tone: "gray" };
  }
}

export const DOC_TYPES = ["id_card", "license", "registration", "insurance", "vehicle_photo"] as const;

export function docTypeLabel(t: T, d: string) {
  switch (d) {
    case "id_card":
      return t("Carte d'identité", "بطاقة الهوية");
    case "license":
      return t("Permis de conduire", "رخصة السياقة");
    case "registration":
      return t("Carte grise", "البطاقة الرمادية");
    case "insurance":
      return t("Assurance", "التأمين");
    case "vehicle_photo":
      return t("Photo du véhicule", "صورة المركبة");
    default:
      return d;
  }
}
