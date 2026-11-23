import { Link } from "react-router-dom";
import { Compass } from "lucide-react";
import { useI18n } from "@/lib/i18n";
import { EmptyState } from "@/components/kj";

const NotFound = () => {
  const { t } = useI18n();
  return (
    <div className="flex flex-col items-center">
      <EmptyState icon={Compass} title={t("Page introuvable", "الصفحة غير موجودة")} />
      <Link to="/" className="text-sm font-semibold text-primary hover:underline">
        {t("Retour à l'accueil", "العودة إلى الرئيسية")}
      </Link>
    </div>
  );
};

export default NotFound;
