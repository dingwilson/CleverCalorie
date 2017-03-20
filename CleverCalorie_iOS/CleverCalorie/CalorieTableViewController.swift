//
//  CalorieTableViewController.swift
//  CleverCalorie
//
//  Created by Wilson Ding on 10/30/16.
//  Copyright © 2016 Wilson Ding. All rights reserved.
//

import UIKit
import FirebaseDatabase
import Alamofire
import SwiftyJSON

class CalorieTableViewController: UITableViewController {
    
    var ingredients: [String] = FoodStorageService.sharedInstance.ingredients
    
    let base_url:String = "http://ec2-35-162-80-33.us-west-2.compute.amazonaws.com/search/"
    
    var ref: FIRDatabaseReference!
    
    var key : String = ""
    
    var uuid: String!
    
    var totalCal: Double!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Do any additional setup after loading the view.
        
        uuid = UIDevice.current.identifierForVendor!.uuidString
        
        ref = FIRDatabase.database().reference()
        
        key = ref.childByAutoId().key
        
        writeToFB()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        totalCal = 0
        
        self.tableView.reloadData()
        

    }
    
    override func viewWillDisappear(_ animated: Bool) {
        if (FoodStorageService.sharedInstance.storage.count > 0){
            FoodStorageService.sharedInstance.database.append(FoodStorageService.sharedInstance.storage)
            FoodStorageService.sharedInstance.storage.removeAll()
        }
        FoodStorageService.sharedInstance.ingredients.removeAll()
        navigationController?.popToRootViewController(animated: true)
    }
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func writeToFB() {
        //Create an object to store all the ingredients and a date item
        
        //Add date item
        
        //        let ingredients = get_food_data(query: "apple,avocado")
        //        print(ingredients.count)
        //        print(return_data[0].get_calories())
        
        
        for item in ingredients {
            print(item)
            get_food_data(query: item)
            self.tableView.reloadData()
            //Create the object to put into the setValue function
        }
        
    }
    
    func getSum() {
        var sum : Double = 0.00
        if (FoodStorageService.sharedInstance.storage.count > 0) {
            for i in 0...FoodStorageService.sharedInstance.storage.count - 1 {
                sum = sum + FoodStorageService.sharedInstance.storage[i].get_calories()
            }
        }
        self.title = "Total Calories: \(sum)"
    }
    
    func get_food_data(query: String) {
        let url = base_url + query
        if (ingredients.count > FoodStorageService.sharedInstance.storage.count) {
            Alamofire.request(url).responseJSON { response in
                switch response.result {
                case .success(let value):
                    let json = JSON(value)
                    let name: String = json["name"].stringValue
                    let calories: Double = json["calories"].doubleValue
                    let calories_fat: Double = json["calories_fat"].doubleValue
                    let total_fat: Double = json["total_fat"].doubleValue
                    
                    self.ref.child(self.uuid).child(self.key).child(name).child("calories").setValue(calories)
                    self.ref.child(self.uuid).child(self.key).child(name).child("calories_fat").setValue(calories_fat)
                    self.ref.child(self.uuid).child(self.key).child(name).child("total_fat").setValue(total_fat)
                    
                    let stringFromDate = Date().iso8601    // "2016-06-18T05:18:27.935Z"
                    
                    if let dateFromString = stringFromDate.dateFromISO8601 {
                        self.ref.child(self.uuid).child(self.key).child("time_stamp").setValue(dateFromString.iso8601)
                        let temp_food : FoodItem = FoodItem(calories: calories, calories_fat: calories_fat, name: name, total_fat: total_fat, time: dateFromString.iso8601)
                        FoodStorageService.sharedInstance.storage.append(temp_food)
                    }
                    
                    if (self.ingredients.count == FoodStorageService.sharedInstance.storage.count) {
                        self.getSum()
                        self.tableView.reloadData()
                    }
                    
                    
                case .failure(let error):
                    print(error)
                }
            }

        }
        
    }
    
    // MARK: - Table view data source
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        // #warning Incomplete implementation, return the number of sections
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // #warning Incomplete implementation, return the number of rows
        return FoodStorageService.sharedInstance.storage.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        
        cell.textLabel?.text = FoodStorageService.sharedInstance.storage[indexPath.row].get_name().capitalizingFirstLetter()
        
        totalCal = totalCal + FoodStorageService.sharedInstance.storage[indexPath.row].get_calories()
        
        cell.detailTextLabel?.text = "\(FoodStorageService.sharedInstance.storage[indexPath.row].get_calories()) calories (\(FoodStorageService.sharedInstance.storage[indexPath.row].get_total_fat()) calories from \(FoodStorageService.sharedInstance.storage[indexPath.row].get_calories_fat())g of fat.)"
        
        return cell
    }
    
    /*
     // MARK: - Navigation
     
     // In a storyboard-based application, you will often want to do a little preparation before navigation
     override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
     // Get the new view controller using segue.destinationViewController.
     // Pass the selected object to the new view controller.
     }
     */
    
}

extension Date {
    struct Formatter {
        static let iso8601: DateFormatter = {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .iso8601)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MM-dd' 'HH:mm:ss"
            return formatter
        }()
    }
    var iso8601: String {
        return Formatter.iso8601.string(from: self)
    }
}


extension String {
    var dateFromISO8601: Date? {
        return Date.Formatter.iso8601.date(from: self)
    }
}
