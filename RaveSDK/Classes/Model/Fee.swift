//
//  Fee.swift
//  RaveMobile
//
//  Created by Ahmed Hamdy on 24/05/2021.
//  Copyright © 2021 Ahmed Hamdy. All rights reserved.
//

import Foundation

struct Fee: Codable {

	let chargeAmount: String?
	let fee: Float?
	let merchantFee: String?
	let raveFee: String?

	enum CodingKeys: String, CodingKey {
		case chargeAmount = "charge_amount"
		case fee
		case merchantFee = "merchantfee"
		case raveFee = "ravefee"
	}

	init(from decoder: Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)
		chargeAmount = try values.decodeIfPresent(String.self, forKey: .chargeAmount)
		fee = try values.decodeIfPresent(Float.self, forKey: .fee)
		merchantFee = try values.decodeIfPresent(String.self, forKey: .merchantFee)
		raveFee = try values.decodeIfPresent(String.self, forKey: .raveFee)
	}
}
