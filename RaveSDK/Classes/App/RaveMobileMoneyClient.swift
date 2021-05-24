//
//  RaveMobileMoney.swift
//  GetBarter
//
//  Created by Olusegun Solaja on 14/08/2018.
//  Copyright © 2018 Olusegun Solaja. All rights reserved.
//

import Foundation
import UIKit

public enum MobileMoneyType {
    case ghana
    case uganda
    case rwanda
    case zambia
    case franco
}

public class RaveMobileMoneyClient: GetFee {
    public var amount: String?
    public var phoneNumber: String?
    public var email: String? = ""
    public var voucher: String?
    public var network: String?
    public var selectedMobileNetwork: String?

    // MARK: Typealias
    public typealias FeeSuccessHandler = ((String?, String?) -> Void)
    public typealias PendingHandler = ((String?, String?) -> Void)
    public typealias ErrorHandler = ((String?, [String: Any]?) -> Void)
    public typealias SuccessHandler = ((String?, [String: Any]?) -> Void)
    public typealias WebAuthHandler = ((String, String) -> Void)

    // MARK: Handler
	public var errorHandler: ErrorHandler?
	public var feeSuccessHandler: FeeSuccessHandler?
	public var chargeSuccessHandler: SuccessHandler?
	public var chargePendingHandler: PendingHandler?
	public var chargeWebAuthHandler: WebAuthHandler?

    public var transactionReference: String?
	public var mobileMoneyType: MobileMoneyType = .ghana

	public init() {}

    // MARK: Get transaction Fee
    public func getFee() {
        if RaveConfig.sharedConfig().currencyCode == .GHS || RaveConfig.sharedConfig().currencyCode == .UGX
            || RaveConfig.sharedConfig().currencyCode == .RWF || RaveConfig.sharedConfig().currencyCode == .XAF
            || RaveConfig.sharedConfig().currencyCode == .XOF || RaveConfig.sharedConfig().currencyCode == .ZMW {
            guard let pubkey = RaveConfig.sharedConfig().publicKey else {
                self.errorHandler?("Public Key is not specified", nil)
                return
            }

            let param = [
                "PBFPubKey": pubkey,
                "amount": amount!,
                "currency": RaveConfig.sharedConfig().currencyCode.rawValue,
                "ptype": "2"]

            getFee(param: param, feeSuccessHandler: feeSuccessHandler, errorHandler: errorHandler)
        }
    }

    // MARK: Charge
    public func chargeMobileMoney(_ type: MobileMoneyType = .ghana) {
        var country: String = ""
        switch RaveConfig.sharedConfig().currencyCode {
                   case .KES, .TZS, .GHS, .ZAR:
                       country = RaveConfig.sharedConfig().country
                   default:
                       country = "NG"
                   }
        if let pubkey = RaveConfig.sharedConfig().publicKey {
            var param: [String: Any] = [
                "PBFPubKey": pubkey,
                "amount": amount!,
                "email": email!,
                "phonenumber": phoneNumber ?? "",
                "currency": RaveConfig.sharedConfig().currencyCode,
                "firstname": RaveConfig.sharedConfig().firstName ?? "",
                "lastname": RaveConfig.sharedConfig().lastName ?? "",
                "country": country,
                "meta": "",
                "IP": getIFAddresses().first!,
                "txRef": transactionReference!,
                "orderRef": transactionReference!,
                "device_fingerprint": (UIDevice.current.identifierForVendor?.uuidString)!
            ]
            switch type {
            case .ghana :
                param.merge(["network": network ?? "", "is_mobile_money_gh": "1", "payment_type": "mobilemoneygh"])
            case .uganda :
                param.merge(["network": CurrencyCode.UGX.rawValue, "is_mobile_money_ug": "1", "payment_type": "mobilemoneyuganda"])
            case .rwanda :
                param.merge(["network": CurrencyCode.RWF.rawValue, "is_mobile_money_gh": "1", "payment_type": "mobilemoneygh"])
            case .zambia:
                param.merge(["network": network ?? "", "is_mobile_money_ug": "1", "payment_type": "mobilemoneyzambia"])
            case .franco:
                param.merge(["is_mobile_money_franco": "1", "payment_type": "mobilemoneyfranco"])
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

            if let _voucher = self.voucher, _voucher != ""{
                param.merge(["voucher": _voucher])
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
            RavePayService.charge(reqbody, resultCallback: { (res) in
                if let status = res?["status"] as? String {
					if status == "success"{
						let result = res?["data"] as? [String: AnyObject]
						if let code = result?["code"] as? String, code == "02"{
							if let authURL = result?["link"] as? String {
								self.chargeWebAuthHandler?("", authURL)
							}
						} else {
							let flwTransactionRef = result?["flwRef"] as? String
							if let chargeResponse = result?["chargeResponseCode"] as? String {
								switch chargeResponse {
								case "00":
									self.chargeSuccessHandler?(flwTransactionRef!, res)

								case "02":
									if let authURL = result?["authurl"] as? String, authURL != "NO-URL", authURL != "N/A" {
										// Show Web View
										self.chargeWebAuthHandler?(flwTransactionRef!, authURL)
										if let txRef = result?["flwRef"] as? String {
											self.queryMpesaTransaction(txRef: txRef)
										}

									} else {

										if let type =  result?["paymentType"] as? String, let currency = result?["currency"] as? String {
											print(type)
                                            if type.containsIgnoringCase(find: "mpesa") || type.containsIgnoringCase(find: "mobilemoneygh") || type.containsIgnoringCase(find: "mobilemoneyzm") ||  currency.containsIgnoringCase(find: CurrencyCode.UGX.rawValue) {
												if let status =  result?["status"] as? String {
													if status.containsIgnoringCase(find: "pending") {

														self.chargePendingHandler?("Transaction Processing", "A push notification has been sent to your phone, please complete the transaction by entering your pin.\n Please do not close this page until transaction is completed")
														if let txRef = result?["flwRef"] as? String {
															self.queryMpesaTransaction(txRef: txRef)
														}

													}
												}
											}
										}
									}

								default:
									break
								}
							}
						}
                    } else {
                        if let message = res?["message"] as? String {
                            print(message)
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
            print(param)
            RavePayService.mpesaQueryTransaction(param, resultCallback: { (result) in
                if let  status = result?["status"] as? String, let message = result?["message"]  as? String {
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
                        self.errorHandler?(message, nil)
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
