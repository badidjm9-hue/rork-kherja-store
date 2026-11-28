//
//  ExtrasViews.swift
//  KHERJA
//
//  Saved places, notifications + preferences, driver vehicles, ride receipt, support + SOS.
//  Mirrors the Android screens (Extras.kt). Wired to migrations 0010/0011. Not compiled in this environment.
//

import MapKit
import SwiftUI

enum ExtrasPage: String, Identifiable {
    case places, notifications, vehicles, support
    var id: String { rawValue }
}

// MARK: Shared pieces

private struct ExtrasHeader: View {
    @EnvironmentObject var store: AppState
    let title: String
    var subtitle: String?
    let onBack: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            BackCircleButton(action: onBack)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 24, weight: .heavy)).foregroundStyle(KJ.ink)
                if let subtitle {
                    Text(subtitle).font(.system(size: 13, weight: .medium)).foregroundStyle(KJ.muted)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }
}

private struct ExtrasEmpty: View {
    let icon: String, title: String, hint: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 34, weight: .semibold)).foregroundStyle(KJ.blue)
                .frame(width: 72, height: 72).background(Circle().fill(KJ.softBlue))
            Text(title).font(.system(size: 17, weight: .heavy)).foregroundStyle(KJ.ink)
            Text(hint).font(.system(size: 13, weight: .medium)).foregroundStyle(KJ.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40).padding(.horizontal, 24)
    }
}

private struct ErrorLine: View {
    let text: String?
    var body: some View {
        if let text {
            Label(text, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .bold)).foregroundStyle(KJ.danger)
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(KJ.dangerBg))
        }
    }
}

private func extrasDate(_ date: Date?, _ lang: AppLanguage) -> String {
    guard let date else { return "" }
    let f = DateFormatter()
    f.locale = Locale(identifier: lang == .ar ? "ar_DZ" : "fr_FR")
    f.dateStyle = .medium
    f.timeStyle = .short
    return f.string(from: date)
}

// MARK: My space card (inside Settings)

struct MySpaceCard: View {
    @EnvironmentObject var store: AppState
    let onOpen: (ExtrasPage) -> Void
    @State private var unread = 0

    var body: some View {
        VStack(spacing: 0) {
            row("mappin.and.ellipse", store.l("places_title"), store.l("places_subtitle"), nil, .places)
            Divider().overlay(Color(hex: 0xE8EAF1))
            row("bell", store.l("notif_title"), store.l("notif_subtitle"), unread > 0 ? "\(unread)" : nil, .notifications)
            if store.role == "driver" {
                Divider().overlay(Color(hex: 0xE8EAF1))
                row("car.side", store.l("vehicles_title"), store.l("vehicles_subtitle"), nil, .vehicles)
            }
            Divider().overlay(Color(hex: 0xE8EAF1))
            row("lifepreserver", store.l("support_title"), store.l("support_subtitle"), nil, .support)
        }
        .kjCard(padding: 4)
        .task { unread = (try? await SupabaseService.shared.unreadNotificationCount()) ?? 0 }
    }

