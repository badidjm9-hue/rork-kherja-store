//
//  KHERJATests.swift
//  KHERJATests
//
//  Created by Rork on November 23, 2026.
//

import Testing
@testable import KHERJA

struct KHERJATests {

    private func d(_ s: String) -> Data { Data(s.utf8) }

    @Test func gatewayAndTransportFailuresAreServiceErrors() {
        #expect(AuthServiceError.classify(status: 404, body: d("{}")) == .service)
        #expect(AuthServiceError.classify(status: 503, body: d("oops")) == .service)
        #expect(AuthServiceError.classify(status: 200, body: d("<html>")) == .service)
        #expect(AuthServiceError.classify(status: 401, body: d("{\"message\":\"Invalid JWT\"}")) == .service)
        #expect(AuthServiceError.classify(status: 403, body: d("{\"message\":\"forbidden\"}")) == .service)
        #expect(AuthServiceError.classify(status: 429, body: d("Too Many Requests")) == .rateLimited)
        #expect(AuthServiceError.classify(status: 429, body: d("{\"message\":\"slow down\"}")) == .rateLimited)
    }

    @Test func functionBusinessRepliesPassThrough() {
        #expect(AuthServiceError.classify(status: 200, body: d("{\"ok\":true}")) == nil)
        #expect(AuthServiceError.classify(status: 400, body: d("{\"error\":\"Code incorrect\"}")) == nil)
        #expect(AuthServiceError.classify(status: 401, body: d("{\"error\":\"Numéro ou mot de passe incorrect\"}")) == nil)
        #expect(AuthServiceError.classify(status: 429, body: d("{\"error\":\"Trop de tentatives\"}")) == nil)
        #expect(AuthServiceError.classify(status: 503, body: d("{\"error\":\"Service SMS indisponible\"}")) == .service)
    }

    @Test func exceptionKeysMapToUserMessages() {
        #expect(AuthRules.exceptionKey(AuthServiceError.network) == "err_network")
        #expect(AuthRules.exceptionKey(AuthServiceError.service) == "err_auth_service")
        #expect(AuthRules.exceptionKey(AuthServiceError.rateLimited) == "err_too_many")
        #expect(AuthRules.exceptionKey(URLError(.notConnectedToInternet)) == "err_network")
        #expect(AuthRules.exceptionKey(CancellationError()) == "error_generic")
    }

    @Test func cancellationIsNotANetworkFailure() {
        #expect(AuthRules.isCancellation(CancellationError()))
        #expect(AuthRules.isCancellation(URLError(.cancelled)))
        #expect(!AuthRules.isCancellation(URLError(.notConnectedToInternet)))
        #expect(!AuthRules.isCancellation(URLError(.timedOut)))
        #expect(!AuthRules.isCancellation(AuthServiceError.network))
        #expect(AuthRules.exceptionKey(URLError(.cancelled)) != "err_network")
        // Other network errors keep the offline message.
        #expect(AuthRules.exceptionKey(URLError(.networkConnectionLost)) == "err_network")
        #expect(AuthRules.exceptionKey(URLError(.timedOut)) == "err_network")
    }

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

}
