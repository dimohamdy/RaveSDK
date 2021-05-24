//
//  RaveCardClient.swift
//  GetBarter
//
//  Created by Olusegun Solaja on 14/08/2018.
//  Copyright © 2018 Olusegun Solaja. All rights reserved.
//

import Foundation
import UIKit

public class RaveCardClient: GetFee {
    public var cardNumber: String?
    public var cardfirst6: String?
    public var cvv: String?
    public var amount: String?
    public var expYear: String?
    public var expMonth: String?
    public var saveCard = true
    public var otp: String?

    public var isSaveCardCharge: String?
    public var saveCardPayment: String?
    public var savedCardHash: String?
    public var savedCardMobileNumber: String?

    public var transactionReference: String?
    public var bodyParam: [String: Any]? = [:]

    // MARK: Typealias
    public typealias FeeSuccessHandler = ((String?, String?) -> Void)
    public typealias SuccessHandler = ((String?, [String: Any]?) -> Void)
    public typealias ErrorHandler = ((String?, [String: Any]?) -> Void)
    public typealias SuggestedAuthHandler = ((SuggestedAuthModel, [String: Any]?, String?) -> Void)
    public typealias OTPAuthHandler = ((String, String) -> Void)
    public typealias WebAuthHandler = ((String, String) -> Void)
    public typealias SaveCardSuccessHandler = (([SavedCard]?) -> Void)
    public typealias SaveCardErrorHandler = ((String?) -> Void)
    public typealias RemoveSavedCardSuccessHandler = (() -> Void)
    public typealias RemoveSavedCardErrorHandler = ((String?) -> Void)

    // MARK: Handler
	public var errorHandler: ErrorHandler?
	public var saveCardErrorHandler: SaveCardErrorHandler?
	public var saveCardSuccessHandler: SaveCardSuccessHandler?
	public var removesavedCardErrorHandler: RemoveSavedCardErrorHandler?
	public var removesavedCardSuccessHandler: RemoveSavedCardSuccessHandler?
	public var validateErrorHandler: ErrorHandler?
	public var feeSuccessHandler: FeeSuccessHandler?
	public var chargeSuggestedAuthHandler: SuggestedAuthHandler?
	public var chargeOTPAuthHandler: OTPAuthHandler?
	public var chargeWebAuthHandler: WebAuthHandler?
	public var chargeSuccessHandler: SuccessHandler?
	public var sendOTPSuccessHandler: SaveCardErrorHandler?
	public var sendOTPErrorHandler: SaveCardErrorHandler?
	public var selectedCard: SavedCard?

    private var isRetryCharge = false
    private var retryChargeValue: String?

	public init() {}

    // MARK: Transaction Fee
    public func getFee() {
        guard let pubkey = RaveConfig.sharedConfig().publicKey else {
            self.errorHandler?("Public Key is not specified", nil)
            return
        }
        let param = [
                "PBFPubKey": pubkey,
                "amount": amount!,
                "currency": RaveConfig.sharedConfig().currencyCode.rawValue,
                "card6": cardfirst6!]

        getFee(param: param, feeSuccessHandler: feeSuccessHandler, errorHandler: errorHandler)
    }

