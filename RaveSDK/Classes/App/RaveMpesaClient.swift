//
//  RaveMpesaClient.swift
//  GetBarter
//
//  Created by Olusegun Solaja on 14/08/2018.
//  Copyright © 2018 Olusegun Solaja. All rights reserved.
//

import Foundation
import UIKit

public typealias FeeSuccessHandler = ((String?, String?) -> Void)
public typealias ErrorHandler = ((String?, [String: Any]?) -> Void)

protocol GetFee {
    func getFee(param: [String: String], feeSuccessHandler: FeeSuccessHandler?, errorHandler: ErrorHandler?)
}

extension GetFee {

    func getFee(param: [String: String], feeSuccessHandler: FeeSuccessHandler?, errorHandler: ErrorHandler?) {

        RavePayService.getFee(param, resultCallback: { (result) in
            if let fee =  result?.data?.fee {
                let chargeAmount = result?.data?.chargeAmount
                feeSuccessHandler?("\(fee)", chargeAmount)
            } else {
                if let err = result?.message {
                    errorHandler?(err, nil)
                }
            }

        }, errorCallback: { (err) in
            errorHandler?(err, nil)
        })
    }
}

public class RaveMpesaClient: GetFee {
    public var amount: String?
    public var phoneNumber: String?
    public var email: String? = ""

    // MARK: Typealias

    public typealias PendingHandler = ((String?, String?) -> Void)
    public typealias SuccessHandler = ((String?, [String: Any]?) -> Void)

    // MARK: Handler
    public var errorHandler: ErrorHandler?
    public var feeSuccessHandler: FeeSuccessHandler?
    public var chargeSuccessHandler: SuccessHandler?
    public var chargePendingHandler: PendingHandler?

    public var transactionReference: String?
    public var businessNumber: String?
    public var accountNumber: String?

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
            "ptype": "3"]
           getFee(param: param, feeSuccessHandler: feeSuccessHandler, errorHandler: errorHandler)

    }

    // MARK: Charge
    public func chargeMpesa() {
        if let pubkey = RaveConfig.sharedConfig().publicKey {
            var country: String = ""
            switch RaveConfig.sharedConfig().currencyCode {
            case .KES, .TZS, .GHS, .ZAR:
                country = RaveConfig.sharedConfig().country
            default:
                country = "NG"
            }
            var param: [String: Any] = [
                "PBFPubKey": pubkey,
                "amount": amount!,
                "email": email!,
                "is_mpesa": "1",
                "is_mpesa_lipa": "1",
                "phonenumber": phoneNumber ?? "",
                "firstname": RaveConfig.sharedConfig().firstName ?? "",
                "lastname": RaveConfig.sharedConfig().lastName ?? "",
                "currency": RaveConfig.sharedConfig().currencyCode ,
                "payment_type": "mpesa",
                "country": country ,
                "meta": "",
                "IP": getIFAddresses().first!,
                "txRef": transactionReference!,
                "device_fingerprint": (UIDevice.current.identifierForVendor?.uuidString)!
            ]
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
            let jsonString  = param.jsonStringify()
            //getEncryptionKey(RaveConfig.sharedConfig().secretKey!)
            let secret =  RaveConfig.sharedConfig().encryptionKey!
            let data =  TripleDES.encrypt(string: jsonString, key: secret)
            let base64String = data?.base64EncodedString()

            let reqbody = [
                "PBFPubKey": pubkey,
                "client": base64String!, // Encrypted $data payload here.
                "alg": "3DES-24"
            ]
            RavePayService.charge(reqbody, resultCallback: { (res) in
                if let status = res?["status"] as? String {
                    if status == "success"{
                        let result = res?["data"] as? [String: AnyObject]
                        let flwTransactionRef = result?["flwRef"] as? String
                        if let chargeResponse = result?["chargeResponseCode"] as? String {
                            switch chargeResponse {
                            case "00":
                                self.chargeSuccessHandler?(flwTransactionRef!, res)

                            case "02":

                                if let type =  result?["paymentType"] as? String {
                                    if type.containsIgnoringCase(find: "mpesa") || type.containsIgnoringCase(find: "mobilemoneygh") {
                                        if let status =  result?["status"] as? String {
                                            if status.containsIgnoringCase(find: "pending") {

                                                self.chargePendingHandler?("Transaction Processing", "A push notification has been sent to your phone, please complete the transaction by entering your pin.\n Please do not close this page until transaction is completed")
                                                self.businessNumber =   result?["business_number"] as? String
                                                self.accountNumber =  result?["orderRef"] as? String
                                                if let txRef = result?["flwRef"] as? String {
                                                    self.queryMpesaTransaction(txRef: txRef)
                                                }
                                            }
                                        }
                                    }
                                }
                            default:
                                break
                            }
                        }
                    } else {
                        if let message = res?["message"] as? String {
                            self.errorHandler?(message, res)
                        }
                    }
                }

            }, errorCallback: { (err) in

                self.errorHandler?(err, nil)
            })

        }
    }

    // MARK: Requery transaction
    func queryMpesaTransaction(txRef: String?) {
        if let secret = RaveConfig.sharedConfig().publicKey, let  ref = txRef {
            let param = ["PBFPubKey": secret, "flw_ref": ref]
            RavePayService.mpesaQueryTransaction(param, resultCallback: { (result) in
                if let  status = result?["status"] as? String {
                    if status == "success" {
                        if let data = result?["data"] as? [String: AnyObject] {
                            let flwRef = data["flwref"] as? String
                            if let chargeCode = data["chargeResponseCode"] as?  String {
                                switch chargeCode {
                                case "00":
                                    self.chargeSuccessHandler?(flwRef, result)

                                default:
                                    self.queryMpesaTransaction(txRef: ref)
                                }
                            } else {
                                self.queryMpesaTransaction(txRef: ref)
                            }
                        }
                    } else {
                        self.errorHandler?("Something went wrong please try again.", nil)
                    }
                }
            }, errorCallback: { (err) in

                if err.containsIgnoringCase(find: "serialize") || err.containsIgnoringCase(find: "JSON") {
                    self.errorHandler?("Request Timed Out", nil)
                } else {
                    self.errorHandler?(err, nil)
                }

            })
        }
    }
}