    private func row(_ icon: String, _ title: String, _ subtitle: String, _ badge: String?, _ page: ExtrasPage) -> some View {
        Button { onOpen(page) } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(KJ.blue)
                    .frame(width: 40, height: 40).background(Circle().fill(KJ.softBlue))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(KJ.ink)
                    Text(subtitle).font(.system(size: 12, weight: .medium)).foregroundStyle(KJ.muted).lineLimit(2)
                }
                Spacer()
                if let badge {
                    Text(badge).font(.system(size: 12, weight: .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(KJ.burgundy))
                }
                Image(systemName: store.language == .ar ? "chevron.left" : "chevron.right")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(KJ.muted)
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ExtrasHost: View {
    let page: ExtrasPage
    var body: some View {
        switch page {
        case .places: SavedPlacesView()
        case .notifications: NotificationsView()
        case .vehicles: VehiclesView()
        case .support: SupportView()
        }
    }
}

// MARK: Saved places

struct SavedPlacesView: View {
    @EnvironmentObject var store: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var places: [SavedPlace]?
    @State private var error: String?
    @State private var adding = false

    var body: some View {
        VStack(spacing: 0) {
            ExtrasHeader(title: store.l("places_title"), subtitle: store.l("places_subtitle")) { dismiss() }
            ScrollView {
                VStack(spacing: 12) {
                    ErrorLine(text: error)
                    if places == nil {
                        PulsingDots().padding(.top, 30)
                    } else if places?.isEmpty == true {
                        ExtrasEmpty(icon: "mappin.slash", title: store.l("place_none"), hint: store.l("place_none_hint"))
                    } else {
                        ForEach(places ?? []) { p in
                            HStack(spacing: 12) {
                                Image(systemName: icon(p.kind)).foregroundStyle(KJ.blue)
                                    .frame(width: 40, height: 40).background(Circle().fill(KJ.softBlue))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.label).font(.system(size: 16, weight: .bold)).foregroundStyle(KJ.ink)
                                    Text(p.address).font(.system(size: 12)).foregroundStyle(KJ.muted).lineLimit(2)
                                }
                                Spacer()
                                Button { Task { await remove(p) } } label: {
                                    Image(systemName: "trash").foregroundStyle(KJ.danger)
                                }
                                .accessibilityLabel(store.l("delete_action"))
                            }
                            .kjCard(padding: 12)
                        }
                    }
                    Button { adding = true } label: {
                        Label(store.l("place_add"), systemImage: "plus").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(KJButtonStyle())
                    .padding(.top, 6)
                }
                .padding(.horizontal, 20).padding(.bottom, 30)
            }
        }
        .background(KJ.canvasGradient.ignoresSafeArea())
        .task { await load() }
        .sheet(isPresented: $adding) {
            AddPlaceView(existing: places ?? []) { adding = false; Task { await load() } }
        }
    }

    private func icon(_ kind: String) -> String {
        switch kind { case "home": return "house.fill"; case "work": return "briefcase.fill"; default: return "star.fill" }
    }

    private func load() async {
        do { places = try await SupabaseService.shared.savedPlaces(); error = nil }
        catch { self.error = store.serverErrorMessage(error); if places == nil { places = [] } }
    }

    private func remove(_ p: SavedPlace) async {
        do { try await SupabaseService.shared.deleteSavedPlace(id: p.id) } catch { self.error = store.serverErrorMessage(error) }
        await load()
    }
}

private struct AddPlaceView: View {
    @EnvironmentObject var store: AppState
    @Environment(\.dismiss) private var dismiss
    let existing: [SavedPlace]
    let onSaved: () -> Void
    @State private var kind = "favorite"
    @State private var label = ""
    @State private var query = ""
    @State private var results: [(title: String, coord: CLLocationCoordinate2D)] = []
    @State private var chosen: (title: String, coord: CLLocationCoordinate2D)?
    @State private var busy = false
    @State private var error: String?

    private var kinds: [String] {
        ["home", "work", "favorite"].filter { k in k == "favorite" || !existing.contains { $0.kind == k } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ExtrasHeader(title: store.l("place_add")) { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ErrorLine(text: error)
                    HStack(spacing: 8) {
                        ForEach(kinds, id: \.self) { k in
                            Button { kind = k } label: {
                                Text(kindLabel(k)).font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(kind == k ? .white : KJ.ink)
                                    .padding(.horizontal, 14).padding(.vertical, 9)
                                    .background(Capsule().fill(kind == k ? KJ.blue : KJ.softBlue))
                            }
                        }
                    }
                    if kind == "favorite" {
                        TextField(store.l("place_label"), text: $label)
                            .textFieldStyle(.roundedBorder)
                    }
                    HStack {
                        TextField(store.l("place_pick_address"), text: $query)
                            .textFieldStyle(.roundedBorder)
                            .submitLabel(.search)
                            .onSubmit { Task { await search() } }
                        Button { Task { await search() } } label: { Image(systemName: "magnifyingglass") }
                            .buttonStyle(.borderedProminent).tint(KJ.blue)
                    }
                    if busy { PulsingDots() }
                    ForEach(results.indices, id: \.self) { i in
                        Button { chosen = results[i]; query = results[i].title; results = [] } label: {
                            Text(results[i].title).font(.system(size: 14, weight: .semibold)).foregroundStyle(KJ.ink)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                        }
                    }
                    Button { Task { await save() } } label: { Text(store.l("save")).frame(maxWidth: .infinity) }
                        .buttonStyle(KJButtonStyle())
                        .disabled(chosen == nil || (kind == "favorite" && label.trimmingCharacters(in: .whitespaces).isEmpty))
                }
                .padding(.horizontal, 20)
            }
        }
        .background(KJ.canvasGradient.ignoresSafeArea())
        .onAppear { if !kinds.contains(kind) { kind = "favorite" } }
    }

