//
//  CameraViewController.swift
//  CleverCalorie
//
//  Created by Wilson Ding on 10/29/16.
//  Copyright © 2016 Wilson Ding. All rights reserved.
//

import UIKit
import AVFoundation
import Clarifai

class CameraViewController: UIViewController {

    @IBOutlet weak var previewView: UIView!
    
    var captureSession: AVCaptureSession?
    var stillImageOutput: AVCaptureStillImageOutput?
    var previewLayer: AVCaptureVideoPreviewLayer?
    
    let app = ClarifaiApp(appID: "XXXXXXXXXXXXXXXXXXXXXXXX", appSecret: "XXXXXXXXXXXXXXXXXXXXXXXX")
    
    @IBOutlet weak var cantFindButton: UIButton!
    var doubleRun = 0
    
    var checkTimer: Timer!
    
    @IBOutlet weak var button1: UIButton!
    @IBOutlet weak var button2: UIButton!
    @IBOutlet weak var button3: UIButton!
    
    var ingredients = [String]()
    @IBOutlet weak var ingredientsLabel: UILabel!
    
    @IBOutlet weak var forwardButton: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        navigationController?.navigationBar.barTintColor = colorWithHexString(hex: "011A46")
        
        navigationController?.navigationBar.titleTextAttributes = [NSForegroundColorAttributeName: UIColor.white]
        
        // Do any additional setup after loading the view.
        
        button1.layer.cornerRadius = 15
        button2.layer.cornerRadius = 15
        button3.layer.cornerRadius = 15
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        captureSession = AVCaptureSession()
        captureSession!.sessionPreset = AVCaptureSessionPreset640x480
        
        let backCamera = AVCaptureDevice.defaultDevice(withMediaType: AVMediaTypeVideo)
        
        var error: Error?
        var input: AVCaptureDeviceInput!
        do {
            input = try AVCaptureDeviceInput(device: backCamera)
        } catch let error1 {
            error = error1
            input = nil
        }
        
        if error == nil && captureSession!.canAddInput(input) {
            captureSession!.addInput(input)
            
            stillImageOutput = AVCaptureStillImageOutput()
            stillImageOutput!.outputSettings = [AVVideoCodecKey: AVVideoCodecJPEG]
            if captureSession!.canAddOutput(stillImageOutput) {
                captureSession!.addOutput(stillImageOutput)
                
                previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
                previewLayer!.videoGravity = AVLayerVideoGravityResizeAspect
                previewLayer!.connection?.videoOrientation = AVCaptureVideoOrientation.portrait
                previewView.layer.addSublayer(previewLayer!)
                
                captureSession!.startRunning()
                
                self.checkTimer = Timer.scheduledTimer(timeInterval: 2, target: self, selector: #selector(self.takePhoto), userInfo: nil, repeats: true)
            }
        }
        
        if (FoodStorageService.sharedInstance.ingredients.count == 0) {
            self.ingredientsLabel.text = "To Begin - Click on an Ingredient"
            self.forwardButton.isHidden = true
        } else {
            self.ingredientsLabel.text = FoodStorageService.sharedInstance.ingredients.joined(separator: ", ")
        }
        
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSession!.stopRunning()
        self.checkTimer.invalidate()
        
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        previewLayer!.frame = previewView.bounds
        if (FoodStorageService.sharedInstance.ingredients.count == 0) {
            self.ingredientsLabel.text = "To Begin - Click on an Ingredient"
            self.forwardButton.isHidden = true
        } else {
            self.ingredientsLabel.text = FoodStorageService.sharedInstance.ingredients.joined(separator: ", ")
        }
    }
    
    func analyzeImage(image: UIImage) {
        app?.getModelByName("food-items-v1.0", completion: { (model, error) in
            let clarifaiImage = ClarifaiImage(image: image)
            model?.predict(on: [clarifaiImage!], completion: {(outputs, error) in
                if error == nil {
                    let output = outputs?[0]
                    var tags = [Any]()
                    for concepts: ClarifaiConcept in (output?.concepts)! {
                        tags.append(concepts.conceptName)
                    }
                    DispatchQueue.main.async(execute: {() in
                        for word in FoodStorageService.sharedInstance.ingredients {
                            if let ix = (tags as! [String]).index(of: word) {
                                tags.remove(at: ix)
                            }
                        }
                        
                        if tags.count > 2 {
                            self.button1.setTitle((tags[0] as? String)?.capitalizingFirstLetter(), for: .normal)
                            self.button2.setTitle((tags[1] as? String)?.capitalizingFirstLetter(), for: .normal)
                            self.button3.setTitle((tags[2] as? String)?.capitalizingFirstLetter(), for: .normal)
                            
                            if (self.button1.isHidden == true) {
                                self.button1.isHidden = false
                                self.button2.isHidden = false
                                self.button3.isHidden = false
                            }
                        }
                    })
                }
            })
        })
    }