    // MARK: Charge Saved Card
    public func saveCardCharge() {
        if let pubkey = RaveConfig.sharedConfig().publicKey {
            var country: String = ""
            switch RaveConfig.sharedConfig().currencyCode {
                       case .KES, .TZS, .GHS, .ZAR:
                           country = RaveConfig.sharedConfig().country
                       default:
                           country = "NG"
                       }
            var param: [String: Any] = ["PBFPubKey": pubkey,
                                      "IP": getIFAddresses().first!,
                                      "device_fingerprint": (UIDevice.current.identifierForVendor?.uuidString)!,
                                      "email": RaveConfig.sharedConfig().email!,
                                      "currency": RaveConfig.sharedConfig().currencyCode,
                                      "country": country,
                                      "amount": amount ?? "",
                                      "firstname": RaveConfig.sharedConfig().firstName ?? "",
                                      "lastname": RaveConfig.sharedConfig().lastName ?? "",
                                      "txRef": RaveConfig.sharedConfig().transcationRef!]
            if let saveCard = isSaveCardCharge {
                param.merge(["is_saved_card_charge": saveCard])
            }
            if let _otp = otp {
                param.merge(["otp": _otp])
            }
            if let saveCardType = saveCardPayment {
                param.merge(["payment_type": saveCardType])
            }
            if let brand = selectedCard?.card?.cardBrand {
                if brand.lowercased() == "visa"{
                  param.merge(["is_visa": true])
                } else {
                  param.merge(["is_visa": false])
                }

            }
            if let device = selectedCard?.mobileNumber {
                param.merge(["device_key": device])
            }
            if let hash = selectedCard?.cardHash {
                param.merge(["card_hash": hash])
            }
            if RaveConfig.sharedConfig().isPreAuth {
                param.merge(["charge_type": "preauth"])
            }
            if let subAccounts = RaveConfig.sharedConfig().subAccounts {
                let subAccountDict =  subAccounts.map { (subAccount) -> [String: String] in
                    var dict = ["id": subAccount.id]
                    if let ratio = subAccount.ratio {
                        dict.merge(["transaction_split_ratio": "\(ratio)"])
                    }
                    if let chargeType = subAccount.charge_type {
                        switch chargeType {
                        case .flat :
                            dict.merge(["transaction_charge_type": "flat"])
                            if let charge = subAccount.charge {
                                dict.merge(["transaction_charge": "\(charge)"])
                            }
                        case .percentage:
                            dict.merge(["transaction_charge_type": "percentage"])
                            if let charge = subAccount.charge {
                                dict.merge(["transaction_charge": "\((charge / 100))"])
                            }
                        }
                    }

                    return dict
                }
                param.merge(["subaccounts": subAccountDict])
            }
            if let meta = RaveConfig.sharedConfig().meta {
                param.merge(["meta": meta])
            }

            let jsonString  = param.jsonStringify()
            let secret = RaveConfig.sharedConfig().encryptionKey!
            let data =  TripleDES.encrypt(string: jsonString, key: secret)
            let base64String = data?.base64EncodedString()

            let reqbody = [
                "PBFPubKey": pubkey,
                "client": base64String!, // Encrypted $data payload here.
                "alg": "3DES-24"
            ]
            RavePayService.charge(reqbody, resultCallback: { [weak self] (res) in
                guard let strongSelf = self else {return}
                if let status = res?["status"] as? String {
                    if status == "success"{
                        let result = res?["data"] as? [String: AnyObject]
                        if let suggestedAuth = result?["suggested_auth"] as? String {
                            var authModel: SuggestedAuthModel = .NONE
                            switch suggestedAuth {
                            case "PIN":
                                authModel = .PIN
                            case "AVS_VBVSECURECODE":
                                authModel = .AVS_VBVSECURECODE
                            case "VBVSECURECODE":
                                authModel = .VBVSECURECODE
                            case "NOAUTH_INTERNATIONAL":
                                authModel = .NOAUTH_INTERNATIONAL
                            case "GTB_OTP":
                                authModel = .GTB_OTP
                            default:
                                authModel = .NONE
                            }
                            let authURL = result?["authurl"] as? String
                            strongSelf.chargeSuggestedAuthHandler?(authModel, result!, authURL)

                        } else {
                            if let chargeResponse = result?["chargeResponseCode"] as? String {
                                switch chargeResponse {
                                case "00":
                                    let flwTransactionRef = result?["flwRef"] as? String
                                    strongSelf.chargeSuccessHandler?(flwTransactionRef, result)
                                case "02":
                                    let flwTransactionRef = result?["flwRef"] as? String
                                    var _instruction: String? =  result?["chargeResponseMessage"] as? String
                                    if let instruction = result?["validateInstruction"] as? String {
                                        _instruction = instruction
                                    } else {
                                        if let instruction = result?["validateInstructions"] as? [String: AnyObject] {
                                            if let  _inst =  instruction["instruction"] as? String {
                                                if _inst != ""{
                                                    _instruction = _inst
                                                }
                                            }
                                        }
                                    }
                                    if let authURL = result?["authurl"] as? String, authURL != "NO-URL", authURL != "N/A" {
                                        // Show Web View
                                        strongSelf.chargeWebAuthHandler?(flwTransactionRef!, authURL)
                                    } else {
                                        if let flwRef = flwTransactionRef {
                                            // Show OTP Screen
                                            strongSelf.chargeOTPAuthHandler?(flwRef, _instruction ?? "Pending OTP Validation")
                                        }
                                    }
                                default:
                                    break
                                }
                            }

                        }
                    } else {
                        if let message = res?["message"] as? String {
                            strongSelf.errorHandler?(message, nil)
                        }
                    }
                }
            }) {[weak self] (err) in
                guard let strongSelf = self else {return}
                strongSelf.errorHandler?(err, nil)
            }
        }
    }
    // MARK: Charge Card
    public func chargeCard() {
        if let pubkey = RaveConfig.sharedConfig().publicKey {
            var country: String = ""
            switch RaveConfig.sharedConfig().currencyCode {
                       case .KES, .TZS, .GHS, .ZAR:
                           country = RaveConfig.sharedConfig().country
                       default:
                           country = "NG"
                       }
            guard let _ = cardNumber else {
                fatalError("Card Number is missing")
            }
            guard let _ = cvv else {
                fatalError("CVV Number is missing")
            }
            guard let _ = amount else {
                fatalError("Amount is missing")
            }
            guard let _ = expYear else {
                fatalError("Expiry Year is missing")
            }
            guard let _ = expMonth else {
                fatalError("Expiry Month is missing")
            }
            guard let _ = RaveConfig.sharedConfig().email else {
                fatalError("Email address is missing")
            }
            guard let _ = RaveConfig.sharedConfig().transcationRef else {
                fatalError("transactionRef is missing")
            }
            var param: [String: Any] = ["PBFPubKey": pubkey ,
                                      "cardno": cardNumber ?? "",
                                      "cvv": cvv ?? "",
                                      "amount": amount ?? "",
                                      "expiryyear": expYear ?? "",
                                      "expirymonth": expMonth ?? "",
                                      "firstname": RaveConfig.sharedConfig().firstName ?? "",
                                      "lastname": RaveConfig.sharedConfig().lastName ?? "",
                                      "email": RaveConfig.sharedConfig().email!,
                                      "currency": RaveConfig.sharedConfig().currencyCode,
                                      "country": country,
                                      "IP": getIFAddresses().first!,
                                      "txRef": RaveConfig.sharedConfig().transcationRef!,
                                      "device_fingerprint": (UIDevice.current.identifierForVendor?.uuidString)!]
            if let narrate = RaveConfig.sharedConfig().narration {
                param.merge(["narration": narrate])
            }
            if RaveConfig.sharedConfig().isPreAuth {
                param.merge(["charge_type": "preauth"])
            }

            if let subAccounts = RaveConfig.sharedConfig().subAccounts {
                let subAccountDict =  subAccounts.map { (subAccount) -> [String: String] in
                    var dict = ["id": subAccount.id]
                    if let ratio = subAccount.ratio {
                        dict.merge(["transaction_split_ratio": "\(ratio)"])
                    }
                    if let chargeType = subAccount.charge_type {
                        switch chargeType {
                        case .flat :
                            dict.merge(["transaction_charge_type": "flat"])
                            if let charge = subAccount.charge {
                                dict.merge(["transaction_charge": "\(charge)"])
                            }
                        case .percentage:
                            dict.merge(["transaction_charge_type": "percentage"])
                            if let charge = subAccount.charge {
                                dict.merge(["transaction_charge": "\((charge / 100))"])
                            }
                        }
                    }

                    return dict
                }
                param.merge(["subaccounts": subAccountDict])
            }

            if let meta = RaveConfig.sharedConfig().meta {
                param.merge(["meta": meta])
            }
            if saveCard {
                if let phone = RaveConfig.sharedConfig().phoneNumber, phone != ""{
                    param.merge(["remember_device_mobile_key": phone, "remember_device_email": RaveConfig.sharedConfig().email!, "is_remembered": "1"])
                }
            }

            if bodyParam?.count == 0 {
                bodyParam = param
            }
            if isRetryCharge {
                if let retryValue = self.retryChargeValue {
                    bodyParam?.merge(["retry_charge": retryValue])
                }
            }
            let jsonString  = bodyParam!.jsonStringify()
            let secret = RaveConfig.sharedConfig().encryptionKey!
            let data =  TripleDES.encrypt(string: jsonString, key: secret)
            let base64String = data?.base64EncodedString()

            let reqbody = [
                "PBFPubKey": pubkey,
                "client": base64String!, // Encrypted $data payload here.
                "alg": "3DES-24"
            ]

            RavePayService.charge(reqbody, resultCallback: { [weak self] (res) in
                guard let strongSelf = self else {return}
                if let status = res?["status"] as? String {
                    if status == "success"{
                        let result = res?["data"] as? [String: AnyObject]
                        if let suggestedAuth = result?["suggested_auth"] as? String {
                            var authModel: SuggestedAuthModel = .NONE
                            switch suggestedAuth {
                            case "PIN":
                                authModel = .PIN
                            case "AVS_VBVSECURECODE":
                                authModel = .AVS_VBVSECURECODE
                            case "VBVSECURECODE":
                                authModel = .VBVSECURECODE
                            case "NOAUTH_INTERNATIONAL":
                                authModel = .NOAUTH_INTERNATIONAL
                            case "GTB_OTP":
                                authModel = .GTB_OTP
                            default:
                                authModel = .NONE
                            }
                            let authURL = result?["authurl"] as? String
                            strongSelf.chargeSuggestedAuthHandler?(authModel, result!, authURL)

                        } else {
                            if let chargeResponse = result?["chargeResponseCode"] as? String {
                                switch chargeResponse {
                                case "00":
                                    let flwTransactionRef = result?["flwRef"] as? String
                                    strongSelf.chargeSuccessHandler?(flwTransactionRef, result)
                                case "02":
                                    let flwTransactionRef = result?["flwRef"] as? String
                                    var _instruction: String? =  result?["chargeResponseMessage"] as? String
                                    if let instruction = result?["validateInstruction"] as? String {
                                        _instruction = instruction
                                    } else {
                                        if let instruction = result?["validateInstructions"] as? [String: AnyObject] {
                                            if let  _inst =  instruction["instruction"] as? String {
                                                if _inst != ""{
                                                    _instruction = _inst
                                                }
                                            }
                                        }
                                    }
                                    if let authURL = result?["authurl"] as? String, authURL != "NO-URL", authURL != "N/A" {
                                          // Show Web View
                                          strongSelf.chargeWebAuthHandler?(flwTransactionRef!, authURL)
                                    } else {
                                        if let flwRef = flwTransactionRef {
                                          // Show OTP Screen
                                            strongSelf.chargeOTPAuthHandler?(flwRef, _instruction ?? "Pending OTP Validation")
                                        }
                                    }
                                default:
                                    break
                                }
                            }

                        }
                    } else {
                        if let message = res?["message"] as? String {
                            strongSelf.errorHandler?(message, res)
                        }
                    }
                }
            }) {[weak self] (err) in
                guard let strongSelf = self else {return}
                 strongSelf.errorHandler?(err, nil)
            }

        } else {
           self.errorHandler?("Public Key is not specified", nil)
        }
    }

