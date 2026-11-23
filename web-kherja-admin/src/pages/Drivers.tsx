import { useI18n } from "@/lib/i18n";
import { PageHeader } from "@/components/kj";
import PeopleTable from "@/components/PeopleTable";

export default function Drivers() {
  const { t } = useI18n();
  return (
    <div>
      <PageHeader
        title={t("Chauffeurs", "السائقون")}
        subtitle={t(
          "Un chauffeur ne reçoit aucune demande tant qu'il n'est pas validé.",
          "لا يتلقى السائق أي طلب حتى يتم قبوله.",
        )}
      />
      <PeopleTable role="driver" />
    </div>
  );
}
