//
//  ViewController.swift
//  attentive_caption_0120
//
//  Created by 登山元気 on 2018/01/20.
//  Copyright © 2018年 genki toyama. All rights reserved.
//

import UIKit
import AVFoundation
import Vision

enum MODE {
    case TITLE
    case ABST
    case DETAIL
    case MORE_DETAIL
    case URABANASHI
}

class ViewController: UIViewController {
    
    //MARK: IBOutlet
    @IBOutlet weak var overlayView: OverlayView!
    @IBOutlet weak var facePreview: UIImageView!
    
    @IBOutlet weak var facePos: UILabel!
    @IBOutlet weak var faceTime: UILabel!
    @IBOutlet weak var faceArea: UILabel!
    @IBOutlet weak var currentID: UILabel!
    
    @IBOutlet var progressViews: [UIProgressView]!{
        didSet {
            progressViews.forEach {
                $0.transform = CGAffineTransform(scaleX: 1, y: 3)
                $0.progress = 0
            }
        }
    }
    
    @IBOutlet var probabilityLabels: [UILabel]! {
        didSet {
            probabilityLabels.forEach {
                $0.text = "-%"
            }
        }
    }
    
    //MARK: vraiables
    //video capture
    let session = AVCaptureSession()
    var device: AVCaptureDevice?
    var previewLayer: AVCaptureVideoPreviewLayer?
    var connection : AVCaptureConnection?
    
    static var isFrontCamera: Bool = true

    //timer
    var timer : Timer!
    var cnt : Float = 0
    var currentFaceNum : Int = 0
    var previousFaceNum : Int = 0
    
    let timerInterval : Double = 0.05
    
    //coreml
    let inputSize: Float = 112
    let momomind = How_old_0115()
    
    lazy var faceRequest: VNDetectFaceRectanglesRequest = {
        return VNDetectFaceRectanglesRequest(completionHandler: self.vnRequestHandler)
    }()
    
    var inputImage:CIImage?
    var overlayViewSize: CGSize?
    var videoDims: CMVideoDimensions?
    
    //decide age
    var confidenceDic = [Int:Float]()
    var confidences = [Int]()
    let confidenceSize : Int = 50
    var isStartPredict = false
    
    //decide font
    var prevFontID : Int = 0
    
    //decide MODE
    static var myMode = MODE.TITLE
    var prevMode = MODE.TITLE
    let faceAreaThresholdFar : Int = 20000
    let faceAreaThresholdNear : Int = 40000
    
    let faceTimeThresholdAbst : Int = 5
    let faceTimeThresholdDetail : Int = 15              //10+5
    let faceTimeThresholdMoreDetail : Int = 45          //30+10+5
    let faceTimeThresholdUrabanashi : Int = 75          //30+30+10+5
    
    //each works data
    