    private func kindLabel(_ k: String) -> String {
        switch k { case "home": return store.l("place_home"); case "work": return store.l("place_work"); default: return store.l("place_favorite") }
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 3 else { return }
        busy = true; error = nil
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = q
        req.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 36.7538, longitude: 3.0588),
                                        span: MKCoordinateSpan(latitudeDelta: 0.6, longitudeDelta: 0.6))
        do {
            let resp = try await MKLocalSearch(request: req).start()
            results = resp.mapItems.prefix(6).map {
                ([$0.name, $0.placemark.locality].compactMap { $0 }.joined(separator: ", "), $0.placemark.coordinate)
            }
        } catch { self.error = store.l("error_generic") }
        busy = false
    }

    private func save() async {
        guard let chosen, let uid = store.session.userId else { return }
        let name = kind == "favorite" ? label.trimmingCharacters(in: .whitespaces) : kindLabel(kind)
        do {
            try await SupabaseService.shared.addSavedPlace(userId: uid, kind: kind, label: name, address: chosen.title,
                                                           lat: chosen.coord.latitude, lng: chosen.coord.longitude)
            onSaved()
        } catch { self.error = store.serverErrorMessage(error) }
    }
}

// MARK: Notifications

struct NotificationsView: View {
    @EnvironmentObject var store: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var items: [AppNotification]?
    @State private var prefs = NotificationPrefs()
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            ExtrasHeader(title: store.l("notif_title"), subtitle: store.l("notif_subtitle")) { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ErrorLine(text: error)
                    Text(store.l("notif_prefs")).font(.system(size: 17, weight: .heavy)).foregroundStyle(KJ.ink)
                    VStack(spacing: 12) {
                        Toggle(isOn: Binding(get: { prefs.rides }, set: { var n = prefs; n.rides = $0; savePrefs(n) })) {
                            prefLabel(store.l("notif_pref_rides"), store.l("notif_pref_rides_hint"))
                        }
                        Toggle(isOn: Binding(get: { prefs.promotions }, set: { var n = prefs; n.promotions = $0; savePrefs(n) })) {
                            prefLabel(store.l("notif_pref_promos"), store.l("notif_pref_promos_hint"))
                        }
                    }
                    .tint(KJ.blue).kjCard()

                    HStack {
                        Text(store.l("notif_title")).font(.system(size: 17, weight: .heavy)).foregroundStyle(KJ.ink)
                        Spacer()
                        if (items ?? []).contains(where: { $0.isUnread }) {
                            Button(store.l("notif_mark_all")) { Task { await markAll() } }
                                .font(.system(size: 13, weight: .bold)).foregroundStyle(KJ.blue)
                        }
                    }
                    .padding(.top, 8)

                    if items == nil {
                        SkeletonList(count: 4).padding(.top, 8)
                    } else if items?.isEmpty == true {
                        ExtrasEmpty(icon: "bell.slash", title: store.l("notif_none"), hint: store.l("notif_none_hint"))
                    } else {
                        ForEach(Array((items ?? []).enumerated()), id: \.element.id) { index, n in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: n.isUnread ? "bell.badge.fill" : "bell")
                                    .foregroundStyle(n.isUnread ? KJ.burgundy : KJ.muted)
                                    .frame(width: 40, height: 40)
                                    .background(Circle().fill(n.isUnread ? KJ.dangerBg : KJ.softBlue))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(n.title).font(.system(size: 15, weight: n.isUnread ? .heavy : .semibold)).foregroundStyle(KJ.ink)
                                    if !n.body.isEmpty { Text(n.body).font(.system(size: 13)).foregroundStyle(KJ.inkSoft) }
                                    Text(extrasDate(n.createdAt, store.language)).font(.system(size: 11)).foregroundStyle(KJ.muted)
                                }
                                Spacer()
                                Button { Task { await remove(n) } } label: { Image(systemName: "trash").foregroundStyle(KJ.muted) }
                                    .accessibilityLabel(store.l("delete_action"))
                            }
                            .kjCard(padding: 12)
                            .onTapGesture { if n.isUnread { Task { await read(n) } } }
                            .kjReveal(index: index)
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 30)
            }
        }
        .background(KJ.canvasGradient.ignoresSafeArea())
        .task {
            await load()
            if let uid = store.session.userId, let p = try? await SupabaseService.shared.notificationPrefs(userId: uid) { prefs = p }
        }
    }

    private func prefLabel(_ title: String, _ hint: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 15, weight: .bold)).foregroundStyle(KJ.ink)
            Text(hint).font(.system(size: 12)).foregroundStyle(KJ.muted)
        }
    }

    private func load() async {
        do { items = try await SupabaseService.shared.notifications(); error = nil }
        catch { self.error = store.serverErrorMessage(error); if items == nil { items = [] } }
    }
    private func read(_ n: AppNotification) async { try? await SupabaseService.shared.markNotificationRead(id: n.id); await load() }
    private func markAll() async {
        do { try await SupabaseService.shared.markAllNotificationsRead() } catch { self.error = store.serverErrorMessage(error) }
        await load()
    }
    private func remove(_ n: AppNotification) async { try? await SupabaseService.shared.deleteNotification(id: n.id); await load() }

    private func savePrefs(_ next: NotificationPrefs) {
        let old = prefs
        prefs = next
        guard let uid = store.session.userId else { return }
        Task {
            do { try await SupabaseService.shared.saveNotificationPrefs(userId: uid, prefs: next) }
            catch { prefs = old; self.error = store.serverErrorMessage(error) }
        }
    }
}

