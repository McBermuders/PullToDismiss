//
//  PullToDismiss.swift
//  PullToDismiss
//
//  Created by Suguru Kishimoto on 11/13/16.
//  Copyright © 2016 Suguru Kishimoto. All rights reserved.
//

import Foundation
import UIKit

open class PullToDismiss: NSObject {
    
    /// Background
    ///
    /// - none: no shadow view
    /// - shadow(color, alpha): have shadow view (view color, view initial alpha)
    /// - blur(blurRadius, color, alpha): have blur view (blur radius, blur color, blur color alpha)
    public enum Background {
        case none
        case shadow(UIColor, CGFloat) // color(RGB), alpha
        case blur(CGFloat, UIColor, CGFloat) // blurRadius, blur color(RGB), blur alpha
        
        public static let defaultShadow: Background = Background.shadow(.black, 0.5)
        public static let defaultBlur: Background = Background.blur(20.0, .clear, 0.0)
        
        public func change(color: UIColor? = nil, alpha: CGFloat? = nil, blur: CGFloat? = nil) -> Background {
            switch self {
            case .none: return self
            case .shadow(let c, let a): return .shadow(color ?? c, alpha ?? a)
            case .blur(let b, let c, let a): return .blur(blur ?? b, color ?? c, alpha ?? a)
            }
        }
        
        public var color: UIColor? {
            switch self {
            case .none: return nil
            case .shadow(let color, _): return color
            case .blur(_, let color, _): return color
            }
        }
        
        public var alpha: CGFloat {
            switch self {
            case .none: return 0.0
            case .shadow(_, let alpha): return alpha
            case .blur(_, _, let alpha): return alpha
            }
        }
    }
    
    public struct Defaults {
        private init() {}
        public static let dismissableHeightPercentage: CGFloat = 0.33
    }
    
    open var background: Background = .defaultShadow
    public var dismissAction: (() -> Void)?
    public weak var delegateProxy: AnyObject?
    public var dismissableHeightPercentage: CGFloat = Defaults.dismissableHeightPercentage {
        didSet {
            dismissableHeightPercentage = min(max(0.0, dismissableHeightPercentage), 1.0)
        }
    }

    fileprivate var viewPositionY: CGFloat = 0.0
    fileprivate var dragging: Bool = false
    fileprivate var previousContentOffsetY: CGFloat = 0.0
    fileprivate weak var viewController: UIViewController?
    
    private var panGesture: UIPanGestureRecognizer?
    private var shadowView: UIView?
    private var blurView: CustomBlurView?
    private var navigationBarHeight: CGFloat = 0.0
    convenience public init?(scrollView: UIScrollView) {
        guard let viewController = type(of: self).viewControllerFromScrollView(scrollView) else {
            print("a scrollView must be on the view controller.")
            return nil
        }
        self.init(scrollView: scrollView, viewController: viewController)
    }
    
    public init(scrollView: UIScrollView, viewController: UIViewController, navigationBar: UIView? = nil) {
        super.init()
        scrollView.delegate = self
        self.viewController = viewController
        if let navigationBar = navigationBar ?? viewController.navigationController?.navigationBar {
            let gesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
            navigationBar.addGestureRecognizer(gesture)
            navigationBarHeight = navigationBar.frame.height
            self.panGesture = gesture
        }
    }

    deinit {
        if let panGesture = panGesture {
            panGesture.view?.removeGestureRecognizer(panGesture)
        }
    }
    
    fileprivate var targetViewController: UIViewController? {
        return viewController?.navigationController ?? viewController
    }
    
    fileprivate func dismiss() {
        targetViewController?.dismiss(animated: true, completion: nil)
    }
    
    // MARK: - shadow view
    
    private func makeBackgroundView() {
        
        switch background {
        case .shadow(let color, let alpha):
            let shadowView = UIView(frame: .zero)
            shadowView.backgroundColor = color
            shadowView.alpha = alpha
            targetViewController?.view.addSubview(shadowView)
            targetViewController?.view.clipsToBounds = false
            shadowView.frame = targetViewController?.view.bounds ?? .zero
            shadowView.superview?.sendSubview(toBack: shadowView)
            self.shadowView = shadowView
        case .blur(let blurRadius, let colorTint, let colorTintAlpha):
            let blurView = CustomBlurView(radius: blurRadius)
            blurView.colorTint = colorTint
            blurView.colorTintAlpha = colorTintAlpha
            targetViewController?.view.addSubview(blurView)
            targetViewController?.view.clipsToBounds = false
            blurView.frame = targetViewController?.view.bounds ?? .zero
            blurView.superview?.sendSubview(toBack: blurView)
            self.blurView = blurView
        default:
            ()
        }
    }
    
    private func updateBackgroundView() {
        switch background {
        case .shadow(_, let alpha):
            let targetViewOriginY: CGFloat = targetViewController?.view.frame.origin.y ?? 0.0
            let targetViewHeight: CGFloat = targetViewController?.view.frame.height ?? 0.0
            self.shadowView?.alpha = (1.0 - (targetViewOriginY / (targetViewHeight * dismissableHeightPercentage))) * alpha
        case .blur(let blurRadius, _, _):
            let targetViewOriginY: CGFloat = targetViewController?.view.frame.origin.y ?? 0.0
            let targetViewHeight: CGFloat = targetViewController?.view.frame.height ?? 0.0
            self.blurView?.blurRadius = (1.0 - (targetViewOriginY / (targetViewHeight * dismissableHeightPercentage))) * blurRadius
        default:
            ()
        }
    }
    