    //MARK: funcs
    override func viewDidLoad() {
        super.viewDidLoad()
        setupVideoCapture(isBack: true)
        
        //make timer
        timer = Timer.scheduledTimer(timeInterval: timerInterval, target: self,
                                     selector: #selector(self.onUpdate(timer:)), userInfo: nil, repeats: true)
        
        //hide predict part
//        overlayView.isHidden = true
    }
    
    //timer
    @objc func onUpdate(timer : Timer){
        if(currentFaceNum > 0){
            if (ViewController.myMode != MODE.TITLE && ViewController.myMode != MODE.ABST){
                cnt += Float(timerInterval)
            }else{
                cnt = 0.0
            }
            //桁数を指定して文字列を作る.
            let str = "faceTime: ".appendingFormat("%.2f",cnt)
            faceTime.text = str
        }
        previousFaceNum = currentFaceNum
        
        if(prevMode != ViewController.myMode){
            switch ViewController.myMode{
            case .TITLE:
                print("change to Title")
                prevMode = MODE.TITLE
            case .ABST:
                print("change to Abst")
                prevMode = MODE.ABST
            case .DETAIL:
                print("change to Detail")
                prevMode = MODE.DETAIL
            case .MORE_DETAIL:
                print("change to More detail")
                prevMode = MODE.MORE_DETAIL
            case .URABANASHI:
                print("change to Urabanashi")
                prevMode = MODE.URABANASHI
            }
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        overlayViewSize = overlayView.frame.size
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startSession()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSession()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
    }
}

//MARK: - setup video
extension ViewController {
    private var isActualDevice: Bool {
        return TARGET_OS_SIMULATOR != 1
    }
    
    private func startSession() {
        guard isActualDevice else { return }
        if !session.isRunning {
            session.startRunning()
        }
    }
    
    private func stopSession() {
        guard isActualDevice else { return }
        if session.isRunning {
            session.stopRunning()
        }
    }
    
    static func findDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        if position == .front{
            self.isFrontCamera = true
        }else{
            self.isFrontCamera = false
        }
        
        return AVCaptureDevice.default( .builtInWideAngleCamera,
                                        for: AVMediaType.video,
                                        position: position)
    }
    
    func setupVideoCapture(isBack: Bool) {
        guard isActualDevice else { return }
        
        let device = ViewController.findDevice(position: .front)!
        
        self.device = device
        session.sessionPreset = AVCaptureSession.Preset.inputPriority
        device.formats.forEach { (format) in
            print(format)
        }
        
        print("format:",device.activeFormat)
        print("min duration:", device.activeVideoMinFrameDuration)
        print("max duration:", device.activeVideoMaxFrameDuration)
        
        do {
            try device.lockForConfiguration()
        } catch {
            fatalError()
        }
        device.activeVideoMaxFrameDuration = CMTimeMake(1, 3)
        device.activeVideoMinFrameDuration = CMTimeMake(1, 3)
        device.unlockForConfiguration()
        
        let desc = device.activeFormat.formatDescription
        self.videoDims = CMVideoFormatDescriptionGetDimensions(desc)
        
        // Input
        let deviceInput: AVCaptureDeviceInput
        do {
            deviceInput = try AVCaptureDeviceInput(device: device)
        } catch {
            fatalError()
        }
        guard session.canAddInput(deviceInput) else {
            fatalError()
        }
        session.addInput(deviceInput)
        
        // Preview:
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.frame = view.layer.bounds
        previewLayer.contentsGravity = kCAGravityResizeAspectFill
        previewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
        view.layer.insertSublayer(previewLayer, at: 0)
        self.previewLayer = previewLayer
        
        //hide camera layer
//        self.previewLayer?.isHidden = true
        
        // Output
        let output = AVCaptureVideoDataOutput()
        let key = kCVPixelBufferPixelFormatTypeKey as String
        let val = kCVPixelFormatType_32BGRA as NSNumber
        output.videoSettings = [key: val]
        output.alwaysDiscardsLateVideoFrames = true
        let queue = DispatchQueue(label: "net.kenmaz.momomind")
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else {
            fatalError()
        }
        session.addOutput(output)
        
        self.connection = output.connection(with: AVMediaType.video)
    }
}

//MARK: - Video Capture
extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    // 毎フレーム実行される処理
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if connection.videoOrientation != .portrait {
            connection.videoOrientation = .portrait
            return
        }
        if let buffer = CMSampleBufferGetImageBuffer(sampleBuffer), connection == self.connection {
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            processBuffer(timestamp, buffer)
        }
    }
    
    private func processBuffer(_ timestamp: CMTime, _ buffer: CVImageBuffer) {
        let inputImage = CIImage(cvImageBuffer: buffer)
        let handler = VNImageRequestHandler(ciImage: inputImage)
        self.inputImage = inputImage
        
        //ずっと回す
        DispatchQueue.global(qos: .userInteractive).async {
            do {
                try handler.perform([self.faceRequest])
            } catch {
                print(error)
            }
        }
    }
}

//MARK: - Face detection
extension ViewController {
    func vnRequestHandler(request: VNRequest, error: Error?) {
        self.currentFaceNum = 1
        
        if let e = error {
            print(e)
            return
        }
        guard
            let req = request as? VNDetectFaceRectanglesRequest,
            let faces = req.results as? [VNFaceObservation],
            let centerFace = faces.sorted(by: { (a, b) -> Bool in distanceToCenter(face: a) < distanceToCenter(face: b) }).first else {
                self.currentFaceNum = 0
                updateTimer()
                return
        }
        guard let image = inputImage else {
            return
        }
        
        updateTimer()
        drawFaceRectOverlay(image: image, face: centerFace)
        
        guard let cgImage = getFaceCGImage(image: image, face: centerFace) else {
            return
        }
        
        if ViewController.myMode != MODE.TITLE && ViewController.myMode != MODE.ABST {
            showPreview(cgImage: cgImage)
            predicate(cgImage: cgImage)
        }
    }
    
