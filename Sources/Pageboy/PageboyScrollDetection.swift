//
//  PageboyScrollDetection.swift
//  Pageboy
//
//  Created by Merrick Sapsford on 13/02/2017.
//  Copyright © 2017 Merrick Sapsford. All rights reserved.
//

import Foundation

// MARK: - UIPageViewControllerDelegate, UIScrollViewDelegate
extension PageboyViewController: UIPageViewControllerDelegate, UIScrollViewDelegate {
    
    public func pageViewController(_ pageViewController: UIPageViewController,
                                   willTransitionTo pendingViewControllers: [UIViewController]) {
        self.pageViewController(pageViewController,
                                willTransitionTo: pendingViewControllers,
                                animated: false)
    }
    
    internal func pageViewController(_ pageViewController: UIPageViewController,
                                     willTransitionTo pendingViewControllers: [UIViewController],
                                     animated: Bool) {
        guard let viewController = pendingViewControllers.first,
            let index = self.viewControllers?.index(of: viewController) else {
                return
        }
        
        self.expectedTransitionIndex = index
        let direction = NavigationDirection.forPage(index, previousPage: self.currentIndex ?? index)
        self.delegate?.pageboyViewController(self, willScrollToPageAtIndex: index,
                                             direction: direction,
                                             animated: animated)
    }
    
    public func pageViewController(_ pageViewController: UIPageViewController,
                                   didFinishAnimating finished: Bool,
                                   previousViewControllers: [UIViewController],
                                   transitionCompleted completed: Bool) {
        guard completed == true else { return }
        
        if let viewController = pageViewController.viewControllers?.first,
            let index = self.viewControllers?.index(of: viewController) {
            guard index == self.expectedTransitionIndex else { return }
            
            self.updateCurrentPageIndexIfNeeded(index)
        }
    }
    
    //
    // MARK: UIScrollViewDelegate
    //
    
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard let currentIndex = self.currentIndex else {
            return
        }
        
        let previousPagePosition = self.previousPagePosition ?? 0.0
        
        // calculate offset / page size for relative orientation
        var pageSize: CGFloat!
        var contentOffset: CGFloat!
        if self.navigationOrientation == .horizontal {
            pageSize = scrollView.frame.size.width
            contentOffset = scrollView.contentOffset.x
        } else {
            pageSize = scrollView.frame.size.height
            contentOffset = scrollView.contentOffset.y
        }
        
        guard let scrollIndexDiff = self.pageScrollIndexDiff(forCurrentIndex: currentIndex,
                                                       expectedIndex: self.expectedTransitionIndex,
                                                       currentContentOffset: contentOffset,
                                                       pageSize: pageSize) else {
                                                        return
        }
        
        guard var pagePosition = self.pagePosition(forContentOffset: contentOffset,
                                                   pageSize: pageSize,
                                                   indexDiff: scrollIndexDiff) else {
                                                        return
        }
        
        // do not continue if a page change is detected
        guard !self.detectCurrentPageIndexIfNeeded(pagePosition: pagePosition,
                                                   scrollView: scrollView) else {
            return
        }
        
        // do not continue if previous position equals current
        if previousPagePosition == pagePosition {
            return
        }
        
        // update relative page position for infinite overscroll if required
        self.detectInfiniteOverscrollIfNeeded(pagePosition: &pagePosition)
        
        // provide scroll updates
        var positionPoint: CGPoint!
        let direction = NavigationDirection.forPosition(pagePosition, previous: previousPagePosition)
        if self.navigationOrientation == .horizontal {
            positionPoint = CGPoint(x: pagePosition, y: scrollView.contentOffset.y)
        } else {
            positionPoint = CGPoint(x: scrollView.contentOffset.x, y: pagePosition)
        }
                
        // ignore duplicate updates
        guard self.currentPosition != positionPoint else { return }
        self.currentPosition = positionPoint
        self.delegate?.pageboyViewController(self,
                                             didScrollToPosition: positionPoint,
                                             direction: direction,
                                             animated: self.isScrollingAnimated)
        