// MARK: Vehicles (driver)

struct VehiclesView: View {
    @EnvironmentObject var store: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var items: [Vehicle]?
    @State private var error: String?
    @State private var editing: Vehicle?
    @State private var showForm = false
    @State private var deleting: Vehicle?

    var body: some View {
        VStack(spacing: 0) {
            ExtrasHeader(title: store.l("vehicles_title"), subtitle: store.l("vehicles_subtitle")) { dismiss() }
            ScrollView {
                VStack(spacing: 12) {
                    ErrorLine(text: error)
                    if items == nil {
                        PulsingDots().padding(.top, 30)
                    } else if items?.isEmpty == true {
                        ExtrasEmpty(icon: "car", title: store.l("veh_none"), hint: store.l("veh_none_hint"))
                    } else {
                        ForEach(items ?? []) { v in card(v) }
                    }
                    Button { editing = nil; showForm = true } label: {
                        Label(store.l("veh_add"), systemImage: "plus").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(KJButtonStyle())
                }
                .padding(.horizontal, 20).padding(.bottom, 30)
            }
        }
        .background(KJ.canvasGradient.ignoresSafeArea())
        .task { await load() }
        .sheet(isPresented: $showForm) {
            VehicleForm(vehicle: editing) { showForm = false; Task { await load() } }
        }
        .alert(store.l("veh_delete_confirm"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button(store.l("delete_action"), role: .destructive) { if let v = deleting { Task { await remove(v) } } }
            Button(store.l("cancel_action"), role: .cancel) {}
        }
    }

    private func card(_ v: Vehicle) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: v.category == "moto" ? "motorcycle.fill" : "car.fill").foregroundStyle(KJ.blue)
                Text("\(v.make) \(v.model)").font(.system(size: 17, weight: .heavy)).foregroundStyle(KJ.ink)
                Spacer()
                if v.isPrimary { badge(store.l("veh_primary"), KJ.success, KJ.successBg) }
                if v.status == "suspended" { badge(store.l("veh_suspended"), KJ.danger, KJ.dangerBg) }
            }
            Text([v.plate, v.color ?? "", v.year.map(String.init) ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(KJ.inkSoft)
            if let r = v.suspendedReason, v.status == "suspended" {
                Text(r).font(.system(size: 12)).foregroundStyle(KJ.danger)
            }
            HStack(spacing: 14) {
                if !v.isPrimary && v.status != "suspended" {
                    Button(store.l("veh_make_primary")) { Task { await makePrimary(v) } }.foregroundStyle(KJ.blue)
                }
                Button(store.l("edit_action")) { editing = v; showForm = true }.foregroundStyle(KJ.blue)
                Button(store.l("delete_action")) { deleting = v }.foregroundStyle(KJ.danger)
            }
            .font(.system(size: 13, weight: .bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .kjCard()
    }

    private func badge(_ t: String, _ fg: Color, _ bg: Color) -> some View {
        Text(t).font(.system(size: 11, weight: .heavy)).foregroundStyle(fg)
            .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(bg))
    }

    private func load() async {
        guard let uid = store.session.userId else { return }
        do { items = try await SupabaseService.shared.myVehicles(driverId: uid); error = nil }
        catch { self.error = store.serverErrorMessage(error); if items == nil { items = [] } }
    }
    private func makePrimary(_ v: Vehicle) async {
        do { try await SupabaseService.shared.setPrimaryVehicle(id: v.id); await store.refreshProfile() } catch { self.error = store.serverErrorMessage(error) }
        await load()
    }
    private func remove(_ v: Vehicle) async {
        do { try await SupabaseService.shared.deleteVehicle(id: v.id); await store.refreshProfile() } catch { self.error = store.serverErrorMessage(error) }
        await load()
    }
}

private struct VehicleForm: View {
    @EnvironmentObject var store: AppState
    @Environment(\.dismiss) private var dismiss
    let vehicle: Vehicle?
    let onSaved: () -> Void
    @State private var category = "car"
    @State private var make = ""
    @State private var model = ""
    @State private var year = ""
    @State private var plate = ""
    @State private var color = ""
    @State private var seats = 4
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ExtrasHeader(title: store.l(vehicle == nil ? "veh_add" : "veh_edit")) { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ErrorLine(text: error)
                    Picker(store.l("veh_category"), selection: $category) {
                        Text(store.l("cat_car")).tag("car")
                        Text(store.l("cat_moto")).tag("moto")
                    }
                    .pickerStyle(.segmented)
                    TextField(store.l("brand"), text: $make).textFieldStyle(.roundedBorder)
                    TextField(store.l("model"), text: $model).textFieldStyle(.roundedBorder)
                    TextField(store.l("veh_year"), text: $year).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                    TextField(store.l("plate"), text: $plate).textInputAutocapitalization(.characters).textFieldStyle(.roundedBorder)
                    TextField(store.l("color"), text: $color).textFieldStyle(.roundedBorder)
                    Stepper("\(store.l("veh_seats")): \(seats)", value: $seats, in: 1...8)
                    Button { Task { await save() } } label: { Text(store.l("save")).frame(maxWidth: .infinity) }
                        .buttonStyle(KJButtonStyle())
                        .disabled(busy || make.isEmpty || model.isEmpty || plate.isEmpty)
                }
                .padding(.horizontal, 20)
            }
        }
        .background(KJ.canvasGradient.ignoresSafeArea())
        .onAppear {
            guard let v = vehicle else { return }
            category = v.category; make = v.make; model = v.model; year = v.year.map(String.init) ?? ""
            plate = v.plate; color = v.color ?? ""; seats = v.seats ?? 4
        }
    }

    private func save() async {
        guard let uid = store.session.userId else { return }
        busy = true; defer { busy = false }
        let y = Int(year.trimmingCharacters(in: .whitespaces))
        if !year.isEmpty && (y == nil || !(1980...2100).contains(y!)) { error = store.l("error_generic"); return }
        let body = VehicleWrite(driver_id: vehicle == nil ? uid : nil, category: category,
                                make: make.trimmingCharacters(in: .whitespaces), model: model.trimmingCharacters(in: .whitespaces),
                                year: y, plate: plate.trimmingCharacters(in: .whitespaces),
                                color: color.trimmingCharacters(in: .whitespaces), seats: seats)
        do {
            if let v = vehicle { try await SupabaseService.shared.updateVehicle(id: v.id, body) }
            else { try await SupabaseService.shared.addVehicle(body) }
            await store.refreshProfile()
            onSaved()
        } catch { self.error = store.serverErrorMessage(error) }
    }
}