    func takePhoto() {
        if self.doubleRun < 2 {
            self.doubleRun += 1
        }
        
        else {
            self.doubleRun = 100
            self.cantFindButton.isHidden = false
            self.cantFindButton.fadeOut()
            self.cantFindButton.fadeIn()
        }
        
        if let videoConnection = stillImageOutput!.connection(withMediaType: AVMediaTypeVideo) {
            videoConnection.videoOrientation = AVCaptureVideoOrientation.portrait
            stillImageOutput?.captureStillImageAsynchronously(from: videoConnection, completionHandler: {(sampleBuffer, error) in
                if (sampleBuffer != nil) {
                    let imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(sampleBuffer)
                    let dataProvider = CGDataProvider(data: imageData as! CFData)
                    let cgImageRef = CGImage(jpegDataProviderSource: dataProvider!, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
                    
                    let image = UIImage(cgImage: cgImageRef!, scale: 1.0, orientation: UIImageOrientation.right)
                    
                    self.analyzeImage(image: image)
                }
            })
        }
    }
    
    func updateIngredientsLabel() {
        self.forwardButton.isHidden = false
        ingredientsLabel.text = FoodStorageService.sharedInstance.ingredients.joined(separator: ", ")
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    //override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
        
        //let vc = segue.destination as! CalorieTableViewController
       // vc.ingredients = self.ingredients
        
   // }
    
    @IBAction func button1Pressed(_ sender: AnyObject) {
        if !FoodStorageService.sharedInstance.ingredients.contains((self.button1.titleLabel?.text)!) {
            FoodStorageService.sharedInstance.ingredients.append((self.button1.titleLabel?.text)!)
            self.updateIngredientsLabel()
        }
    }
    
    @IBAction func button2Pressed(_ sender: AnyObject) {
        if !FoodStorageService.sharedInstance.ingredients.contains((self.button2.titleLabel?.text)!) {
            FoodStorageService.sharedInstance.ingredients.append((self.button2.titleLabel?.text)!)
            self.updateIngredientsLabel()
        }
    }
    
    @IBAction func button3Pressed(_ sender: AnyObject) {
        if !FoodStorageService.sharedInstance.ingredients.contains((self.button3.titleLabel?.text)!) {
            FoodStorageService.sharedInstance.ingredients.append((self.button3.titleLabel?.text)!)
            self.updateIngredientsLabel()
        }
    }
    
    @IBAction func forwardButtonPressed(_ sender: AnyObject) {
        self.performSegue(withIdentifier: "segueToCalorieList", sender: self)
    }
    
    
}

extension LogTableViewController {
    // Creates a UIColor from a Hex string.
    func colorWithHexString (hex:String) -> UIColor {
        var cString:String = hex.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        
        if (cString.hasPrefix("#")) {
            cString = (cString as NSString).substring(from: 1)
        }
        
        if (cString.characters.count != 6) {
            return UIColor.gray
        }
        
        let rString = (cString as NSString).substring(to: 2)
        let gString = ((cString as NSString).substring(from: 2) as NSString).substring(to: 2)
        let bString = ((cString as NSString).substring(from: 4) as NSString).substring(to: 2)
        
        var r:CUnsignedInt = 0, g:CUnsignedInt = 0, b:CUnsignedInt = 0;
        Scanner(string: rString).scanHexInt32(&r)
        Scanner(string: gString).scanHexInt32(&g)
        Scanner(string: bString).scanHexInt32(&b)
        
        
        return UIColor(red: CGFloat(r) / 255.0, green: CGFloat(g) / 255.0, blue: CGFloat(b) / 255.0, alpha: CGFloat(1))
    }
}
