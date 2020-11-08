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
import Charts

// MARK: Definitions
let shioServiceUUID = CBUUID(string: "47ea1400-a0e4-554e-5282-0afcd3246970")
let micDataCharUUID = CBUUID(string: "47ea1402-a0e4-554e-5282-0afcd3246970")
let controlCharUUID = CBUUID(string: "47ea1403-a0e4-554e-5282-0afcd3246970")

let timeSyncMasterValue: UInt8 = 0x6D
let audioStreamStartValue: UInt8 = 0xA5
let timeSyncEnabled = true

class ViewController: UIViewController, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    
    @IBOutlet weak var appNameLabel: UILabel!
    @IBOutlet weak var progressView: UIProgressView!
    @IBOutlet weak var recordButton: UIButton!
    @IBOutlet weak var shioLImageView: UIImageView!
    @IBOutlet weak var shioRImageView: UIImageView!
    @IBOutlet weak var shioLSearchingIndicatorView: UIActivityIndicatorView!
    @IBOutlet weak var shioRSearchingIndicatorView: UIActivityIndicatorView!
    @IBOutlet weak var shioLButton: UIButton!
    @IBOutlet weak var shioRButton: UIButton!
    
    @IBOutlet weak var shioPriGraph: LineChartView!
    @IBOutlet weak var shioSecGraph: LineChartView!
    
    let testFilePath = Bundle.main.path(forResource: "Two Dumbs Up - uncoolclub", ofType: "mp3")
    var connectionIntervalUpdated = 0
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
        shioLImageView.isHidden = true
        shioRImageView.isHidden = true
        shioLSearchingIndicatorView.startAnimating()
        shioRSearchingIndicatorView.startAnimating()
        progressView.isHidden = true
    }
    
    private func updateView() {
        let peripheralsDiscovered = peripherals.count > 0
        if peripheralsDiscovered {
            if peripherals.count == 1 {
                shioLSearchingIndicatorView.stopAnimating()
                shioLSearchingIndicatorView.isHidden = true
                shioLImageView.isHidden = false
            } else if (peripherals.count == 2) {
                shioRSearchingIndicatorView.stopAnimating()
                shioRSearchingIndicatorView.isHidden = true
                shioRImageView.isHidden = false
            }
        }
    }
    
    private func updateViewDeviceBackground(peripheral: CBPeripheral, connected: Bool)
    {
        let color = connected ? UIColor(red: 84.0/255.0, green: 90.0/255.0, blue: 97.0/255.0, alpha: 1.0) : UIColor(red: 242.0/255.0, green: 242.0/255.0, blue: 247/255.0, alpha: 1.0)
        if (peripheral.identifier == self.shioPri.identifier) {
            shioLButton.backgroundColor = color
            shioLSearchingIndicatorView.stopAnimating()
            shioLSearchingIndicatorView.isHidden = true
            shioLImageView.isHidden = false
        } else if (peripheral.identifier == self.shioSec.identifier) {
            shioRButton.backgroundColor = color
            shioRSearchingIndicatorView.stopAnimating()
            shioRSearchingIndicatorView.isHidden = true
            shioRImageView.isHidden = false
        }
    }
    
    private func pdmStart()
    {
        print("PDM start")
        let value: UInt8 = audioStreamStartValue
        let data = Data(_:[value])
        
        if (shioPri.state == CBPeripheralState.connected) {
            shioPri.writeValue(data, for: shioPriControlCharacteristic, type: CBCharacteristicWriteType.withoutResponse)
        } else {
            print("ERROR shioPri not connected")
        }
        
        if (shioSec.state == CBPeripheralState.connected) {
            shioSec.writeValue(data, for: shioSecControlCharacteristic, type: CBCharacteristicWriteType.withoutResponse)
        } else {
            print("ERROR shioSec not connected")
        }
        
        recordButton.backgroundColor = (UIColor(red: 247.0/255.0, green: 86.0/255.0, blue: 0x63/255.0, alpha: 1.0))
        recordButton.setTitleColor(UIColor.white, for: .normal)
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
                
                peripherals.updateValue(peripheral, forKey: peripheral.identifier)
                self.updateView()
                
                if (peripherals.count == 1) {
                    print("Discovered first shio")
                    self.shioPri = peripheral
                    self.shioPri.delegate = self
                    self.centralManager.connect(self.shioPri, options: nil)
                }
                
                // Two shios discovered, connect to second and stop scanning
                if (peripherals.count == 2) {
                    print("Discovered second shio")
                    self.centralManager.stopScan()
                    
                    self.shioSec = peripheral
                    self.shioSec.delegate = self
                    self.centralManager.connect(self.shioSec, options: nil)
                }
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices(nil)
        updateViewDeviceBackground(peripheral: peripheral, connected: true)
        if (peripheral.identifier == self.shioPri.identifier) {
            print("Connected shioPri \(peripheral.identifier)")
        } else if (peripheral.identifier == self.shioSec.identifier) {
            print("Connected shioSec \(peripheral.identifier)")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        updateViewDeviceBackground(peripheral: peripheral, connected: false)
        connectionIntervalUpdated = (connectionIntervalUpdated > 0) ? (connectionIntervalUpdated - 1) : 0
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
                    
                    shioPri.setNotifyValue(true, for: shioPriControlCharacteristic)
                } else if (characteristic.uuid == micDataCharUUID) {
                    shioPriMicDataCharacteristic = characteristic
                }
            } else if (thisShio == "shioSec") {
                if (characteristic.uuid == controlCharUUID) {
                    shioSecControlCharacteristic = characteristic
                    shioSec.setNotifyValue(true, for: shioSecControlCharacteristic)
                } else if (characteristic.uuid == micDataCharUUID) {
                    shioSecMicDataCharacteristic = characteristic
                }
            }
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
        let packetLength = Int(value.count)     // Get the length of the packet
        
        if (characteristic.uuid == micDataCharUUID) {
            assert(packetLength % 2 == 0) // We assume 16 bit integer, can't have half a data packet
            let newPacketLength = Int(packetLength / 2)

            // Convert the Byte Buffer to an Int 16 Buffer
            value.withUnsafeBytes{ (bufferRawBufferPointer) -> Void in
                let bufferPointerInt16 = UnsafeBufferPointer<Int16>.init(start: bufferRawBufferPointer.baseAddress!.bindMemory(to: Int16.self, capacity: 1), count: newPacketLength)

                // Do something with data
                if (peripheral.identifier == self.shioPri.identifier) {
                    for i in 0...newPacketLength - 1 {
                        shioPriAudioBuffer.append(bufferPointerInt16[i])
                    }

                } else if (peripheral.identifier == self.shioSec.identifier) {
                    for i in 0...newPacketLength - 1 {
                        shioSecAudioBuffer.append(bufferPointerInt16[i])
                    }
                }
            }            
            updateCharts()

        } else if (characteristic.uuid == controlCharUUID) {
            let dataPointer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
            value.copyBytes(to: dataPointer, count: 1)
            
            if (dataPointer[0] == 0xFF) {
                connectionIntervalUpdated += 1
                print("Control interval updated")
                
                if (connectionIntervalUpdated == 2) {
                    pdmStart()
                }
            }
        }
    }
    
    func updateCharts() {
        // Should probably check for a memory error here
        var valuesPri: [ChartDataEntry] = []
        var valuesSec: [ChartDataEntry] = []
        
        if (shioPriAudioBuffer.count > 100) {
            for i in (shioPriAudioBuffer.count - 100 ..< shioPriAudioBuffer.count) {
                valuesPri.append(ChartDataEntry(x: Double(i - shioPriAudioBuffer.count + 100), y: Double(shioPriAudioBuffer[i])))
            }
        }

        if (shioSecAudioBuffer.count > 100) {
            for i in (shioSecAudioBuffer.count - 100 ..< shioSecAudioBuffer.count) {
                valuesSec.append(ChartDataEntry(x: Double(i - shioSecAudioBuffer.count + 100), y: Double(shioSecAudioBuffer[i])))
            }
        }
        
        let setPri = LineChartDataSet(entries: valuesPri, label: "Mic 1 Waveform")
        setPri.drawCirclesEnabled = false
        let dataPri = LineChartData(dataSet: setPri)
        shioPriGraph.data = dataPri
        shioPriGraph.leftAxis.axisMinimum = -32768
        shioPriGraph.leftAxis.axisMaximum = 32768
        shioPriGraph.rightAxis.axisMinimum = -32768
        shioPriGraph.rightAxis.axisMaximum = 32768
        
        shioPriGraph.rightAxis.enabled = false
        shioPriGraph.leftAxis.enabled = false
        shioPriGraph.xAxis.enabled = false
        shioPriGraph.leftAxis.drawLabelsEnabled = false
        shioPriGraph.rightAxis.drawLabelsEnabled = false
        shioPriGraph.xAxis.drawGridLinesEnabled = false
        shioPriGraph.xAxis.drawAxisLineEnabled = false
        shioPriGraph.leftAxis.drawAxisLineEnabled = false
        shioPriGraph.rightAxis.drawAxisLineEnabled = false
        shioPriGraph.drawBordersEnabled = false
            
        let setSec = LineChartDataSet(entries: valuesSec, label: "Mic 2 Waveform")
        setSec.drawCirclesEnabled = false
        let dataSec = LineChartData(dataSet: setSec)
        shioSecGraph.data = dataSec
        shioSecGraph.leftAxis.axisMinimum = -32768
        shioSecGraph.leftAxis.axisMaximum = 32768
        shioSecGraph.rightAxis.axisMinimum = -32768
        shioSecGraph.rightAxis.axisMaximum = 32768
        
        shioSecGraph.rightAxis.enabled = false
        shioSecGraph.leftAxis.enabled = false
        shioSecGraph.xAxis.enabled = false
        shioSecGraph.leftAxis.drawLabelsEnabled = false
        shioSecGraph.rightAxis.drawLabelsEnabled = false
        shioSecGraph.xAxis.drawGridLinesEnabled = false
        shioSecGraph.xAxis.drawAxisLineEnabled = false
        shioSecGraph.leftAxis.drawAxisLineEnabled = false
        shioSecGraph.rightAxis.drawAxisLineEnabled = false
        shioSecGraph.drawBordersEnabled = false
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
        } else if (recordingState == RecordingState.done) {
            let (baseStringPri, baseStringSec) = createWavFile(audioBufferPri: shioPriAudioBuffer, audioBufferSec: shioSecAudioBuffer)
            uploadAudio(baseString: baseStringPri)
            uploadAudio(baseString: baseStringSec)
        }
    }
    
    func uploadAudio(baseString: String) {
        let directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioURL = URL(fileURLWithPath: baseString, relativeTo: directoryURL).appendingPathExtension("wav")
        AWSS3Manager.shared.uploadAudio(audioUrl: audioURL, uploadName: baseString + ".wav", progress: { [weak self] (progress) in
            guard let strongSelf = self else { return }
            strongSelf.progressView.progress = Float(progress)
            
            strongSelf.recordButton.setTitle(String(Int(100*progress)) + "%", for:.normal)
        }) { [weak self] (uploadedFileUrl, error) in
            guard let strongSelf = self else { return }
            if let finalPath = uploadedFileUrl as? String {
                strongSelf.recordingState = RecordingState.waiting
                strongSelf.recordButton.setTitle("INITIALIZING", for: .normal)
                strongSelf.recordButton.backgroundColor = UIColor(red: 242.0/255.0, green: 242.0/255.0, blue: 247/255.0, alpha: 1.0)
                
                let alert = UIAlertController(title: "Upload Successful", message: "Thank you for taking the time to submit a voice recording for our project. Feel free to reach out to us if you have any questions!", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Dismiss", style: .default, handler: nil))
                strongSelf.present(alert, animated: true)
                
            } else {
                print("\(String(describing: error?.localizedDescription))")
            }
        }
    }
    
    @IBAction func tapShioLButton(_ sender: Any) {
        print("Tap shioLButton")
        if (shioPri.state == CBPeripheralState.connected) {
            centralManager.cancelPeripheralConnection(shioPri)
        } else {
            shioLSearchingIndicatorView.startAnimating()
            shioLImageView.isHidden = true
            shioLSearchingIndicatorView.isHidden = false
            self.centralManager.connect(self.shioPri, options: nil)
        }
        
    }
    
    @IBAction func tapShioRButton(_ sender: Any) {
        print("Tap shioRButton")
        if (shioSec.state == CBPeripheralState.connected) {
            centralManager.cancelPeripheralConnection(shioSec)
        } else {
            shioRSearchingIndicatorView.startAnimating()
            shioRImageView.isHidden = true
            shioRSearchingIndicatorView.isHidden = false
            self.centralManager.connect(self.shioSec, options: nil)
        }
    }
}

extension UILabel {

    @IBInspectable var kerning: Float {
        get {
            var range = NSMakeRange(0, (text ?? "").count)
            guard let kern = attributedText?.attribute(NSAttributedString.Key.kern, at: 0, effectiveRange: &range),
                let value = kern as? NSNumber
                else {
                    return 0
            }
            return value.floatValue
        }
        set {
            var attText:NSMutableAttributedString

            if let attributedText = attributedText {
                attText = NSMutableAttributedString(attributedString: attributedText)
            } else if let text = text {
                attText = NSMutableAttributedString(string: text)
            } else {
                attText = NSMutableAttributedString(string: "")
            }

            let range = NSMakeRange(0, attText.length)
            attText.addAttribute(NSAttributedString.Key.kern, value: NSNumber(value: newValue), range: range)
            self.attributedText = attText
        }
    }
}
