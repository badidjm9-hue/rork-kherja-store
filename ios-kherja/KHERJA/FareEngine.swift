//
//  FareEngine.swift
//  KHERJA
//
//  Prices are computed only by the server (`quote_fare`, `driver_offer_preview`,
//  `create_request`, `make_offer`, `accept_offer`) from the admin-managed,
//  versioned pricing grid. The app never knows rates, formulas or commission.
//

import Foundation

enum VehicleKind: String, Codable, CaseIterable {
    case car
    case moto
}