    private func updateTimer(){
        if(self.currentFaceNum != self.previousFaceNum){
            if(self.currentFaceNum > 0){
                //timerを生成する.
                self.timer = Timer.scheduledTimer(timeInterval: self.timerInterval, target: self, selector: #selector(self.onUpdate(timer:)), userInfo: nil, repeats: true)
                print("face appear")
            }else{
                //timerを破棄する.
                self.timer.invalidate()
                self.cnt = 0
                
                self.isStartPredict = false
                self.confidences.removeAll()
                print("face disappear")
                
                ViewController.myMode = MODE.TITLE
            }
            self.previousFaceNum = self.currentFaceNum
        }
    }
    
    private func distanceToCenter(face: VNFaceObservation) -> CGFloat {
        let x = face.boundingBox.origin.x + face.boundingBox.size.width / 2
        let y = face.boundingBox.origin.y + face.boundingBox.size.height / 2
        let pos = CGPoint(x: x, y: y)
        let viewPos = CGPoint(x: 0.5, y: 0.5)
        let distance = sqrt(pow(pos.x - viewPos.x, 2) + pow(pos.y - viewPos.y, 2))
        return distance
    }
    
    //device = 1920,1080 (imagesize/videoDim)
    //image  = 736, 414
    //screen = 414, 736
    //
    private func drawFaceRectOverlay(image: CIImage, face: VNFaceObservation) {
        guard let viewSize = overlayViewSize else {
            return
        }
        
        var boxes:[CGRect] = []
        
        let box = face.boundingBox.scaledForOverlay(to: viewSize)
        boxes.append(box)
        
        let area = box.width * box.height
        let iArea = Int(area)
        let iTime = Int(cnt)
        
        if iArea < faceAreaThresholdFar {
            ViewController.myMode = MODE.TITLE
        }else if iArea < faceAreaThresholdNear {
            ViewController.myMode = MODE.ABST
        }else{
            if iTime < faceTimeThresholdDetail {
                ViewController.myMode = MODE.DETAIL
            }else if iTime < faceTimeThresholdMoreDetail {
                ViewController.myMode = MODE.MORE_DETAIL
            }else if iTime < faceTimeThresholdUrabanashi {
                ViewController.myMode = MODE.URABANASHI
            }else{
                //TODO: すぐ変わらないようにするための対策
                ViewController.myMode = MODE.TITLE
            }
        }
        
        DispatchQueue.main.async {
            self.overlayView.boxes = boxes
            self.overlayView.setNeedsDisplay()
            
            self.faceArea.text = String(format: "%.02f", Float(area))
            self.facePos.text = String(format: "%.01f", Float(box.midX)) + ", " + String(format: "%.01f", Float(box.midY))
        }
    }
    
    private func getFaceCGImage(image: CIImage, face: VNFaceObservation) -> CGImage? {
        let imageSize = image.extent.size
        
        let box = face.boundingBox.scaledForCropping(to: imageSize)
        guard image.extent.contains(box) else {
            return nil
        }
        let size = CGFloat(inputSize)
        
        let transform = CGAffineTransform(
            scaleX: size / box.size.width,
            y: size / box.size.height
        )
        let faceImage = image.cropped(to: box).transformed(by: transform)
        
        let ctx = CIContext()
        guard let cgImage = ctx.createCGImage(faceImage, from: faceImage.extent) else {
            assertionFailure()
            return nil
        }
        return cgImage
    }
    
    private func showPreview(cgImage:CGImage) {
        let uiImage = UIImage(cgImage: cgImage)
        DispatchQueue.main.async {
            self.facePreview.image = uiImage
        }
    }
}

//MARK: - Predicate
extension ViewController {
    fileprivate func predicate(cgImage: CGImage) {
        let image = CIImage(cgImage: cgImage)
        
        let handler = VNImageRequestHandler(ciImage: image)
        do {
            let model = try VNCoreMLModel(for: self.momomind.model)
            let req = VNCoreMLRequest(model: model, completionHandler: self.handleClassification)
            try handler.perform([req])
        } catch {
            print(error)
        }
        
        
    }
    
