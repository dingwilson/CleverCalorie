//
//  foodItem.swift
//  CleverCalorie
//
//  Created by Kevin J Nguyen on 10/29/16.
//  Copyright © 2016 Kevin J Nguyen. All rights reserved.
//

class FoodItem {
    var calories : Double = 0.00
    var calories_fat : Double = 0.00
    var name : String = ""
    var total_fat : Double = 0.00
    var time : String = ""
    
    init (calories: Double, calories_fat: Double, name: String, total_fat: Double, time : String) {
        self.calories = calories
        self.calories_fat = calories_fat
        self.name = name
        self.total_fat = total_fat
        self.time = time
    }
    
    func get_calories () -> Double {
        return calories
    }
    
    func get_calories_fat () -> Double {
        return calories_fat
    }
    
    func get_name () -> String {
        return name
    }
    
    func get_total_fat () -> Double {
        return total_fat
    }
    
    func get_time () -> String {
        return time
    }
}