// MARK: Receipt

struct ReceiptView: View {
    @EnvironmentObject var store: AppState
    @Environment(\.dismiss) private var dismiss
    let rideId: UUID
    @State private var receipt: RideReceipt?
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            ExtrasHeader(title: store.l("receipt_title")) { dismiss() }
            ScrollView {
                VStack(spacing: 14) {
                    ErrorLine(text: error)
                    if let r = receipt {
                        VStack(alignment: .leading, spacing: 12) {
                            line(store.l("receipt_ref"), r.reference)
                            line(store.l("receipt_date"), extrasDate(r.completedAt ?? r.createdAt, store.language))
                            line(store.l("pickup"), r.pickupLabel)
                            line(store.l("destination"), r.destLabel)
                            if let d = r.driverName { line(store.l("driver"), d) }
                            let car = [r.vehicleMake, r.vehicleModel, r.vehiclePlate].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                            if !car.isEmpty { line(store.l("vehicle"), car) }
                            line(store.l("receipt_payment"), store.l("payment_cash"))
                            Divider()
                            HStack {
                                Text(store.l("receipt_total")).font(.system(size: 17, weight: .heavy)).foregroundStyle(KJ.ink)
                                Spacer()
                                Text(KJFormat.dzd(r.fare)).font(.system(size: 22, weight: .heavy)).foregroundStyle(KJ.blue)
                            }
                        }
                        .kjCard()
                        ShareLink(item: shareText(r)) {
                            Label(store.l("receipt_share"), systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(KJButtonStyle())
                    } else if error == nil {
                        PulsingDots().padding(.top, 40)
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 30)
            }
        }
        .background(KJ.canvasGradient.ignoresSafeArea())
        .task {
            do { receipt = try await SupabaseService.shared.rideReceipt(rideId: rideId) }
            catch { self.error = store.l("receipt_unavailable") }
        }
    }

    private func line(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).font(.system(size: 13, weight: .semibold)).foregroundStyle(KJ.muted)
            Spacer()
            Text(v).font(.system(size: 14, weight: .bold)).foregroundStyle(KJ.ink).multilineTextAlignment(.trailing)
        }
    }

    private func shareText(_ r: RideReceipt) -> String {
        "KHERJA · \(r.reference)\n\(r.pickupLabel) → \(r.destLabel)\n\(KJFormat.dzd(r.fare)) (\(store.l("payment_cash")))"
    }
}

