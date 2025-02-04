//
//  QRCodeScannerController.swift
//  CS199 INS
//
//  Created by Abril & Aquino on 11/12/2018.
//  Copyright © 2018 Abril & Aquino. All rights reserved.
//

import UIKit
import SceneKit
import Foundation
import AVFoundation
import GRDB

class QRCodeScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    
    @IBOutlet weak var messageLabel: UILabel!
    @IBOutlet weak var captureFrame: UIImageView!
    
    var captureSession = AVCaptureSession()
    var videoPreviewLayer : AVCaptureVideoPreviewLayer?
    
    var qrCodeFrameView : UIView?
    var qrCodeFrameThreshold : CGSize?
    
    var floorPlanTexture :  UIImage!
    var currentBuilding : Building!
    var locs : [IndoorLocation] = []
    var rooms : [[IndoorLocation]] = []
    
    private let supportedCodeTypes = [AVMetadataObject.ObjectType.qr]
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Get the back-facing camera for capturing videos
        var deviceDiscoverySession : AVCaptureDevice.DiscoverySession
        
        if (AVCaptureDevice.default(AVCaptureDevice.DeviceType.builtInDualCamera, for: AVMediaType.video, position: AVCaptureDevice.Position.back) != nil) {
            deviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInDualCamera], mediaType: AVMediaType.video, position: .back)
        } else {
            deviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: AVMediaType.video, position: .back)
        }
        
        guard let captureDevice = deviceDiscoverySession.devices.first else {
            print("ERROR: No compatible camera device found.")
            return
        }
        
        do {
            // Get an instance of the AVCaptureDeviceInput class using the previous device object.
            let input = try AVCaptureDeviceInput(device: captureDevice)
            // Set the input device on the capture session.
            captureSession.addInput(input)
            
            let captureMetadataOutput = AVCaptureMetadataOutput()
            captureSession.addOutput(captureMetadataOutput)
            
            captureMetadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            captureMetadataOutput.metadataObjectTypes = supportedCodeTypes
            
        } catch {
            print(error)
            return
        }
        
        // Initialize the video preview layer and add it as a sublayer to the viewPreview view's layer.
        videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        videoPreviewLayer?.videoGravity = AVLayerVideoGravity.resizeAspectFill
        videoPreviewLayer?.frame = view.layer.bounds
        view.layer.addSublayer(videoPreviewLayer!)
        
        // Start video capture.
        // captureSession.startRunning()
        
        // Move the message label and top bar to the front
        messageLabel.layer.cornerRadius = 5
        view.bringSubviewToFront(messageLabel)
        view.bringSubviewToFront(captureFrame)
        
        // Initialize QR Code Frame to highlight the QR code
        qrCodeFrameView = UIView()
        // Initialize QR code frame size threshold for reference to enforce min. distance
        qrCodeFrameThreshold = CGSize.init(width: 100.0, height: 100.0)
        
        if let qrCodeFrameView = qrCodeFrameView {
            qrCodeFrameView.layer.borderColor = UIColor.green.cgColor
            qrCodeFrameView.layer.borderWidth = 2
            view.addSubview(qrCodeFrameView)
            view.bringSubviewToFront(qrCodeFrameView)
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        captureSession.startRunning()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        captureSession.stopRunning()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    // MARK: - Helper methods
    
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        // Check if the metadataObjects array is not nil and it contains at least one object.
        if metadataObjects.count == 0 {
            qrCodeFrameView?.frame = CGRect.zero
            messageLabel.text = "No QR Code detected."
            return
        }
        
        // Get the metadata object.
        let metadataObj = metadataObjects[0] as! AVMetadataMachineReadableCodeObject
        
        if supportedCodeTypes.contains(metadataObj.type) {
            // If the found metadata is equal to the QR code metadata (or barcode) then update the status label's text and set the bounds
            let barCodeObject = videoPreviewLayer?.transformedMetadataObject(for: metadataObj)
            qrCodeFrameView?.frame = barCodeObject!.bounds
            
            if metadataObj.stringValue != nil && sizeFitsGuide((qrCodeFrameView?.frame)!){
                let qrCodeURL = metadataObj.stringValue!
                var qrCodeMatches : Int = 0
                
                do {
                    try DB.write { db in
                        qrCodeMatches = try QRTag.filter(Column("url") == qrCodeURL).fetchCount(db)
                    }
                } catch {
                    print(error)
                }
                
                if (qrCodeMatches == 1) {
                    launchNavigator(rawURL: qrCodeURL)
                    messageLabel.text = "QR code recognized"
                } else {
                    messageLabel.text = "QR code cannot be recognized"
                }
                
            } else if metadataObj.stringValue != nil {
                messageLabel.text = "Align the QR code to the guide"
            }
        }
    }
    
    func launchNavigator(rawURL: String) {
        
        // Short circuit function if
        if presentedViewController != nil {
            return
        }
        
        // Retrieving QR code's pertinent components
        let qrCodeFragments = rawURL.components(separatedBy: "::")
        let qrCodeBuilding = qrCodeFragments[0]
        let qrCodeFloorLevel = Int(qrCodeFragments[1])!
        
        // Variables to store QR code, building and floor information
        var qrTag : QRTag?
        var building : Building?
        var floor : Floor?
        
        // Message to display on prompt
        var promptMessage : String
        
        // Retrieve building and floor from QR code metadata
        do {
            try DB.write { db in
                qrTag = try QRTag.fetchOne(db, "SELECT * FROM QRTag WHERE url = ?", arguments: [rawURL])
                building = try Building.fetchOne(db, "SELECT * FROM Building WHERE alias = ?", arguments: [qrCodeBuilding])
                floor = try Floor.fetchOne(db, "SELECT * FROM Floor WHERE bldg = ? AND level = ?", arguments: [qrCodeBuilding, qrCodeFloorLevel])
            }
        } catch {
            print(error)
        }
        // Set the prompt message
        promptMessage = Utilities.initializeSuccessMessage(floor!.level, building!.hasLGF, building!.name, building!.alias) + " Press Navigate! to start."
        //print(promptMessage)
        //promptMessage = "You are on the \(Utilities.ordinalize(floor!.level, building!.hasLGF)) Floor of \(building!.name). Press Navigate! to start navigating."
        
        let alertPrompt = UIAlertController(title: "Localization successful.", message: promptMessage, preferredStyle: .actionSheet)
        let confirmAction = UIAlertAction(title: "Navigate!", style: UIAlertAction.Style.default, handler: { (action) -> Void in
            
            // Retrieve locations and floor plans of current building
            var buildingLocs : [[IndoorLocation]] = []
            var buildingFloorPlans : [FloorPlan] = []
            var buildingCurrentFloor : Int = 0
            //
            for floorLevel in 1...building!.floors {
                var floorLocs : [IndoorLocation] = []
                do {
                    try DB.write { db in
                        let request = IndoorLocation.order(Column("level"), Column("title")).filter(Column("bldg") == qrCodeBuilding && Column("level") == floorLevel)
                        floorLocs = try request.fetchAll(db)
                    }
                } catch {
                    print(error)
                }
                
                let floorImage = UIImage(named: "\(qrCodeBuilding)/\(floorLevel)")!
                let floorPlan = FloorPlan(floorLevel, floorImage)
                
                buildingLocs.append(floorLocs)
                buildingFloorPlans.append(floorPlan)
                
                if (floorLevel == qrCodeFloorLevel) {
                    buildingCurrentFloor = floorLevel
                }
            }
            
            // Retrieving building's staircases, in case they would be needed
            var buildingStaircases : [Staircase] = []
            //
            do {
                try DB.write { db in
                    let request = Staircase.filter(Column("bldg") == qrCodeBuilding)
                    buildingStaircases = try request.fetchAll(db)
                }
            } catch {
                print(error)
            }
            
            // Set shared variables for storing information about user position and current building
            AppState.setNavSceneUserCoords(qrTag!.xcoord, qrTag!.ycoord)
            AppState.setBuilding(building!)
            AppState.setBuildingLocs(buildingLocs)
            AppState.setBuildingFloorPlans(buildingFloorPlans)
            AppState.setBuildingStaircases(buildingStaircases)
            AppState.setBuildingCurrentFloor(buildingCurrentFloor)
            
            // Set shared variable for determining if user has performed initial scan for a single navigation procedure
            AppState.switchScanner()
            
            // Enable other controllers and shift to location list
            // self.tabBarController!.tabBar.items![1].isEnabled = true
            self.tabBarController!.tabBar.items![2].isEnabled = true
            self.tabBarController!.selectedIndex = 2
        })
        let cancelAction = UIAlertAction(title: "Cancel", style: UIAlertAction.Style.cancel, handler: nil)
        
        alertPrompt.addAction(confirmAction)
        alertPrompt.addAction(cancelAction)
        
        present(alertPrompt, animated: true, completion: nil)
    }
    
    func sizeFitsGuide(_ qrCodeFrame: CGRect) -> Bool {
        let guideContainsCode = self.captureFrame.frame.contains(qrCodeFrame)
        let codeAboveThreshold = qrCodeFrame.size.width >= (qrCodeFrameThreshold?.width)! && qrCodeFrame.size.height >= (qrCodeFrameThreshold?.height)!
        return (guideContainsCode && codeAboveThreshold)
    }
    
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertToUIApplicationOpenExternalURLOptionsKeyDictionary(_ input: [String: Any]) -> [UIApplication.OpenExternalURLOptionsKey: Any] {
    return Dictionary(uniqueKeysWithValues: input.map { key, value in (UIApplication.OpenExternalURLOptionsKey(rawValue: key), value)})
}