    // MARK: Validate Card
    public func validateCardOTP() {
        guard let ref = self.transactionReference, let _otp = otp else {
            self.errorHandler?("Transaction Reference  or OTP is not set", nil)
            return
        }
        let reqbody = [
            "PBFPubKey": RaveConfig.sharedConfig().publicKey!,
            "transaction_reference": ref,
            "otp": _otp
        ]
        RavePayService.validateCardOTP(reqbody, resultCallback: { (result) in
            if let res =  result {
                print(result ?? "")
                if let status = res ["status"] as? String {
                    if status.containsIgnoringCase(find: "success") {
                        if let data = res ["data"] as? [String: AnyObject] {
                            if let _data = data ["data"] as? [String: AnyObject] {
                                if  let responseCode = _data["responsecode"] as? String {
                                    if responseCode == "00"{
                                        if let tx = data["tx"] as? [String: AnyObject] {
                                            if let ref = tx["flwRef"] as? String {
                                                self.chargeSuccessHandler?(ref, data)
                                            }
                                        } else {
                                            let message = res ["message"] as? String
                                            self.validateErrorHandler?(message, data)

                                        }
                                    } else {
                                        if let message = _data["responsemessage"] as? String {
                                            if self.isMasterCard() && !(message.containsIgnoringCase(find: "insufficient")) {
                                                let tx = data["tx"] as? [String: AnyObject]
                                                self.retryChargeValue =  tx?["txRef"] as? String
                                                self.isRetryCharge = true
                                                self.chargeCard()
                                            } else {
                                                let message = res ["message"] as? String
                                                self.validateErrorHandler?(message, data)
                                            }
                                        }
                                    }
                                }
                            }

                        }
                    } else {
                        let message = res ["message"] as? String
                        self.validateErrorHandler?(message, nil)

                    }
                } else {
                        let message = res ["message"] as? String
                        self.validateErrorHandler?(message, nil)
                }

            }
        }) { (err) in
            if err.containsIgnoringCase(find: "serialize") || err.containsIgnoringCase(find: "JSON") {
                 self.validateErrorHandler?("Request Timed Out", nil)
            } else {
                self.validateErrorHandler?(err, nil)
            }
        }
    }