// MARK: Support + SOS

struct SupportView: View {
    @EnvironmentObject var store: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @StateObject private var location = LocationService.shared
    @State private var contact: SupportContact?
    @State private var category = "ride"
    @State private var message = ""
    @State private var info: String?
    @State private var error: String?
    @State private var confirmSOS = false
    @State private var busy = false

    var body: some View {
        VStack(spacing: 0) {
            ExtrasHeader(title: store.l("support_title"), subtitle: store.l("support_subtitle")) { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ErrorLine(text: error)
                    if let info {
                        Label(info, systemImage: "checkmark.circle.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(KJ.success)
                    }
                    sosCard
                    Text(store.l("support_contact")).font(.system(size: 17, weight: .heavy)).foregroundStyle(KJ.ink)
                    VStack(alignment: .leading, spacing: 10) {
                        if let c = contact, !c.phone.isEmpty || !c.email.isEmpty {
                            if !c.phone.isEmpty {
                                Button { if let u = URL(string: "tel:" + c.phone.filter { $0.isNumber || $0 == "+" }) { openURL(u) } } label: {
                                    Label("\(store.l("support_call")) \(c.phone)", systemImage: "phone.fill")
                                }
                            }
                            if !c.email.isEmpty {
                                Button { if let u = URL(string: "mailto:" + c.email) { openURL(u) } } label: {
                                    Label(c.email, systemImage: "envelope.fill")
                                }
                            }
                        } else {
                            Text(store.l("support_contact_none")).font(.system(size: 13)).foregroundStyle(KJ.muted)
                        }
                    }
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(KJ.blue)
                    .frame(maxWidth: .infinity, alignment: .leading).kjCard()

                    Text(store.l("ticket_new")).font(.system(size: 17, weight: .heavy)).foregroundStyle(KJ.ink)
                    VStack(alignment: .leading, spacing: 10) {
                        Picker(store.l("ticket_category"), selection: $category) {
                            ForEach(["ride", "payment", "account", "safety", "other"], id: \.self) { Text(store.l("cat_" + $0)).tag($0) }
                        }
                        .tint(KJ.blue)
                        TextEditor(text: $message).frame(minHeight: 110)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: 0xE8EAF1)))
                        Button { Task { await sendTicket() } } label: { Text(store.l("ticket_send")).frame(maxWidth: .infinity) }
                            .buttonStyle(KJButtonStyle()).disabled(busy)
                    }
                    .kjCard()
                }
                .padding(.horizontal, 20).padding(.bottom, 30)
            }
        }
        .background(KJ.canvasGradient.ignoresSafeArea())
        .task { contact = try? await SupabaseService.shared.supportContact() }
        .alert(store.l("sos_confirm"), isPresented: $confirmSOS) {
            Button(store.l("sos_button"), role: .destructive) { Task { await sendSOS() } }
            Button(store.l("cancel_action"), role: .cancel) {}
        }
    }

    private var sosCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(store.l("sos_title"), systemImage: "exclamationmark.shield.fill")
                .font(.system(size: 17, weight: .heavy)).foregroundStyle(KJ.danger)
            Text(store.l("sos_hint")).font(.system(size: 13)).foregroundStyle(KJ.inkSoft)
            Button { confirmSOS = true } label: {
                Text(store.l("sos_button")).font(.system(size: 16, weight: .heavy)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 50).background(Capsule().fill(KJ.danger))
            }
            .disabled(busy)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .kjCard()
    }

    private func sendTicket() async {
        guard let uid = store.session.userId else { return }
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 5 else { error = store.l("ticket_too_short"); info = nil; return }
        busy = true; defer { busy = false }
        do {
            try await SupabaseService.shared.createTicket(userId: uid, category: category, message: text, rideId: store.activeRideId)
            message = ""; error = nil; info = store.l("ticket_sent")
        } catch { self.error = store.serverErrorMessage(error); info = nil }
    }

    private func sendSOS() async {
        busy = true; defer { busy = false }
        let loc = location.location
        do {
            try await SupabaseService.shared.raiseSOS(rideId: store.activeRideId, lat: loc?.coordinate.latitude, lng: loc?.coordinate.longitude)
            error = nil
            info = store.l("sos_sent") + (loc == nil ? " " + store.l("sos_no_location") : "")
        } catch { self.error = store.serverErrorMessage(error); info = nil }
    }
}
