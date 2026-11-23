import { useI18n } from "@/lib/i18n";
import { PageHeader } from "@/components/kj";
import PeopleTable from "@/components/PeopleTable";

export default function Passengers() {
  const { t } = useI18n();
  return (
    <div>
      <PageHeader
        title={t("Passagers", "الركاب")}
        subtitle={t("Un compte suspendu ne peut plus créer de demande.", "الحساب المعلق لا يمكنه إنشاء طلبات.")}
      />
      <PeopleTable role="passenger" />
    </div>
  );
}
