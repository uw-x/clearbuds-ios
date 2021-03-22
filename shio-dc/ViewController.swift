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
    @IBOutlet weak var playButtonLeft: UIButton!
    @IBOutlet weak var playButtonRight: UIButton!
    
    @IBOutlet weak var recordButton: UIButton!
    @IBOutlet weak var shioLImageView: UIImageView!
    @IBOutlet weak var shioRImageView: UIImageView!
    @IBOutlet weak var shioLSearchingIndicatorView: UIActivityIndicatorView!
    @IBOutlet weak var shioRSearchingIndicatorView: UIActivityIndicatorView!
    @IBOutlet weak var shioLButton: UIButton!
    @IBOutlet weak var shioRButton: UIButton!
    
    @IBOutlet weak var liveView: LineChartView!
    @IBOutlet weak var voiseNoiseControlPicker: UISegmentedControl!
    
    var baseStringPri: String!
    var baseStringSec: String!
    var connectionIntervalUpdated = 0
    var centralManager: CBCentralManager!
    var shioPri: CBPeripheral!
    var shioPriMicDataCharacteristic: CBCharacteristic!
    var shioPriControlCharacteristic: CBCharacteristic!
    var shioSec: CBPeripheral!
    var shioSecMicDataCharacteristic: CBCharacteristic!
    var shioSecControlCharacteristic: CBCharacteristic!
    var peripherals: [UUID: CBPeripheral] = [:]
    var player: AVPlayer!
    var shioPriMetadataReceived = false
    var shioSecMetadataReceived = false
    var shioPriPPIArmed: UInt32 = 400000
    var shioSecPPIArmed: UInt32 = 400000
    var misalignedStartCompensated = false

    // Actual audio buffers
    var shioPriAudioBuffer : [Int16] = []
    var shioSecAudioBuffer : [Int16] = []
    
    // Sequence numbers
    var expectedSequenceNumberPri = UInt16(0)
    var expectedSequenceNumberSec = UInt16(0)
    
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
        playButtonLeft.isHidden = true
        playButtonRight.isHidden = true
        initLiveView()
        print("View Loaded")
        print(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0])
    }
    
    private func initLiveView() {
        liveView.leftAxis.axisMinimum = -35000
        liveView.leftAxis.axisMaximum = 35000
        liveView.rightAxis.axisMinimum = -35000
        liveView.rightAxis.axisMaximum = 35000
        
        liveView.rightAxis.enabled = false
        liveView.leftAxis.enabled = false
        liveView.xAxis.enabled = false
        liveView.leftAxis.drawLabelsEnabled = false
        liveView.rightAxis.drawLabelsEnabled = false
        liveView.xAxis.drawGridLinesEnabled = false
        liveView.xAxis.drawAxisLineEnabled = false
        liveView.leftAxis.drawAxisLineEnabled = false
        liveView.rightAxis.drawAxisLineEnabled = false
        liveView.drawBordersEnabled = false
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
            print("Discovered " + pname)
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

            // Convert the Byte Buffer to an Int16 Buffer
            value.withUnsafeBytes{ (bufferRawBufferPointer) -> Void in
                let bufferPointerInt16 = UnsafeBufferPointer<Int16>.init(start: bufferRawBufferPointer.baseAddress!.bindMemory(to: Int16.self, capacity: 1), count: newPacketLength)
                let sequenceNumberBytes : [UInt8] = [bufferRawBufferPointer[1], bufferRawBufferPointer[0]]
                let actualSequenceNumber = sequenceNumberBytes.withUnsafeBytes{$0.load(as: UInt16.self)}
                
                // Do something with data
                if (peripheral.identifier == self.shioPri.identifier) {
                    if (shioPriMetadataReceived == false) {
                        let shioPriPPIArmedBytes : [UInt8] = [bufferRawBufferPointer[5], bufferRawBufferPointer[4], bufferRawBufferPointer[3], bufferRawBufferPointer[2]]
                        shioPriPPIArmed = shioPriPPIArmedBytes.withUnsafeBytes{$0.load(as: UInt32.self)}
                        print("shioPri PPI Armed:", shioPriPPIArmed)
                        shioPriMetadataReceived = true
                        expectedSequenceNumberPri += 1
                    } else {
                        if (expectedSequenceNumberPri == actualSequenceNumber) {
                            // Nominal behavior
                            for i in 1...(newPacketLength - 1) {
                                shioPriAudioBuffer.append(bufferPointerInt16[i])
                            }
                                                    
                            expectedSequenceNumberPri += 1
                        } else if (actualSequenceNumber > expectedSequenceNumberPri) {
                            // A packet was dropped, fill (actual-expected) worth of packets with zeros
                            var zerosAdded = 0
                            for _ in 0...(actualSequenceNumber - expectedSequenceNumberPri - 1) {
                                for _ in 1...(newPacketLength - 1) {
                                    shioPriAudioBuffer.append(0)
                                    zerosAdded += 1
                                }
                            }
                            
                            print("PRI actual", actualSequenceNumber, "expected", expectedSequenceNumberPri, "zerosAdded ", zerosAdded)
                            
                            for i in 1...(newPacketLength - 1) {
                                shioPriAudioBuffer.append(bufferPointerInt16[i])
                            }
                            
                            expectedSequenceNumberPri = actualSequenceNumber + 1
                        } else {
                            assert(true) // the expected should never be ahead of the actual
                        }
                    }
                } else if (peripheral.identifier == self.shioSec.identifier) {
                    if (shioSecMetadataReceived == false) {
                        let shioSecPPIArmedBytes : [UInt8] = [bufferRawBufferPointer[5], bufferRawBufferPointer[4], bufferRawBufferPointer[3], bufferRawBufferPointer[2]]
                        shioSecPPIArmed = shioSecPPIArmedBytes.withUnsafeBytes{$0.load(as: UInt32.self)}
                        print("shioSec PPI Armed:", shioSecPPIArmed)
                        shioSecMetadataReceived = true
                        expectedSequenceNumberSec += 1
                    } else {
                        if (expectedSequenceNumberSec == actualSequenceNumber) {
                            // Nominal behavior
                            for i in 1...(newPacketLength - 1) {
                                shioSecAudioBuffer.append(bufferPointerInt16[i])
                            }
                            
                            expectedSequenceNumberSec += 1
                        } else if (actualSequenceNumber > expectedSequenceNumberSec) {
                            // A packet was dropped, fill (actual-expected) worth of packets with zeros
                            var zerosAdded = 0
                            for _ in 0...(actualSequenceNumber - expectedSequenceNumberSec - 1) {
                                for _ in 1...(newPacketLength - 1) {
                                    shioSecAudioBuffer.append(0)
                                    zerosAdded += 1
                                }
                            }
                            
                            print("SEC actual", actualSequenceNumber, "expected", expectedSequenceNumberSec, "zerosAdded ", zerosAdded)
                            
                            for i in 1...(newPacketLength - 1) {
                                shioSecAudioBuffer.append(bufferPointerInt16[i])
                            }
                            
                            expectedSequenceNumberSec = actualSequenceNumber + 1
                        } else {
                            assert(true) // the expected should never be ahead of the actual
                        }
                    }
                }
            }
            
            // Handle scenario where one starts before the other due to being written at the egde of the clock sync
            if (shioPriMetadataReceived && shioSecMetadataReceived && !misalignedStartCompensated) {
                if (abs(Int(shioPriPPIArmed) - Int(shioSecPPIArmed)) < 200000) { // only attempt to compensate if they are within expected bounds (i.e. 300k 500k), reject 700k 20k
                    if ((shioPriPPIArmed > 400000 && shioSecPPIArmed < 400000) || (shioPriPPIArmed < 400000 && shioSecPPIArmed > 400000)) {
                        // There is a misalignment
                        let startOffsetTicks = 800000 // the second shio will wait a full cycle before starting
                        let startOffsetUs = startOffsetTicks / 16
                        let singleSampleTimeUs = (1000*1000) / 15625
                        let samplesToDrop = startOffsetUs / singleSampleTimeUs // should be 781 with 15.625khz sampling rate
                        
                        if (shioSecPPIArmed < 400000) {
                            // Secondary started earlier
                            if (shioSecAudioBuffer.count > samplesToDrop) {
                                print("Dropping ", samplesToDrop, " samples from secondary")
                                shioSecAudioBuffer.removeFirst(Int(samplesToDrop))
                                misalignedStartCompensated = true
                            }
                        } else {
                            // Primary started earlier
                            if (shioPriAudioBuffer.count > samplesToDrop) {
                                print("Dropping ", samplesToDrop, " samples from primary")
                                shioPriAudioBuffer.removeFirst(Int(samplesToDrop))
                                misalignedStartCompensated = true
                            }
                        }
                    } else {
                        // There is no misalignment
                        misalignedStartCompensated = true
                        print("No misalignment")
                    }
                } else {
                    misalignedStartCompensated = true
                    print("No misalignment")
                }
            }
            //
            
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
        var lineChartEntry1 = [ChartDataEntry]()
        var lineChartEntry2 = [ChartDataEntry]()
        let data = LineChartData()
        let offset = 1000

        let numSamples = 37500  // 3 Seconds
        let currStride = 100  // Don't show every single sample, it's too slow and you can't see that resolution anyway

        if (shioPriAudioBuffer.count > currStride) {
            var x_idx = 0
            for i in stride(from: max(0, ((shioPriAudioBuffer.count - numSamples) / currStride) * currStride), to: shioPriAudioBuffer.count, by: currStride) {
                lineChartEntry1.append(ChartDataEntry(x: Double(x_idx), y: Double(shioPriAudioBuffer[i]) - Double(offset)))
                x_idx += 1
            }
            let line1 = LineChartDataSet(entries: lineChartEntry1, label: "Mic 1")
            line1.drawCirclesEnabled = false
            line1.setColor(UIColor(red: 0.0/255.0, green: 150.0/255.0, blue: 255.0/255.0, alpha: 1.0))
            data.addDataSet(line1)
        }
        
        if (shioSecAudioBuffer.count > 100) {
            var x_idx = 0
            for i in stride(from: max(0, ((shioSecAudioBuffer.count - numSamples) / currStride) * currStride), to: shioSecAudioBuffer.count, by: currStride) {
                lineChartEntry2.append(ChartDataEntry(x: Double(x_idx), y: Double(shioSecAudioBuffer[i]) + Double(offset)))
                x_idx += 1
            }
            let line2 = LineChartDataSet(entries: lineChartEntry2, label: "Mic 2")
            line2.drawCirclesEnabled = false
            line2.setColor(UIColor(red: 0x63/255.0, green: 86.0/255.0, blue: 247.0/255.0, alpha: 1.0))
            data.addDataSet(line2)
        }
        
        liveView.data = data
    }

    // Function to create and write the wav files locally from Raw PCM. Returns filename of left and right
    func createWavFile(audioBufferPri: [Int16], audioBufferSec: [Int16]) -> (String, String) {
        // Hard coded params for now
        let sample_rate =  Float64(15625.0)
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
            let (stringPri, stringSec) = createWavFile(audioBufferPri: shioPriAudioBuffer, audioBufferSec: shioSecAudioBuffer)
            self.baseStringPri = stringPri
            self.baseStringSec = stringSec
            playButtonLeft.isHidden = false
            playButtonLeft.setTitle("Play Left", for: .normal)
            playButtonRight.isHidden = false
            playButtonRight.setTitle("Play Right", for: .normal)
            
            playButtonLeft.backgroundColor = (UIColor(red: 0.0/255.0, green: 150.0/255.0, blue: 255.0/255.0, alpha: 1.0))
            playButtonLeft.setTitleColor(UIColor.white, for: .normal)
            
            playButtonRight.backgroundColor = (UIColor(red: 0x63/255.0, green: 86.0/255.0, blue: 247.0/255.0, alpha: 1.0))
            playButtonRight.setTitleColor(UIColor.white, for: .normal)
            
        } else if (recordingState == RecordingState.done) {
            uploadAudio(baseString: self.baseStringPri)
            uploadAudio(baseString: self.baseStringSec)
            
            // Reset audio buffers and expected sequence numbers
            shioPriAudioBuffer = []
            shioSecAudioBuffer = []
            expectedSequenceNumberPri = 0
            expectedSequenceNumberSec = 0
        }
    }
    
    func uploadAudio(baseString: String) {
        let directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioURL = URL(fileURLWithPath: baseString, relativeTo: directoryURL).appendingPathExtension("wav")
        var folderName = ""
        if (voiseNoiseControlPicker.selectedSegmentIndex == 0) {
            folderName = "Voice/"
        } else {
            folderName = "Noise/"
        }
        
        let uploadNameWithPath = folderName + baseString + ".wav"
        
        AWSS3Manager.shared.uploadAudio(audioUrl: audioURL, uploadName: uploadNameWithPath, progress: { [weak self] (progress) in
            guard let strongSelf = self else { return }
            strongSelf.progressView.progress = Float(progress)
            
            strongSelf.recordButton.setTitle(String(Int(100*progress)) + "%", for:.normal)
        }) { [weak self] (uploadedFileUrl, error) in
            guard let strongSelf = self else { return }
            if (uploadedFileUrl as? String) != nil {
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
    
    @IBAction func tapPlayButtonLeft(_ sender: Any) {
        let directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioURL = URL(fileURLWithPath: self.baseStringPri, relativeTo: directoryURL).appendingPathExtension("wav")
        play(url: audioURL)
    }

    @IBAction func tapPlayButtonRight(_ sender: Any) {
        let directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioURL = URL(fileURLWithPath: self.baseStringSec, relativeTo: directoryURL).appendingPathExtension("wav")
        play(url: audioURL)
    }
    
    func play(url: URL) {
        print("playing \(url)")
        do {
            let new_url = URL(string: "http://grail.cs.washington.edu/projects/cone-of-silence/assets/audio_comparisons/input.wav")!
            self.player = AVPlayer(url: url)
            self.player.play()
            
        } catch let error as NSError {
            //self.player = nil
            print(error.localizedDescription)
        } catch {
            print("AVAudioPlayer init failed")
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