    // MARK: Fetch saved card
    func fetchSavedCards() {
        if let pubkey = RaveConfig.sharedConfig().publicKey {
            if let deviceNumber = RaveConfig.sharedConfig().phoneNumber {
                let param = ["public_key": pubkey, "device_key": deviceNumber]

                RavePayService.getSavedCards(param, resultCallback: {[weak self] (cardResponse) in
                    guard let  strongSelf = self else { return}
                    strongSelf.saveCardSuccessHandler?(cardResponse.cards)
                }) {[weak self] (err) in
                    guard let  strongSelf = self else { return}
                    strongSelf.saveCardErrorHandler?(err)
                }
            }

        }
    }
    // MARK: Transaction Fee
    public func removeSavedCard() {
        if let pubkey = RaveConfig.sharedConfig().publicKey {
            let param = [
                "public_key": pubkey,
                "card_hash": savedCardHash!,
                "mobile_number": savedCardMobileNumber!]
            RavePayService.removeSavedCard(param, resultCallback: {[weak self] (_) in
                guard let strongSelf = self else {return}
                    strongSelf.removesavedCardSuccessHandler?()
                }, errorCallback: {[weak self] (err) in
                    guard let strongSelf = self else {return}
                    strongSelf.removesavedCardErrorHandler?(err)
            })
        } else {
            self.removesavedCardErrorHandler?("Public Key is not specified")
        }
    }

    // MARK: Send OTP
      func sendOTP(card: SavedCard) {
        if let pubkey = RaveConfig.sharedConfig().publicKey {
            let param = ["public_key": pubkey, "card_hash": card.cardHash ?? "", "device_key": card.mobileNumber ?? ""]
            RavePayService.sendOTP(param, resultCallback: {[weak self] (message) in
                guard let  strongSelf = self else { return}
                strongSelf.sendOTPSuccessHandler?(message)
            }) {[weak self] (err) in
                guard let  strongSelf = self else { return}
                strongSelf.sendOTPErrorHandler?(err)
            }
        }
     }

    func isMasterCard() -> Bool {
        if let cardNumber = self.cardNumber {
            if cardNumber.hasPrefix("5") {
                return true
            } else {
                return false
            }
        } else {
            return false
        }
    }

}
