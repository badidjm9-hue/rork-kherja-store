//
//  SettingsView.swift
//  Kherja
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
