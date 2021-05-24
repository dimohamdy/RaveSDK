//
//  FWResult.swift
//  RaveMobile
//
//  Created by Ahmed Hamdy on 24/05/2021.
//  Copyright © 2021 Ahmed Hamdy. All rights reserved.
//

import Foundation

struct FWResult<T: Codable>: Codable {
	let data: T?
	let message: String?
	let status: String?

	enum CodingKeys: String, CodingKey {
		case data
		case message
		case status
	}

	init(from decoder: Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)
        data =  try? values.decodeIfPresent(T.self, forKey: .data)
		message = try values.decodeIfPresent(String.self, forKey: .message)
		status = try values.decodeIfPresent(String.self, forKey: .status)
	}
}
