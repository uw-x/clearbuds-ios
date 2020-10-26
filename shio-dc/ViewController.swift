//
//  ViewController.swift
//  shio-dc
//
//  Created by Maruchi Kim on 10/26/20.
//  https://www.swiftdevcenter.com/upload-image-video-audio-and-any-type-of-files-to-aws-s3-bucket-swift/

import UIKit

class ViewController: UIViewController {

    @IBOutlet weak var s3UrlLabel: UILabel!
    @IBOutlet weak var progressView: UIProgressView!
    let testFilePath = Bundle.main.path(forResource: "Two Dumbs Up - uncoolclub", ofType: "mp3")
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        
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

