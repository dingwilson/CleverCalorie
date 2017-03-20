//
//  FoodStorageService.swift
//  CleverCalorie
//
//  Created by Kevin J Nguyen on 10/30/16.
//  Copyright © 2016 Wilson Ding. All rights reserved.
//

class FoodStorageService {
    
    var storage = [FoodItem]()
    
    var ingredients = [String]()
    
    var database = [[FoodItem]]()
    
    static let sharedInstance = FoodStorageService()
    //Other methods of the class....
}