    private func deleteBackgroundView() {
        self.shadowView?.removeFromSuperview()
        self.shadowView = nil
        self.blurView?.removeFromSuperview()
        self.blurView = nil
    }
    
    private func resetBackgroundView() {
        switch background {
        case .shadow(_, let alpha):
            self.shadowView?.alpha = alpha
        case .blur(let blurRadius, _, _):
            self.blurView?.blurRadius = blurRadius
        default:
            ()
        }
    }
    
    @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            startDragging()
        case .changed:
            let diff = gesture.translation(in: gesture.view).y
            updateViewPosition(offset: diff)
            gesture.setTranslation(.zero, in: gesture.view)
        case .ended:
            finishDragging()
        default:
            break
        }
    }
    
    fileprivate func startDragging() {
        viewPositionY = 0.0
        makeBackgroundView()
    }
    
    fileprivate func updateViewPosition(offset: CGFloat) {
        var addOffset: CGFloat = offset
        // avoid statusbar gone
        if viewPositionY >= 0 && viewPositionY < 0.05 {
            addOffset = min(max(-0.01, addOffset), 0.01)
        }
        viewPositionY += addOffset
        targetViewController?.view.frame.origin.y = max(0.0, viewPositionY)
        shadowView?.frame.origin.y = -(targetViewController?.view.frame.origin.y ?? 0.0)
        updateBackgroundView()
    }
    
    fileprivate func finishDragging() {
        let originY = targetViewController?.view.frame.origin.y ?? 0.0
        let dismissableHeight = (targetViewController?.view.frame.height ?? 0.0) * dismissableHeightPercentage
        if originY > dismissableHeight {
            deleteBackgroundView()
            _ = dismissAction?() ?? dismiss()
        } else if originY != 0.0 {
            if targetViewController?.view.frame.minY != 0.0 {
                UIView.perform(.delete, on: [], options: [], animations: { [weak self] in
                    self?.targetViewController?.view.frame.origin.y = 0.0
                    self?.resetBackgroundView()
                }) { [weak self] _ in
                    self?.deleteBackgroundView()
                }
            }
        }
        viewPositionY = 0.0
    }
    
    private static func viewControllerFromScrollView(_ scrollView: UIScrollView) -> UIViewController? {
        var responder: UIResponder? = scrollView
        while let r = responder {
            if let viewController = r as? UIViewController {
                return viewController
            }
            responder = r.next
        }
        return nil
    }
    
    // MARK: - delegates
    
    public var scrollViewDelegate: UIScrollViewDelegate? {
        return delegateProxy as? UIScrollViewDelegate
    }
    
    public var tableViewDelegate: UITableViewDelegate? {
        return delegateProxy as? UITableViewDelegate
    }
    
    public var collectionViewDelegate: UICollectionViewDelegate? {
        return delegateProxy as? UICollectionViewDelegate
    }
    
    public var collectionViewDelegateFlowLayout: UICollectionViewDelegateFlowLayout? {
        return delegateProxy as? UICollectionViewDelegateFlowLayout
    }
}

extension PullToDismiss: UIScrollViewDelegate {
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if dragging {
            let diff = -(scrollView.contentOffset.y - previousContentOffsetY)
            if scrollView.contentOffset.y < -scrollView.contentInset.top || (targetViewController?.view.frame.origin.y ?? 0.0) > 0.0 {
                updateViewPosition(offset: diff)
                scrollView.contentOffset.y = -scrollView.contentInset.top
            }
            previousContentOffsetY = scrollView.contentOffset.y
        }
        scrollViewDelegate?.scrollViewDidScroll?(scrollView)
    }
    
    public func scrollViewDidZoom(_ scrollView: UIScrollView) {
        scrollViewDelegate?.scrollViewDidZoom?(scrollView)
    }
    
    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        startDragging()
        dragging = true
        previousContentOffsetY = scrollView.contentOffset.y
        scrollViewDelegate?.scrollViewWillBeginDragging?(scrollView)
    }
    
    public func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        scrollViewDelegate?.scrollViewWillEndDragging?(scrollView, withVelocity: velocity, targetContentOffset: targetContentOffset)
    }
    
    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        finishDragging()
        dragging = false
        previousContentOffsetY = 0.0
        scrollViewDelegate?.scrollViewDidEndDragging?(scrollView, willDecelerate: decelerate)
    }
    
    public func scrollViewWillBeginDecelerating(_ scrollView: UIScrollView) {
        scrollViewDelegate?.scrollViewWillBeginDecelerating?(scrollView)
    }
    
    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        scrollViewDelegate?.scrollViewDidEndDecelerating?(scrollView)
    }
    
    public func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        scrollViewDelegate?.scrollViewDidEndScrollingAnimation?(scrollView)
    }
    
    public func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return scrollViewDelegate?.viewForZooming?(in: scrollView)
    }
    
    public func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        scrollViewDelegate?.scrollViewWillBeginZooming?(scrollView, with: view)
    }
    
    public func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        scrollViewDelegate?.scrollViewDidEndZooming?(scrollView, with: view, atScale: scale)
    }
    
    public func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
        return scrollViewDelegate?.scrollViewShouldScrollToTop?(scrollView) ?? true
    }
    
    public func scrollViewDidScrollToTop(_ scrollView: UIScrollView) {
        scrollViewDelegate?.scrollViewDidScrollToTop?(scrollView)
    }
}
