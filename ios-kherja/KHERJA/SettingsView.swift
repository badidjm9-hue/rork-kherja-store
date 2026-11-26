//
//  SettingsView.swift
//  KHERJA
//
//  Profile, language, role info, sign out.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AppState
    @State private var name = ""
    @State private var city = "Alger"
    @State private var savedFlash = false
    @State private var confirmLogout = false
    @State private var settingsPage: SettingsInfoPage?

    private let cities = ["Alger", "Oran", "Constantine", "Annaba", "Blida", "Batna", "Sétif", "Tlemcen", "Béjaïa", "Ouargla"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.l("settings"))
                        .font(.system(size: 28, weight: .heavy))
                        .foregroundStyle(KJ.ink)
                }
                .padding(.top, 16)

                profileCard

                section(store.l("name")) {
                    TextField(store.l("your_name"), text: $name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(KJ.ink)
                    Picker(store.l("city"), selection: $city) {
                        ForEach(cities, id: \.self) { Text($0).tag($0) }
                    }
                    .tint(KJ.blue)

                    HStack {
                        Button {
                            save()
                        } label: {
                            Text(store.l("save"))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(KJButtonStyle())
                    }
                    .padding(.top, 6)

                    if savedFlash {
                        Label(store.l("saved"), systemImage: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(KJ.success)
                    }
                }

                section(store.l("language")) {
                    HStack(spacing: 12) {
                        languageButton(.fr)
                        languageButton(.ar)
                    }
                }

                section(store.language == .ar ? "المساعدة والمعلومات" : "Aide et informations") {
                    settingsInfoRow(
                        title: store.language == .ar ? "مركز المساعدة" : "Centre d’aide",
                        subtitle: store.language == .ar ? "إجابات عن الرحلات والتوصيل والحساب" : "Trajets, livraison et compte",
                        icon: "questionmark.circle",
                        page: .help
                    )
                    Divider().overlay(KJ.border)
                    settingsInfoRow(
                        title: store.language == .ar ? "الخصوصية والبيانات" : "Confidentialité et données",
                        subtitle: store.language == .ar ? "كيف تُستخدم بياناتك داخل التطبيق" : "Comprendre l’utilisation de vos données",
                        icon: "hand.raised",
                        page: .privacy
                    )
                    Divider().overlay(KJ.border)
                    settingsInfoRow(
                        title: store.language == .ar ? "حول KHERJA" : "À propos de KHERJA",
                        subtitle: store.language == .ar ? "معلومات عن التطبيق" : "Informations sur l’application",
                        icon: "info.circle",
                        page: .about
                    )
                }

                section(store.l("role")) {
                    HStack(spacing: 12) {
                        Image(systemName: store.role == "driver" ? "motorcycle.fill" : "person.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(KJ.blue)
                        Text(store.role == "driver" ? store.l("driver") : store.l("passenger"))
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(KJ.ink)
                        Spacer()
                    }
                }

                Button {
                    confirmLogout = true
                } label: {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text(store.l("logout"))
                    }
                    .foregroundStyle(KJ.danger)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Capsule().fill(KJ.dangerBg))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 30)
            }
            .padding(.horizontal, 20)
        }
        .background(KJ.canvasGradient.ignoresSafeArea())
        .task {
            name = store.profile?.name ?? ""
            city = store.profile?.city ?? "Alger"
        }
        .alert(store.l("logout"), isPresented: $confirmLogout) {
            Button(store.l("logout"), role: .destructive) { store.signOut() }
            Button(store.l("ok"), role: .cancel) {}
        }
        .sheet(item: $settingsPage) { page in
            SettingsInfoView(page: page, language: store.language)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var profileCard: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(KJ.softBlue)
                .frame(width: 66, height: 66)
                .overlay(
                    Text(initials)
                        .font(.system(size: 23, weight: .heavy))
                        .foregroundStyle(KJ.blue)
                )
            VStack(alignment: .leading, spacing: 4) {
                Text(store.profile?.name ?? "—")
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundStyle(KJ.ink)
                HStack(spacing: 10) {
                    Label(String(format: "%.1f", store.profile?.ratingAvg ?? 5), systemImage: "star.fill")
                        .foregroundStyle(KJ.warning)
                    Text("\(store.profile?.tripsCount ?? 0) \(store.l("trips"))")
                        .foregroundStyle(KJ.muted)
                }
                .font(.system(size: 13, weight: .bold))
            }
            Spacer()
        }
        .kjCard()
    }

    private var initials: String {
        (store.profile?.name ?? "K").split(separator: " ").compactMap { $0.first }.prefix(2).map(String.init).joined().uppercased()
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(KJ.ink)
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .kjCard()
        }
    }

    private func languageButton(_ lang: AppLanguage) -> some View {
        Button {
            store.setLanguage(lang)
        } label: {
            HStack(spacing: 10) {
                Text(lang.label)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(store.language == lang ? .white : KJ.ink)
                Text(lang.subLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(store.language == lang ? .white.opacity(0.8) : KJ.muted)
                Spacer()
                if store.language == lang {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(store.language == lang ? AnyShapeStyle(KJ.buttonGradient) : AnyShapeStyle(KJ.softBlue))
            )
        }
        .buttonStyle(.plain)
    }

    private func settingsInfoRow(title: String, subtitle: String, icon: String, page: SettingsInfoPage) -> some View {
        Button {
            settingsPage = page
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(KJ.blue)
                    .frame(width: 38, height: 38)
                    .background(KJ.softBlue, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(KJ.ink)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(KJ.muted)
                }
                Spacer()
                Image(systemName: "chevron.forward")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(KJ.muted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func save() {
        guard let id = store.session.userId else { return }
        let update = ProfileUpdate(name: name.trimmingCharacters(in: .whitespaces), city: city)
        Task {
            try? await SupabaseService.shared.updateProfile(id: id, update: update)
            await store.refreshProfile()
            await MainActor.run {
                savedFlash = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    savedFlash = false
                }
            }
        }
    }
}


private enum SettingsInfoPage: String, Identifiable {
    case help, privacy, about
    var id: String { rawValue }
}

private struct SettingsInfoView: View {
    let page: SettingsInfoPage
    let language: AppLanguage

    private var isArabic: Bool { language == .ar }
    private var title: String {
        switch page {
        case .help: isArabic ? "مركز المساعدة" : "Centre d’aide"
        case .privacy: isArabic ? "الخصوصية والبيانات" : "Confidentialité et données"
        case .about: isArabic ? "حول KHERJA" : "À propos de KHERJA"
        }
    }

    private var items: [(String, String)] {
        switch page {
        case .help:
            return isArabic ? [
                ("كيف أطلب رحلة؟", "حدد نقطة الانطلاق والوجهة، اختر نوع المركبة، ثم راجع السعر وأرسل طلبك."),
                ("كيف أتابع طلبي؟", "ستجد حالة الرحلة أو التوصيل في القسم المخصص داخل التطبيق."),
                ("هل يمكنني إلغاء الطلب؟", "تختلف إمكانية الإلغاء حسب حالة الطلب. استخدم زر الإلغاء الظاهر في تفاصيل الطلب عندما يكون متاحاً.")
            ] : [
                ("Comment demander une course ?", "Choisissez le départ et la destination, sélectionnez un véhicule, vérifiez le tarif puis envoyez la demande."),
                ("Comment suivre ma demande ?", "Consultez son état dans la section dédiée aux courses ou aux livraisons."),
                ("Puis-je annuler ?", "L’annulation dépend de l’état de la demande. Utilisez l’action affichée lorsqu’elle est disponible.")
            ]
        case .privacy:
            return isArabic ? [
                ("الموقع", "يُستخدم الموقع لتحديد الانطلاق وعرض معلومات الرحلة عند منح التطبيق الإذن."),
                ("معلومات الحساب", "تُستخدم بيانات الحساب لتشغيل الخدمات وربط الطلبات بصاحبها."),
                ("التحكم", "يمكنك إدارة إذن الموقع من إعدادات iPhone. هذه الصفحة توضيحية وليست بديلاً عن سياسة الخصوصية القانونية المعتمدة.")
            ] : [
                ("Localisation", "La localisation sert à définir le départ et afficher les informations du trajet lorsque vous accordez l’autorisation."),
                ("Compte", "Les informations du compte servent au fonctionnement du service et au rattachement des demandes."),
                ("Contrôle", "Vous pouvez gérer l’autorisation de localisation dans les réglages de l’iPhone. Cette page informative ne remplace pas la politique de confidentialité officielle.")
            ]
        case .about:
            return isArabic ? [
                ("KHERJA", "تطبيق للتنقل وطلب توصيل الطرود."),
                ("الخدمات", "تجربة منفصلة للراكب والسائق، مع خدمات الرحلات والتوصيل."),
                ("الإصدار", "رقم الإصدار وتفاصيل الدعم الرسمية ستُعرض هنا بعد اعتماد إعدادات الإصدار.")
            ] : [
                ("KHERJA", "Une application de mobilité et de livraison de colis."),
                ("Services", "Des espaces distincts pour les passagers et les chauffeurs, avec courses et livraisons."),
                ("Version", "Le numéro de version et les coordonnées officielles seront ajoutés après validation de la configuration de publication.")
            ]
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.0)
                                .font(.system(size: 16, weight: .heavy))
                                .foregroundStyle(KJ.ink)
                            Text(item.1)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(KJ.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .kjCard()
                    }
                }
                .padding(20)
            }
            .background(KJ.canvasGradient.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isArabic ? "تم" : "Terminé") { }
                        .foregroundStyle(KJ.blue)
                }
            }
        }
        .environment(\.layoutDirection, isArabic ? .rightToLeft : .leftToRight)
    }
}
