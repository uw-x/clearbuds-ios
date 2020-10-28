//
//  ViewController.swift
//  shio-dc
//
//  Created by Maruchi Kim on 10/26/20.
//  https://www.swiftdevcenter.com/upload-image-video-audio-and-any-type-of-files-to-aws-s3-bucket-swift/

import UIKit
import CoreBluetooth

class ViewController: UIViewController, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var s3UrlLabel: UILabel!
    @IBOutlet weak var progressView: UIProgressView!
    
    let testFilePath = Bundle.main.path(forResource: "Two Dumbs Up - uncoolclub", ofType: "mp3")
    var centralManager: CBCentralManager!
    var myPeripheral: CBPeripheral!
    var peripherals: [UUID: CBPeripheral] = [:]
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    private func updateView() {
        let peripheralsDiscovered = peripherals.count > 0
        if peripheralsDiscovered {
            tableView.reloadData()
        }
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if (central.state == CBManagerState.poweredOn) {
            print("BLE powered on")
            // Turned on
            central.scanForPeripherals(withServices: nil, options: nil)
        } else {
            print("Something wrong with BLE")
            // Not on, but can have different issues
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if let pname = peripheral.name {
            if (pname == "shio") {
                print("Discovered a shio")
                peripherals.updateValue(peripheral, forKey: peripheral.identifier)
                self.updateView()
            }
        }
    }
    

    @IBAction func tapUploadAudio(_ sender: Any) {
        let audioUrl = URL(fileURLWithPath: testFilePath!)
            AWSS3Manager.shared.uploadAudio(audioUrl: audioUrl, progress: { [weak self] (progress) in
                
                guard let strongSelf = self else { return }
                strongSelf.progressView.progress = Float(progress)
                
            }) { [weak self] (uploadedFileUrl, error) in
                
                guard let strongSelf = self else { return }
                if let finalPath = uploadedFileUrl as? String {
                    strongSelf.s3UrlLabel.text = "Uploaded file url: " + finalPath
                } else {
                    print("\(String(describing: error?.localizedDescription))")
                }
            }
    }
    
}

extension ViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return peripherals.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        // Dequeue Reusable Cell
        let cell = tableView.dequeueReusableCell(withIdentifier: PeripheralTableViewCell.ReuseIdentifier, for: indexPath) as! PeripheralTableViewCell

        // Fetch Day
        let index = indexPath.row
        let peripheral = Array(peripherals)[index].value

        // Configure Cell
        cell.peripheralLabel.text = peripheral.name

        return cell
    }

}
