//
//  MJCustomClipImageViewController.swift
//  Example
//
//  Created by custom implementation
//

import UIKit

open class MJCustomClipImageViewController: UIViewController, ZLClipImageViewControllerProtocol {
    
    // MARK: - ZLClipImageViewControllerProtocol Properties
    public var animate: Bool = true
    public var autoDismiss: Bool = true
    public var presentAnimateFrame: CGRect?
    public var presentAnimateImage: UIImage?
    public var clipDoneBlock: ((CGFloat, CGRect, ZLImageClipRatio) -> Void)?
    public var cancelClipBlock: (() -> Void)?
    
    // MARK: - Private Properties
    private let originalImage: UIImage
    private var editImage: UIImage
    private var editRect: CGRect
    private var angle: CGFloat = 0
    private let circleRatio: ZLImageClipRatio
    
    // UI Components
    private lazy var mainScrollView: UIScrollView = {
        let view = UIScrollView()
        view.alwaysBounceVertical = true
        view.alwaysBounceHorizontal = true
        view.showsVerticalScrollIndicator = false
        view.showsHorizontalScrollIndicator = false
        if #available(iOS 11.0, *) {
            view.contentInsetAdjustmentBehavior = .never
        }
        view.delegate = self
        view.minimumZoomScale = 1
        view.maximumZoomScale = 10
        return view
    }()
    
    private lazy var containerView = UIView()
    
    private lazy var imageView: UIImageView = {
        let view = UIImageView()
        view.image = editImage
        view.contentMode = .scaleAspectFit
        view.clipsToBounds = true
        return view
    }()
    
    private lazy var overlayView: CircleClipOverlayView = {
        let view = CircleClipOverlayView(frame: view.bounds)
        view.isUserInteractionEnabled = false
        return view
    }()
    
    private lazy var customDoneBtn: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("完成", for: .normal)
        btn.setTitleColor(.white, for: .normal)
        btn.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        btn.addTarget(self, action: #selector(doneBtnClick), for: .touchUpInside)
        return btn
    }()
    
    private lazy var customBackBtn: UIButton = {
        let btn = UIButton(type: .system)
        var backImage = UIImage.zl.getImage("zl_navBack")
        if backImage == nil {
            if #available(iOS 13.0, *) {
                backImage = UIImage(systemName: "chevron.left")
            }
        }
        btn.setImage(backImage, for: .normal)
        btn.tintColor = .white
        btn.addTarget(self, action: #selector(backBtnClick), for: .touchUpInside)
        return btn
    }()
    
    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.text = "裁剪图片"
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 17, weight: .medium)
        label.textAlignment = .center
        return label
    }()
    
    private var clipBoxFrame: CGRect = .zero
    private var maxClipFrame: CGRect = .zero
    private var minClipSize = CGSize(width: 45, height: 45)
    private var isDoneClicked = false
    
    // MARK: - Initialization
    public required init(image: UIImage, status: ZLClipStatus) {
        originalImage = image
        editRect = status.editRect
        angle = status.angle
        
        // 创建圆形裁剪比例, 显示的是圆形, 实际返回的正方形.
        circleRatio = ZLImageClipRatio(title: "circle", whRatio: 1, isCircle: false)
        
        // 处理图片旋转
        let angle = ((Int(angle) % 360) - 360) % 360
        if angle == -90 {
            editImage = image.zl.rotate(orientation: .left)
        } else if angle == -180 {
            editImage = image.zl.rotate(orientation: .down)
        } else if angle == -270 {
            editImage = image.zl.rotate(orientation: .right)
        } else {
            editImage = image
        }
        
        super.init(nibName: nil, bundle: nil)
        
        // 如果没有指定裁剪区域，计算默认的圆形裁剪区域
        if editRect == CGRect(origin: .zero, size: image.size) {
            calculateClipRect()
        }
    }
    
    public required init(image: UIImage) {
        originalImage = image
        editImage = image
        editRect = CGRect(origin: .zero, size: image.size)
        circleRatio = ZLImageClipRatio(title: "circle", whRatio: 1, isCircle: false)
        
        super.init(nibName: nil, bundle: nil)
        
        calculateClipRect()
    }
    
    @available(*, unavailable)
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    open override func viewDidLoad() {
        super.viewDidLoad()
        
        setupUI()
    }
    
    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 隐藏导航栏
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }
    
    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // 如果不是点击完成按钮，而是通过返回按钮返回，调用取消回调
        if !isDoneClicked && (isMovingFromParent || isBeingDismissed) {
            cancelClipBlock?()
        }
    }
    
    open override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        mainScrollView.frame = view.bounds
        maxClipFrame = calculateMaxClipFrame()
        layoutInitialImage()
    }
    
    open override var prefersStatusBarHidden: Bool {
        return false
    }
    
    open override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    // MARK: - Setup
    private func setupUI() {
        view.backgroundColor = .black
        
        view.addSubview(mainScrollView)
        mainScrollView.addSubview(containerView)
        containerView.addSubview(imageView)
        view.addSubview(overlayView)
        
        // 添加自定义按钮和标题
        view.addSubview(customBackBtn)
        view.addSubview(titleLabel)
        view.addSubview(customDoneBtn)
        
        // 设置约束
        customBackBtn.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        customDoneBtn.translatesAutoresizingMaskIntoConstraints = false
        
        if #available(iOS 11.0, *) {
            let safeArea = view.safeAreaLayoutGuide
            NSLayoutConstraint.activate([
                customBackBtn.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 10),
                customBackBtn.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 15),
                customBackBtn.widthAnchor.constraint(equalToConstant: 44),
                customBackBtn.heightAnchor.constraint(equalToConstant: 44),
                
                titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                titleLabel.centerYAnchor.constraint(equalTo: customBackBtn.centerYAnchor),
                
                customDoneBtn.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 10),
                customDoneBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -15),
                customDoneBtn.heightAnchor.constraint(equalToConstant: 44)
            ])
        } else {
            // iOS 11.0 以下使用 topLayoutGuide
            NSLayoutConstraint.activate([
                customBackBtn.topAnchor.constraint(equalTo: topLayoutGuide.bottomAnchor, constant: 10),
                customBackBtn.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 15),
                customBackBtn.widthAnchor.constraint(equalToConstant: 44),
                customBackBtn.heightAnchor.constraint(equalToConstant: 44),
                
                titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                titleLabel.centerYAnchor.constraint(equalTo: customBackBtn.centerYAnchor),
                
                customDoneBtn.topAnchor.constraint(equalTo: topLayoutGuide.bottomAnchor, constant: 10),
                customDoneBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -15),
                customDoneBtn.heightAnchor.constraint(equalToConstant: 44)
            ])
        }
    }
    
    @objc private func backBtnClick() {
        if navigationController != nil {
            navigationController?.popViewController(animated: true)
        } else {
            dismiss(animated: true, completion: nil)
        }
    }
    
    // MARK: - Calculations
    private func calculateMaxClipFrame() -> CGRect {
        var insets = deviceSafeAreaInsets()
        insets.top += 54 // 按钮区域高度（44 + 10间距）
        var rect = CGRect.zero
        rect.origin.x = 15
        rect.origin.y = insets.top
        rect.size.width = UIScreen.main.bounds.width - 30
        rect.size.height = UIScreen.main.bounds.height - insets.top - 20
        return rect
    }
    
    private func calculateClipRect() {
        let imageSize = editImage.size
        let minSide = min(imageSize.width, imageSize.height)
        let w = minSide
        let h = minSide
        
        editRect = CGRect(
            x: (imageSize.width - w) / 2,
            y: (imageSize.height - h) / 2,
            width: w,
            height: h
        )
    }
    
    private func layoutInitialImage() {
        mainScrollView.minimumZoomScale = 1
        mainScrollView.maximumZoomScale = 1
        mainScrollView.zoomScale = 1
        
        let editSize = editRect.size
        mainScrollView.contentSize = editSize
        let maxClipRect = maxClipFrame
        
        containerView.frame = CGRect(origin: .zero, size: editImage.size)
        imageView.frame = containerView.bounds
        
        // 计算裁剪框大小（圆形，取最大可用的正方形）
        let maxClipSize = min(maxClipRect.width, maxClipRect.height)
        let clipSize = CGSize(width: maxClipSize, height: maxClipSize)
        
        // 计算裁剪框位置（居中）
        var frame = CGRect.zero
        frame.size = clipSize
        frame.origin.x = maxClipRect.minX + (maxClipRect.width - frame.width) / 2
        frame.origin.y = maxClipRect.minY + (maxClipRect.height - frame.height) / 2
        
        clipBoxFrame = frame
        
        // 计算缩放比例
        let scale = max(frame.width / editImage.size.width, frame.height / editImage.size.height)
        mainScrollView.minimumZoomScale = scale
        mainScrollView.maximumZoomScale = 10
        mainScrollView.zoomScale = scale
        
        // 更新 content size
        mainScrollView.contentSize = CGSize(
            width: editImage.size.width * scale,
            height: editImage.size.height * scale
        )
        
        // 设置 content inset
        mainScrollView.contentInset = UIEdgeInsets(
            top: frame.minY,
            left: frame.minX,
            bottom: view.bounds.height - frame.maxY,
            right: view.bounds.width - frame.maxX
        )
        
        // 计算初始偏移量，使裁剪区域居中显示
        let diffX = editRect.origin.x / editImage.size.width * mainScrollView.contentSize.width
        let diffY = editRect.origin.y / editImage.size.height * mainScrollView.contentSize.height
        mainScrollView.contentOffset = CGPoint(
            x: -mainScrollView.contentInset.left + diffX,
            y: -mainScrollView.contentInset.top + diffY
        )
        
        // 更新 overlay
        overlayView.updateLayers(frame, animate: false, endEditing: true)
    }
    
    // MARK: - Actions
    @objc private func doneBtnClick() {
        isDoneClicked = true
        let image = clipImage()
        clipDoneBlock?(angle, image.editRect, circleRatio)
        
        if autoDismiss {
            if navigationController != nil {
                navigationController?.popViewController(animated: true)
            } else {
                dismiss(animated: animate, completion: nil)
            }
        }
    }
    
    private func clipImage() -> (clipImage: UIImage, editRect: CGRect) {
        let frame = convertClipRectToEditImageRect()
        let clipImage = editImage.zl.clipImage(angle: 0, editRect: frame, isCircle: true)
        return (clipImage, frame)
    }
    
    private func convertClipRectToEditImageRect() -> CGRect {
        let imageSize = editImage.size
        let contentSize = mainScrollView.contentSize
        let offset = mainScrollView.contentOffset
        let insets = mainScrollView.contentInset
        
        var frame = CGRect.zero
        frame.origin.x = floor((offset.x + insets.left) * (imageSize.width / contentSize.width))
        frame.origin.x = max(0, frame.origin.x)
        
        frame.origin.y = floor((offset.y + insets.top) * (imageSize.height / contentSize.height))
        frame.origin.y = max(0, frame.origin.y)
        
        // 圆形裁剪，使用正方形
        let clipSize = min(clipBoxFrame.width, clipBoxFrame.height)
        let scale = imageSize.width / contentSize.width
        let size = clipSize * scale
        
        frame.size.width = min(imageSize.width, size)
        frame.size.height = min(imageSize.height, size)
        
        // 确保是正方形
        let minSize = min(frame.size.width, frame.size.height)
        frame.size.width = minSize
        frame.size.height = minSize
        
        return frame
    }
}

