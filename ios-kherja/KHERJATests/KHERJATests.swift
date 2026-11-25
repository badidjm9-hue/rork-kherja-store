//
//  KHERJATests.swift
//  KHERJATests
//
//  Authentication input-validation regression tests.
//

import Testing
@testable import KHERJA

struct KHERJATests {
    // MARK: Phone number validation

    @Test func acceptsSupportedAlgerianMobilePrefixes() {
        #expect(AuthRules.normalizePhone("0555123456") == "0555123456")
        #expect(AuthRules.normalizePhone("0661234567") == "0661234567")
        #expect(AuthRules.normalizePhone("0771234567") == "0771234567")
    }

    @Test func acceptsPhoneNumberFormatting() {
        #expect(AuthRules.normalizePhone("0555 12 34 56") == "0555123456")
        #expect(AuthRules.normalizePhone("0555-12-34-56") == "0555123456")
        #expect(AuthRules.normalizePhone("(0555) 12 34 56") == "0555123456")
    }

    @Test func rejectsInvalidPhoneNumbers() {
        for input in ["", "055512345", "05551234567", "0455123456", "0855123456", "1555123456", "+213555123456", "phone0555123456"] {
            #expect(AuthRules.normalizePhone(input) == nil, "Should reject: \\(input)")
        }
    }

    // MARK: Password rules

    @Test func acceptsPasswordsAtMinimumAndMaximumCharacterBoundaries() {
        #expect(AuthRules.passwordValid("Kherja2026"))
        #expect(AuthRules.passwordValid(String(repeating: "a", count: 71) + "1"))
        #expect(AuthRules.passwordValid(String(repeating: "a", count: 70) + "1"))
    }

    @Test func rejectsPasswordsOutsideLengthBoundaries() {
        #expect(!AuthRules.passwordValid("a1"))
        #expect(!AuthRules.passwordValid(String(repeating: "a", count: 71) + "12"))
    }

    @Test func requiresAtLeastOneLetterAndOneAsciiDigit() {
        #expect(!AuthRules.passwordValid("abcdefgh"))
        #expect(!AuthRules.passwordValid("12345678"))
        #expect(!AuthRules.passwordValid("abcdefgh١٢"))
        #expect(AuthRules.passwordValid("مرحبا12345"))
        #expect(AuthRules.passwordValid("Kherja2026"))
    }

    @Test func rejectsEmojiOnlyAndPunctuationOnlyPasswords() {
        #expect(!AuthRules.passwordValid("😀😀😀😀😀😀😀😀"))
        #expect(!AuthRules.passwordValid("!@#$%^&*123"))
    }

    // MARK: Optional contact email

    @Test func acceptsOptionalOrWellFormedEmail() {
        #expect(AuthRules.emailValid(""))
        #expect(AuthRules.emailValid("   "))
        #expect(AuthRules.emailValid("user@example.com"))
        #expect(AuthRules.emailValid("user.name+tag@example.co.uk"))
        #expect(AuthRules.emailValid("  user@example.com  "))
    }

    @Test func rejectsMalformedOrOverlongEmail() {
        for input in ["not-an-email", "user@", "@example.com", "user@example", "user name@example.com", "user@@example.com"] {
            #expect(!AuthRules.emailValid(input), "Should reject: \\(input)")
        }
        #expect(!AuthRules.emailValid(String(repeating: "a", count: 243) + "@example.com"))
    }

    // MARK: Server-error localization mapping

    @Test func mapsAuthenticationErrorsToLocalizedKeys() {
        #expect(AuthRules.errorKey("Numéro ou mot de passe incorrect") == "err_login_failed")
        #expect(AuthRules.errorKey("Trop de tentatives, réessayez plus tard") == "err_too_many")
        #expect(AuthRules.errorKey("Un compte existe déjà avec ce numéro") == "err_account_exists")
        #expect(AuthRules.errorKey("Aucun compte associé à ce numéro") == "err_no_account")
        #expect(AuthRules.errorKey("Service SMS indisponible") == "err_sms_unavailable")
        #expect(AuthRules.errorKey("Code incorrect") == "wrong_code")
    }

    @Test func unknownAuthenticationErrorsUseGenericFallback() {
        #expect(AuthRules.errorKey(nil) == "error_generic")
        #expect(AuthRules.errorKey("Unexpected upstream failure") == "error_generic")
    }
}
