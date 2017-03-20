//
//  LogDetailTableViewController.swift
//  CleverCalorie
//
//  Created by Wilson Ding on 10/30/16.
//  Copyright © 2016 Wilson Ding. All rights reserved.
//

import UIKit

class LogDetailTableViewController: UITableViewController {

    var currentIndex: Int!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Total Calories: \(getSum(index:currentIndex))"
        // Do any additional setup after loading the view.
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func viewDidAppear(_ animated: Bool) {
        print(FoodStorageService.sharedInstance.database.count)
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        // #warning Incomplete implementation, return the number of sections
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // #warning Incomplete implementation, return the number of rows
        return FoodStorageService.sharedInstance.database[currentIndex].count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        
        cell.textLabel?.text = FoodStorageService.sharedInstance.database[currentIndex][indexPath.row].get_name().capitalizingFirstLetter()
        
        cell.detailTextLabel?.text = "\(FoodStorageService.sharedInstance.database[currentIndex][indexPath.row].get_calories()) calories (\(FoodStorageService.sharedInstance.database[currentIndex][indexPath.row].get_total_fat()) calories from \(FoodStorageService.sharedInstance.database[currentIndex][indexPath.row].get_calories_fat())g of fat.)"
        
        return cell
    }
    
    func getSum(index: Int) -> Double {
        var sum : Double = 0.00
        for i in 0...FoodStorageService.sharedInstance.database[currentIndex].count - 1 {
            sum = sum + FoodStorageService.sharedInstance.database[index][i].get_calories()
        }
        print(sum)
        return sum
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