// MARK: - UIScrollViewDelegate
extension MJCustomClipImageViewController: UIScrollViewDelegate {
    public func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return containerView
    }
    
    public func scrollViewDidZoom(_ scrollView: UIScrollView) {
        // 更新 overlay
        overlayView.updateLayers(clipBoxFrame, animate: false, endEditing: false)
    }
}

// MARK: - CircleClipOverlayView
private class CircleClipOverlayView: UIView {
    private lazy var shadowView: UIView = {
        let view = UIView()
        view.backgroundColor = .black.withAlphaComponent(0.7)
        view.layer.mask = shadowMaskLayer
        return view
    }()
    
    private lazy var shadowMaskLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillRule = .evenOdd
        return layer
    }()
    
//    private lazy var borderLayer: CAShapeLayer = {
//        let layer = CAShapeLayer()
//        layer.strokeColor = UIColor.white.cgColor
//        layer.fillColor = UIColor.clear.cgColor
//        layer.lineWidth = 2
//        layer.contentsScale = UIScreen.main.scale
//        return layer
//    }()
    
    var cropRect: CGRect = .zero
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        shadowView.frame = bounds
        shadowMaskLayer.frame = shadowView.bounds
//        borderLayer.frame = bounds
    }
    
    private func setupUI() {
        addSubview(shadowView)
//        layer.addSublayer(borderLayer)
    }
    
    func updateLayers(_ rect: CGRect, animate: Bool, endEditing: Bool) {
        cropRect = rect
        
        // 创建圆形路径
//        let circlePath = UIBezierPath(
//            roundedRect: rect,
//            cornerRadius: rect.width / 2
//        )
        
        // 创建遮罩路径（整个视图减去圆形区域）
        let maskPath = UIBezierPath(rect: bounds)
        maskPath.append(UIBezierPath(
            roundedRect: rect,
            cornerRadius: rect.width / 2
        ).reversing())
        
        // 更新边框路径
//        borderLayer.path = circlePath.cgPath
        
        // 更新遮罩路径
        if animate {
            let animation = CABasicAnimation(keyPath: "path")
            animation.fromValue = shadowMaskLayer.path
            animation.toValue = maskPath.cgPath
            animation.duration = 0.25
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            shadowMaskLayer.add(animation, forKey: "pathAnimation")
        }
        
        shadowMaskLayer.path = maskPath.cgPath
    }
}
