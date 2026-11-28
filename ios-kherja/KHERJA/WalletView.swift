//
//  WalletView.swift
//  KHERJA
//
//  Cash wallet: balance from transaction history (payments for passengers,
//  earnings for drivers).
//

import SwiftUI

struct WalletView: View {
    @EnvironmentObject var store: AppState
    @State private var transactions: [Transaction] = []
    @State private var loading = true

    private var isDriver: Bool { store.role == "driver" }

    private var balance: Int {
        transactions.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.l("my_wallet"))
                        .font(.system(size: 28, weight: .heavy))
                        .foregroundStyle(KJ.ink)
                    Text(store.l("wallet_subtitle"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(KJ.muted)
                }
                .padding(.top, 16)

                balanceCard

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(store.l("transactions"))
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(KJ.ink)
                        Spacer()
                    }

                    if loading {
                        SkeletonList(count: 3)
                    } else if transactions.isEmpty {
                        Text(store.l("no_transactions"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(KJ.muted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 26)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(Array(transactions.enumerated()), id: \.element.id) { index, t in
                                TransactionRow(transaction: t, lang: store.language)
                                    .kjReveal(index: index)
                            }
                        }
                    }
                }

                HStack(spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(KJ.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.l("cash_note"))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(KJ.ink)
                    }
                    Spacer()
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(KJ.softBlue))
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 20)
        }
        .background(KJ.canvasGradient.ignoresSafeArea())
        .task { await load() }
        .refreshable { await load() }
    }

    private var balanceCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "wallet.bifold.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.l("current_balance"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Text("\(isDriver ? "+" : "")\(KJFormat.dzd(abs(balance)))")
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(.white)
            }
            Spacer()
            Label(isDriver ? store.l("credit") : store.l("debit"), systemImage: "banknote.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(.white.opacity(0.18)))
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(KJ.buttonGradient)
                .shadow(color: KJ.blue.opacity(0.35), radius: 16, y: 8)
        )
    }

    private func load() async {
        guard let userId = store.session.userId else { return }
        do {
            transactions = try await SupabaseService.shared.myTransactions(userId: userId)
        } catch {
            print("KHERJA wallet error: \(error)")
        }
        loading = false
    }
}

struct TransactionRow: View {
    let transaction: Transaction
    let lang: AppLanguage

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(transaction.amount >= 0 ? KJ.successBg : KJ.dangerBg)
                .frame(width: 46, height: 46)
                .overlay(
                    Image(systemName: transaction.amount >= 0 ? "arrow.down.left" : "arrow.up.right")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(transaction.amount >= 0 ? KJ.success : KJ.danger)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.label ?? (transaction.amount >= 0 ? "Crédit" : "Débit"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(KJ.ink)
                    .lineLimit(1)
                Text(dateText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(KJ.muted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(transaction.amount >= 0
                    ? "+ \(KJFormat.dzd(transaction.amount))"
                    : "- \(KJFormat.dzd(abs(transaction.amount)))")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(transaction.amount >= 0 ? KJ.success : KJ.danger)
                Text(transaction.amount >= 0 ? "Crédit" : "Débit")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(transaction.amount >= 0 ? KJ.success : KJ.danger)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(transaction.amount >= 0 ? KJ.successBg : KJ.dangerBg))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white)
                .shadow(color: Color(hex: 0x075BFF).opacity(0.06), radius: 8, y: 4)
        )
    }

    private var dateText: String {
        let f = DateFormatter()
        f.locale = lang == .ar ? Locale(identifier: "ar_DZ") : Locale(identifier: "fr_FR")
        f.dateFormat = "d MMM. yyyy • HH:mm"
        return f.string(from: transaction.createdAt)
    }
}
