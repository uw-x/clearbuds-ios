//
//  ViewController.swift
//  shio-dc
//
//  Created by Maruchi Kim on 10/26/20.
//  https://www.swiftdevcenter.com/upload-image-video-audio-and-any-type-of-files-to-aws-s3-bucket-swift/
//  https://punchthrough.com/core-bluetooth-basics/

import UIKit
import CoreBluetooth
import AVFoundation
import AVKit

// MARK: Definitions
let shioServiceUUID = CBUUID(string: "47ea1400-a0e4-554e-5282-0afcd3246970")
let micDataCharUUID = CBUUID(string: "47ea1402-a0e4-554e-5282-0afcd3246970")
let controlCharUUID = CBUUID(string: "47ea1403-a0e4-554e-5282-0afcd3246970")

let timeSyncMasterValue: UInt8 = 0x6D
let audioStreamStartValue: UInt8 = 0xA5
let timeSyncEnabled = false

class ViewController: UIViewController, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var s3UrlLabel: UILabel!
    @IBOutlet weak var progressView: UIProgressView!
    @IBOutlet weak var recordButton: UIButton!
    
    let testFilePath = Bundle.main.path(forResource: "Two Dumbs Up - uncoolclub", ofType: "mp3")
    var characteristicsDiscovered = 0
    var centralManager: CBCentralManager!
    var shioPri: CBPeripheral!
    var shioPriMicDataCharacteristic: CBCharacteristic!
    var shioPriControlCharacteristic: CBCharacteristic!
    var shioSec: CBPeripheral!
    var shioSecMicDataCharacteristic: CBCharacteristic!
    var shioSecControlCharacteristic: CBCharacteristic!
    var peripherals: [UUID: CBPeripheral] = [:]
    
    // Actual audio buffers
    var shioPriAudioBuffer : [Int16] = []
    var shioSecAudioBuffer : [Int16] = []
    
    enum RecordingState: Int {
        case waiting = 0
        case ready = 1
        case recording = 2
        case done = 3
    }
    
    var recordingState = RecordingState.waiting
    
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
        
        recordingState = RecordingState.ready
        recordButton.setTitle("START STREAM", for: .normal)
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
                    if (timeSyncEnabled) {
                        let value: UInt8 = timeSyncMasterValue
                        let data = Data(_:[value])
                        peripheral.writeValue(data, for: characteristic, type: CBCharacteristicWriteType.withoutResponse)
                    }
                } else if (characteristic.uuid == micDataCharUUID) {
                    shioPriMicDataCharacteristic = characteristic
                }
            } else if (thisShio == "shioSec") {
                if (characteristic.uuid == controlCharUUID) {
                    shioSecControlCharacteristic = characteristic
                } else if (characteristic.uuid == micDataCharUUID) {
                    shioSecMicDataCharacteristic = characteristic
                }
            }
        }
        
        // Once we've discovered characteristics for both shios, set a 1s callback to start the PDM stream
        if (characteristicsDiscovered == 2) {
            _ = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(pdmStartTimerCallback), userInfo: nil, repeats: false)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if (peripheral.identifier == self.shioPri.identifier) {
            print("shioPri mic streaming \(peripheral.identifier)")
        } else if (peripheral.identifier == self.shioSec.identifier) {
            print("shioSec mic streaming \(peripheral.identifier)")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let value = characteristic.value else { return }

        // Get the length of the packer
        let packetLength = Int(value.count)
        assert(packetLength % 2 == 0) // We assume 16 bit integer, can't have half a data packet
        let newPacketLength = Int(packetLength / 2)

        // Convert the Byte Buffer to an Int 16 Buffer
        value.withUnsafeBytes{ (bufferRawBufferPointer) -> Void in
            let bufferPointerInt16 = UnsafeBufferPointer<Int16>.init(start: bufferRawBufferPointer.baseAddress!.bindMemory(to: Int16.self, capacity: 1), count: newPacketLength)

            // Do something with data
            if (peripheral.identifier == self.shioPri.identifier) {
                for i in 0...newPacketLength - 1 {
                    shioPriAudioBuffer.append(bufferPointerInt16[i])
                    print(bufferPointerInt16[i])
                }

            } else if (peripheral.identifier == self.shioSec.identifier) {
                for i in 0...newPacketLength - 1 {
                    shioSecAudioBuffer.append(bufferPointerInt16[i])
                }
            }
        }
    }
    
    // Function to create and write the wave files locally from Raw PCM. Returns filename of left and right
    func createWavFile(audioBufferPri: [Int16], audioBufferSec: [Int16]) -> (String, String) {
        
        // Hard coded params for now
        let sample_rate =  Float64(12500.0)
        let outputFormatSettings = [
            AVFormatIDKey:kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVSampleRateKey: sample_rate,
            AVNumberOfChannelsKey: 1,
            ] as [String : Any]
        
        print("First Array Count")
        print(audioBufferPri.count)
        print("Second Array Count")
        print(audioBufferSec.count)
        
        // Use current time as the basis of the string
        // Only a problem if two people upload at exactly same second
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HH.mm.ss"
        let baseString = formatter.string(from: now)

        let bufferFormat = AVAudioFormat(settings: outputFormatSettings)
        
        // Primary Buffer
        let outputBufferPri = AVAudioPCMBuffer(pcmFormat: bufferFormat!, frameCapacity: AVAudioFrameCount(audioBufferPri.count))

        for i in 0..<audioBufferPri.count {
            outputBufferPri!.int16ChannelData!.pointee[i] = audioBufferPri[i]
        }

        outputBufferPri!.frameLength = AVAudioFrameCount( audioBufferPri.count )
        
        let directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURLPri = URL(fileURLWithPath: baseString + "_L", relativeTo: directoryURL).appendingPathExtension("wav")
        print(fileURLPri)
        
        let audioFilePri = try? AVAudioFile(forWriting: fileURLPri, settings: outputFormatSettings, commonFormat: AVAudioCommonFormat.pcmFormatInt16, interleaved: false)
        
        do{
            try audioFilePri?.write(from: outputBufferPri!)
        } catch let error as NSError {
            print("error:", error.localizedDescription)
        }
        
        // Secondary Buffer
        let outputBufferSec = AVAudioPCMBuffer(pcmFormat: bufferFormat!, frameCapacity: AVAudioFrameCount(audioBufferSec.count))

        for i in 0..<audioBufferSec.count {
            // Primary buffer
            outputBufferSec!.int16ChannelData!.pointee[i] = audioBufferSec[i]
        }

        outputBufferSec!.frameLength = AVAudioFrameCount( audioBufferSec.count )
        
        let fileURLSec = URL(fileURLWithPath: baseString + "_R", relativeTo: directoryURL).appendingPathExtension("wav")
        print(fileURLSec)
        
        let audioFileSec = try? AVAudioFile(forWriting: fileURLSec, settings: outputFormatSettings, commonFormat: AVAudioCommonFormat.pcmFormatInt16, interleaved: false)
        
        do{
            try audioFileSec?.write(from: outputBufferSec!)
        } catch let error as NSError {
            print("error:", error.localizedDescription)
        }
        
        // Return the base string only, we can re-construct the URL later
        return (baseString + "_L", baseString + "_R")
    }
    
    @IBAction func tapRecordButton(_ sender: Any) {
        // Start recording
        if (recordingState == RecordingState.ready) {
            recordingState = RecordingState.recording
            shioPri.setNotifyValue(true, for: shioPriMicDataCharacteristic)
            shioSec.setNotifyValue(true, for: shioSecMicDataCharacteristic)
            recordButton.setTitle("STOP STREAM", for: .normal)
        } else if (recordingState == RecordingState.recording) {
            recordingState = RecordingState.done
            shioPri.setNotifyValue(false, for: shioPriMicDataCharacteristic)
            shioSec.setNotifyValue(false, for: shioSecMicDataCharacteristic)
            recordButton.setTitle("UPLOAD", for: .normal)
            
            let (baseStringPri, baseStringSec) = createWavFile(audioBufferPri: shioPriAudioBuffer, audioBufferSec: shioSecAudioBuffer)
            uploadAudio(baseString: baseStringPri)
            uploadAudio(baseString: baseStringSec)
        } else if (recordingState == RecordingState.done) {
            // Move upload audio code here
        }
    }
    
    func uploadAudio(baseString: String) {
        let directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioURL = URL(fileURLWithPath: baseString, relativeTo: directoryURL).appendingPathExtension("wav")
        AWSS3Manager.shared.uploadAudio(audioUrl: audioURL, uploadName: baseString + ".wav", progress: { [weak self] (progress) in
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
    
    @IBAction func tapUploadAudio(_ sender: Any) {
        // let audioUrl = URL(fileURLWithPath: testFilePath!)
        let directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioURL = URL(fileURLWithPath: "myFile_L", relativeTo: directoryURL).appendingPathExtension("wav")
        print(audioURL)
        AWSS3Manager.shared.uploadAudio(audioUrl: audioURL, progress: { [weak self] (progress) in
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