        self.previousPagePosition = pagePosition
    }
    
    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        if self.autoScroller.cancelsOnScroll {
            self.autoScroller.cancel()
        }
    }
    
    public func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        self.scrollView(didEndScrolling: scrollView)
    }
    
    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        self.scrollView(didEndScrolling: scrollView)
    }
    
    private func scrollView(didEndScrolling scrollView: UIScrollView) {
        if self.autoScroller.restartsOnScrollEnd {
            self.autoScroller.restart()
        }
    }
    
    //
    // MARK: Utils
    //
    
    /// Detect whether the scroll view is overscrolling while infinite scroll is enabled
    /// Adjusts pagePosition if required.
    ///
    /// - Parameter pagePosition: the relative page position.
    private func detectInfiniteOverscrollIfNeeded(pagePosition: inout CGFloat) {
        guard self.isInfinitelyScrolling(forPosition: pagePosition) else {
            return
        }
        
        let maxPagePosition = CGFloat((self.viewControllers?.count ?? 1) - 1)
        var integral: Double = 0.0
        var progress = CGFloat(modf(fabs(Double(pagePosition)), &integral))
        var maxInfinitePosition: CGFloat!
        if pagePosition > 0.0 {
            progress = 1.0 - progress
            maxInfinitePosition = 0.0
        } else {
            maxInfinitePosition = maxPagePosition
        }
        
        var infinitePagePosition = maxPagePosition * progress
        if fmod(progress, 1.0) == 0.0 {
            infinitePagePosition = maxInfinitePosition
        }
        
        pagePosition = infinitePagePosition
    }
    
    /// Whether a position is infinitely scrolling between end ranges
    ///
    /// - Parameter pagePosition: The position.
    /// - Returns: Whether the position is infinitely scrolling.
    private func isInfinitelyScrolling(forPosition pagePosition: CGFloat) -> Bool {
        let maxPagePosition = CGFloat((self.viewControllers?.count ?? 1) - 1)
        let overscrolling = pagePosition < 0.0 || pagePosition > maxPagePosition
        
        guard self.isInfiniteScrollEnabled && overscrolling else {
            return false
        }
        return true
    }
    
    /// Detects whether a page boundary has been passed.
    /// As pageViewController:didFinishAnimating is not reliable.
    ///
    /// - Parameters:
    ///   - pageOffset: The current page scroll offset
    ///   - scrollView: The scroll view that is being scrolled.
    /// - Returns: Whether a page transition has been detected.
    private func detectCurrentPageIndexIfNeeded(pagePosition: CGFloat, scrollView: UIScrollView) -> Bool {
        guard let currentIndex = self.currentIndex else {
            return false
        }
        
        let isPagingForward = pagePosition > self.previousPagePosition ?? 0.0
        if scrollView.isDragging {
            if isPagingForward && pagePosition >= CGFloat(currentIndex + 1) {
                self.updateCurrentPageIndexIfNeeded(currentIndex + 1)
                return true
            } else if !isPagingForward && pagePosition <= CGFloat(currentIndex - 1) {
                self.updateCurrentPageIndexIfNeeded(currentIndex - 1)
                return true
            }
        }
        
        let isOnPage = pagePosition.truncatingRemainder(dividingBy: 1) == 0
        if isOnPage {
            guard currentIndex != self.currentIndex else { return false}
            self.currentIndex = currentIndex
        }
        
        return false
    }
    
    /// Safely update the current page index.
    ///
    /// - Parameter index: the proposed index.
    private func updateCurrentPageIndexIfNeeded(_ index: Int) {
        guard self.currentIndex != index, index >= 0 &&
            index < self.viewControllers?.count ?? 0 else {
                return
        }
        self.currentIndex = index
    }
    
    /// Calculate the expected index diff for a page scroll.
    ///
    /// - Parameters:
    ///   - index: The current index.
    ///   - expectedIndex: The target page index.
    ///   - currentContentOffset: The current content offset.
    ///   - pageSize: The size of each page.
    /// - Returns: The expected index diff.
    private func pageScrollIndexDiff(forCurrentIndex index: Int?,
                                     expectedIndex: Int?,
                                     currentContentOffset: CGFloat,
                                     pageSize: CGFloat) -> CGFloat? {
        guard let index = index else {
            return nil
        }
        
        let expectedIndex = expectedIndex ?? index
        let expectedDiff = CGFloat(max(1, abs(expectedIndex - index)))
        let expectedPosition = self.pagePosition(forContentOffset: currentContentOffset,
                                                 pageSize: pageSize,
                                                 indexDiff: expectedDiff) ?? CGFloat(index)
        
        guard self.isInfinitelyScrolling(forPosition: expectedPosition) == false else {
            return 1
        }
        return expectedDiff
    }
    
    /// Calculate the relative page position.
    ///
    /// - Parameters:
    ///   - contentOffset: The current contentOffset.
    ///   - pageSize: The current page size.
    ///   - indexDiff: The expected difference between current / target page indexes.
    /// - Returns: The relative page position.
    private func pagePosition(forContentOffset contentOffset: CGFloat,
                                       pageSize: CGFloat,
                                       indexDiff: CGFloat) -> CGFloat? {
        guard let currentIndex = self.currentIndex else {
            return nil
        }
        
        let scrollOffset = contentOffset - pageSize
        let pageOffset = (CGFloat(currentIndex) * pageSize) + (scrollOffset * indexDiff)
        return pageOffset / pageSize
    }
}


// MARK: - NavigationDirection detection
internal extension PageboyViewController.NavigationDirection {
    
    var pageViewControllerNavDirection: UIPageViewControllerNavigationDirection {
        get {
            switch self {
                
            case .reverse:
                return .reverse
                
            default:
                return .forward
            }
        }
    }
    
    static func forPage(_ page: Int,
                          previousPage: Int) -> PageboyViewController.NavigationDirection {
        return self.forPosition(CGFloat(page), previous: CGFloat(previousPage))
    }
    
    static func forPosition(_ position: CGFloat,
                            previous previousPosition: CGFloat) -> PageboyViewController.NavigationDirection {
        if position == previousPosition {
            return .neutral
        }
        return  position > previousPosition ? .forward : .reverse
    }
}