    private func handleClassification(request: VNRequest, error: Error?) {
        guard let observations = request.results as? [VNClassificationObservation]
            else { fatalError("unexpected result type from VNCoreMLRequest") }
        
        DispatchQueue.main.async {
            for ob in observations {
                switch ob.identifier {
                case "0-15male": self.updateLabel(idx: 0, ob: ob)
                case "0-15female": self.updateLabel(idx: 1, ob: ob)
                case "16-29male": self.updateLabel(idx: 2, ob: ob)
                case "16-29female": self.updateLabel(idx: 3, ob: ob)
                case "30-49male": self.updateLabel(idx: 4, ob: ob)
                case "30-49female": self.updateLabel(idx: 5, ob: ob)
                case "50-male": self.updateLabel(idx: 6, ob: ob)
                case "50-female": self.updateLabel(idx: 7, ob: ob)
                default:
                    break
                }
            }
        }
        
        if (self.isStartPredict && observations.count > 0) {
            self.confidences.append(self.maxDicKey(dic: self.confidenceDic))
//            print("added: \(self.confidences.last!)")
            if(self.confidences.count > self.confidenceSize){
                self.confidences.removeFirst()
            }
            var count = [Int](repeating: 0, count: 8)
            for c in confidences{
                count[c] += 1
            }
            let maxID = maxArrKey(arr: count)
            
            if prevFontID != maxID{
                switch maxID {
                case 0:
                    print(maxID)
                    prevFontID = maxID
                case 1:
                    print(maxID)
                    prevFontID = maxID
                case 2:
                    print(maxID)
                    prevFontID = maxID
                case 3:
                    print(maxID)
                    prevFontID = maxID
                case 4:
                    print(maxID)
                    prevFontID = maxID
                case 5:
                    print(maxID)
                    prevFontID = maxID
                case 6:
                    print(maxID)
                    prevFontID = maxID
                case 7:
                    print(maxID)
                    prevFontID = maxID
                default:
                    print("hoge")
                }
            }
            
            //TODO: フォントを即反映させないようにしたい
            DispatchQueue.main.async {
                self.currentID.text = "currID: " + String(describing: maxID)
                
            }
        }
        
    }
    
    private func updateLabel(idx: Int, ob: VNClassificationObservation) {
        let label = probabilityLabels.filter{ $0.tag == idx }.first
        let progress = progressViews.filter{ $0.tag == idx }.first
        
        let per = Int(ob.confidence * 100)
        label?.text = "\(per)%"
        progress?.progress = ob.confidence
        
        confidenceDic[idx] = ob.confidence
//        print("conf added: \(idx), \(ob.confidence)")
        
        if(!self.isStartPredict){
            self.isStartPredict = true
        }
    }
    
    private func maxDicKey(dic:[Int:Float]) -> Int{
        //valueの最大値を取り出す
        let max = dic.values.max()
        var maxKey:Int = -1
        //辞書の中身をひとつずつ見ていく
        for (key,value) in dic{
            if value == max{
//                print("key: \(key), value: \(value)")
                if maxKey == -1{
                    maxKey = key
                }else{
                    print("dic errorrrrr")
                }
            }
        }
        return maxKey
    }
    
    private func maxArrKey(arr:[Int]) -> Int{
        //valueの最大値を取り出す
        let max = arr.max()
        var maxKey:Int = -1
        //辞書の中身をひとつずつ見ていく
        for (i, value) in arr.enumerated(){
            if value == max{
                if maxKey == -1{
                    maxKey = i
                }else{
                    print("arr errorrrrr \(maxKey)")
                }
            }
        }
        return maxKey
    }
}

extension CGRect {
    func scaledForOverlay(to size: CGSize) -> CGRect {
        
        let posx :CGFloat
        
        if(ViewController.isFrontCamera == true){
            posx = (1.0 - self.origin.x - self.size.width) * size.width
        }else{
            posx = self.origin.x * size.width
        }
        
        return CGRect(
            x: posx,
            y: (1.0 - self.origin.y - self.size.height) * size.height,
            width: (self.size.width * size.width),
            height: (self.size.height * size.height)
        )
    }
    
    func scaledForCropping(to size: CGSize) -> CGRect {
        return CGRect(
            x: self.origin.x * size.width,
            y: self.origin.y * size.height,
            width: (self.size.width * size.width),
            height: (self.size.height * size.height)
        )
    }
}
