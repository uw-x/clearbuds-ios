//
//  ViewController.swift
//  shio-dc
//
//  Created by Maruchi Kim on 10/26/20.
//  https://www.swiftdevcenter.com/upload-image-video-audio-and-any-type-of-files-to-aws-s3-bucket-swift/

import UIKit
import CoreBluetooth

// MARK: Definitions
let shioServiceUUID = CBUUID(string: "47ea1400-a0e4-554e-5282-0afcd3246970")
let micDataCharUUID = CBUUID(string: "47ea1402-a0e4-554e-5282-0afcd3246970")
let controlCharUUID = CBUUID(string: "47ea1403-a0e4-554e-5282-0afcd3246970")

let timeSyncMasterValue: UInt8 = 0x6D
let audioStreamStartValue: UInt8 = 0xA5

class ViewController: UIViewController, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var s3UrlLabel: UILabel!
    @IBOutlet weak var progressView: UIProgressView!
    
    let testFilePath = Bundle.main.path(forResource: "Two Dumbs Up - uncoolclub", ofType: "mp3")
    var characteristicsDiscovered = 0
    var centralManager: CBCentralManager!
    var shioPri: CBPeripheral!
    var shioPriControlCharacteristic: CBCharacteristic!
    var shioSec: CBPeripheral!
    var shioSecControlCharacteristic: CBCharacteristic!
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
    
    @objc func pdmStartTimerCallback() {
        print("PDM start callback")
        let value: UInt8 = audioStreamStartValue
        let data = Data(_:[value])
        
        shioPri.writeValue(data, for: shioPriControlCharacteristic, type: CBCharacteristicWriteType.withoutResponse)
        shioSec.writeValue(data, for: shioSecControlCharacteristic, type: CBCharacteristicWriteType.withoutResponse)
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
                
                // Two shios discovered, connect to both and stop scanning
                if (peripherals.count == 2) {
                    self.centralManager.stopScan()
                    
                    self.shioPri = Array(peripherals)[0].value
                    self.shioPri.delegate = self
                    
                    self.shioSec = Array(peripherals)[1].value
                    self.shioSec.delegate = self
                    
                    self.centralManager.connect(self.shioPri, options: nil)
                    self.centralManager.connect(self.shioSec, options: nil)
                }
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices(nil)
        if (peripheral.identifier == self.shioPri.identifier) {
            print("Connected shioPri \(peripheral.identifier)")
        } else if (peripheral.identifier == self.shioSec.identifier) {
            print("Connected shioSec \(peripheral.identifier)")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if (peripheral.identifier == self.shioPri.identifier) {
            print("Disconnected shioPri \(peripheral.identifier)")
        } else if (peripheral.identifier == self.shioSec.identifier) {
            print("Disconnected shioSec \(peripheral.identifier)")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        characteristicsDiscovered += 1
        let thisShio = (peripheral.identifier == self.shioPri.identifier) ? "shioPri" : "shioSec"
        print("\(thisShio) characteristics:")
        for characteristic in characteristics {
            print(characteristic)
            
            if (thisShio == "shioPri") {
                if (characteristic.uuid == controlCharUUID) {
                    print("Assigning shioPri as time sync master")
                    shioPriControlCharacteristic = characteristic
                    let value: UInt8 = timeSyncMasterValue
                    let data = Data(_:[value])
                    peripheral.writeValue(data, for: characteristic, type: CBCharacteristicWriteType.withoutResponse)
                }
            } else if (thisShio == "shioSec") {
                if (characteristic.uuid == controlCharUUID) {
                    shioSecControlCharacteristic = characteristic
                }
            }
        }
        
        // Once we've discovered characteristics for both shios, set a 1s callback to start the PDM stream
        if (characteristicsDiscovered == 2) {
            _ = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(pdmStartTimerCallback), userInfo: nil, repeats: false)
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

        // Fetch peripheral
        let index = indexPath.row
        let peripheral = Array(peripherals)[index].value

        // Configure Cell
        cell.peripheralLabel.text = peripheral.name

        return cell
    }

}
