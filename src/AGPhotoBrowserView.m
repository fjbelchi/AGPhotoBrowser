//
//  AGPhotoBrowserView.m
//  AGPhotoBrowser
//
//  Created by Hellrider on 7/28/13.
//  Copyright (c) 2013 Andrea Giavatto. All rights reserved.
//

#import "AGPhotoBrowserView.h"

#import <QuartzCore/QuartzCore.h>
#import "AGPhotoBrowserOverlayView.h"
#import "AGPhotoBrowserZoomableView.h"
#import "AGPhotoBrowserCell.h"
#import "AGPhotoBrowserCellProtocol.h"

@interface AGPhotoBrowserView () <
AGPhotoBrowserOverlayViewDelegate,
AGPhotoBrowserCellDelegate,
UICollectionViewDataSource,
UICollectionViewDelegate,
UIBarPositioningDelegate,
UIGestureRecognizerDelegate
> {
	CGPoint _startingPanPoint;
	BOOL _wantedFullscreenLayout;
    BOOL _navigationBarWasHidden;
	CGRect _originalParentViewFrame;
	NSInteger _currentlySelectedIndex;
    
    BOOL _changingOrientation;
}

@property (nonatomic, strong, readwrite) UIButton *doneButton;
@property (nonatomic, strong) UICollectionView *photoCollectionView;
@property (nonatomic, strong) AGPhotoBrowserOverlayView *overlayView;

@property (nonatomic, strong) UIWindow *previousWindow;
@property (nonatomic, strong) UIWindow *currentWindow;

@property (nonatomic, assign, readonly) CGSize cellSize;

@property (nonatomic, assign, getter = isDisplayingDetailedView) BOOL displayingDetailedView;

@end


static NSString *CellIdentifier = @"AGPhotoBrowserCell";

@implementation AGPhotoBrowserView

const NSInteger AGPhotoBrowserThresholdToCenter = 150;

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:[UIScreen mainScreen].bounds];
    if (self) {
        // Initialization code
		[self setupView];
    }
    return self;
}

- (void)setupView
{
	self.userInteractionEnabled = NO;
	self.backgroundColor = [UIColor colorWithWhite:0. alpha:0.];
	_currentlySelectedIndex = NSNotFound;
    _changingOrientation = NO;
	
	[self addSubview:self.photoCollectionView];
	[self addSubview:self.doneButton];
	[self addSubview:self.overlayView];
	
	[[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(statusBarDidChangeFrame:)
                                                 name:UIDeviceOrientationDidChangeNotification
                                               object:nil];
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}


#pragma mark - Getters

- (UIButton *)doneButton
{
	if (!_doneButton) {
		_doneButton = [[UIButton alloc] initWithFrame:CGRectMake(CGRectGetWidth([UIScreen mainScreen].bounds) - 60 - 10, 20, 60, 32)];
		[_doneButton setTitle:NSLocalizedString(@"Done", @"Title for Done button") forState:UIControlStateNormal];
		_doneButton.layer.cornerRadius = 3.0f;
		_doneButton.layer.borderColor = [UIColor colorWithWhite:0.9 alpha:0.9].CGColor;
		_doneButton.layer.borderWidth = 1.0f;
		[_doneButton setBackgroundColor:[UIColor colorWithWhite:0.1 alpha:0.5]];
		[_doneButton setTitleColor:[UIColor colorWithWhite:0.9 alpha:0.9] forState:UIControlStateNormal];
		[_doneButton setTitleColor:[UIColor colorWithWhite:0.9 alpha:0.9] forState:UIControlStateHighlighted];
		[_doneButton.titleLabel setFont:[UIFont boldSystemFontOfSize:14.0f]];
		_doneButton.alpha = 0.;
		
		[_doneButton addTarget:self action:@selector(p_doneButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
	}
	
	return _doneButton;
}

- (UICollectionView *)photoCollectionView
{
    if (!_photoCollectionView) {

        CGRect screenBounds = [[UIScreen mainScreen] bounds];
        
        UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
        layout.itemSize = screenBounds.size;
        layout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
        
        _photoCollectionView = [[UICollectionView alloc] initWithFrame:screenBounds collectionViewLayout:layout];
        _photoCollectionView.dataSource = self;
        _photoCollectionView.delegate = self;
        _photoCollectionView.pagingEnabled = YES;
        [_photoCollectionView registerClass:[AGPhotoBrowserCell class] forCellWithReuseIdentifier:CellIdentifier];
    }
    
    return _photoCollectionView;
}

- (AGPhotoBrowserOverlayView *)overlayView
{
	if (!_overlayView) {
		_overlayView = [[AGPhotoBrowserOverlayView alloc] initWithFrame:CGRectZero];
        _overlayView.delegate = self;
	}
	
	return _overlayView;
}

- (CGSize)cellSize
{
	UIDeviceOrientation orientation = [[UIDevice currentDevice] orientation];
	if (UIDeviceOrientationIsLandscape(orientation)) {
		return self.currentWindow.frame.size;
	}
	
	return self.currentWindow.frame.size;
}


#pragma mark - Setters

- (void)setDisplayingDetailedView:(BOOL)displayingDetailedView
{
	_displayingDetailedView = displayingDetailedView;
	
	CGFloat newAlpha;
	
	if (_displayingDetailedView) {
		[self.overlayView setOverlayVisible:YES animated:YES];
		newAlpha = 1.;
	} else {
		[self.overlayView setOverlayVisible:NO animated:YES];
		newAlpha = 0.;
	}
	
	[UIView animateWithDuration:AGPhotoBrowserAnimationDuration
					 animations:^(){
						 self.doneButton.alpha = newAlpha;
					 }];
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    NSInteger number = [_dataSource numberOfPhotosForPhotoBrowser:self];
    
    if (number > 0 && _currentlySelectedIndex == NSNotFound && !self.currentWindow.hidden) {
        // initialize with info for the first photo in photoTable
        [self setupPhotoForIndex:0];
    }
    
    return number;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    AGPhotoBrowserCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:CellIdentifier forIndexPath:indexPath];
    
    [self configureCell:cell forRowAtIndexPath:indexPath];
    [self.overlayView resetOverlayView];
    
    return cell;
}

- (void)configureCell:(UICollectionViewCell<AGPhotoBrowserCellProtocol> *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if ([cell respondsToSelector:@selector(resetZoomScale)]) {
        [cell resetZoomScale];
    }
    
    if ([_dataSource respondsToSelector:@selector(photoBrowser:URLStringForImageAtIndex:)] && [cell respondsToSelector:@selector(setCellImageWithURL:)]) {
        [cell setCellImageWithURL:[NSURL URLWithString:[_dataSource photoBrowser:self URLStringForImageAtIndex:indexPath.row]]];
    } else {
        [cell setCellImage:[_dataSource photoBrowser:self imageAtIndex:indexPath.row]];
    }
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath
{
    self.displayingDetailedView = !self.isDisplayingDetailedView;
}

#pragma mark - AGPhotoBrowserCellDelegate

- (void)didPanOnZoomableViewForCell:(id<AGPhotoBrowserCellProtocol>)cell withRecognizer:(UIPanGestureRecognizer *)recognizer
{
	[self p_imageViewPanned:recognizer];
}

- (void)didDoubleTapOnZoomableViewForCell:(id<AGPhotoBrowserCellProtocol>)cell
{
	self.displayingDetailedView = !self.isDisplayingDetailedView;
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    if (!self.currentWindow.hidden && !_changingOrientation) {
        [self.overlayView resetOverlayView];
        
        CGPoint targetContentOffset = scrollView.contentOffset;
        
        UICollectionView *collectionView = (UICollectionView *)scrollView;
        NSIndexPath *indexPathOfTopRowAfterScrolling = [collectionView indexPathForItemAtPoint:targetContentOffset];

        [self setupPhotoForIndex:indexPathOfTopRowAfterScrolling.row];
    }
}

- (void)setupPhotoForIndex:(int)index
{
    _currentlySelectedIndex = index;
	    
    if ([self.dataSource respondsToSelector:@selector(photoBrowser:willDisplayActionButtonAtIndex:)]) {
        self.overlayView.actionButton.hidden = ![self.dataSource photoBrowser:self willDisplayActionButtonAtIndex:_currentlySelectedIndex];
    } else {
        self.overlayView.actionButton.hidden = NO;
    }
    
	if ([_dataSource respondsToSelector:@selector(photoBrowser:titleForImageAtIndex:)]) {
		self.overlayView.photoTitle = [_dataSource photoBrowser:self titleForImageAtIndex:_currentlySelectedIndex];
	} else {
        self.overlayView.photoTitle = @"";
    }
	
	if ([_dataSource respondsToSelector:@selector(photoBrowser:descriptionForImageAtIndex:)]) {
		self.overlayView.photoDescription = [_dataSource photoBrowser:self descriptionForImageAtIndex:_currentlySelectedIndex];
	} else {
        self.overlayView.photoDescription = @"";
    }
}


#pragma mark - Public methods

- (void)show
{
    self.previousWindow = [[UIApplication sharedApplication] keyWindow];
    
    self.currentWindow = [[UIWindow alloc] initWithFrame:self.previousWindow.bounds];
    self.currentWindow.windowLevel = UIWindowLevelStatusBar;
    self.currentWindow.hidden = NO;
    self.currentWindow.backgroundColor = [UIColor clearColor];
    [self.currentWindow makeKeyAndVisible];
    [self.currentWindow addSubview:self];
	
	[UIView animateWithDuration:AGPhotoBrowserAnimationDuration
					 animations:^(){
						 self.backgroundColor = [UIColor colorWithWhite:0. alpha:1.];
					 }
					 completion:^(BOOL finished){
						 if (finished) {
							 self.userInteractionEnabled = YES;
							 self.displayingDetailedView = YES;
							 self.photoCollectionView.alpha = 1.;
							 [self.photoCollectionView reloadData];
						 }
					 }];
}

- (void)showFromIndex:(NSInteger)initialIndex
{
	[self show];
	
	if (initialIndex < [_dataSource numberOfPhotosForPhotoBrowser:self]) {
		[self.photoCollectionView scrollToItemAtIndexPath:[NSIndexPath indexPathForRow:initialIndex inSection:0] atScrollPosition:UICollectionViewScrollPositionNone animated:NO];
	}
}

- (void)hideWithCompletion:( void (^) (BOOL finished) )completionBlock
{
	[UIView animateWithDuration:AGPhotoBrowserAnimationDuration
					 animations:^(){
						 self.photoCollectionView.alpha = 0.;
						 self.backgroundColor = [UIColor colorWithWhite:0. alpha:0.];
					 }
					 completion:^(BOOL finished){
						 self.userInteractionEnabled = NO;
                         [self removeFromSuperview];
                         [self.previousWindow makeKeyAndVisible];
                         self.currentWindow.hidden = YES;
                         self.currentWindow = nil;
						 if(completionBlock) {
							 completionBlock(finished);
						 }
					 }];
}


#pragma mark - AGPhotoBrowserOverlayViewDelegate

- (void)sharingView:(AGPhotoBrowserOverlayView *)sharingView didTapOnActionButton:(UIButton *)actionButton
{
	if ([_delegate respondsToSelector:@selector(photoBrowser:didTapOnActionButton:atIndex:)]) {
		[_delegate photoBrowser:self didTapOnActionButton:actionButton atIndex:_currentlySelectedIndex];
	}
}


#pragma mark - Recognizers

- (void)p_imageViewPanned:(UIPanGestureRecognizer *)recognizer
{
	AGPhotoBrowserZoomableView *imageView = (AGPhotoBrowserZoomableView *)recognizer.view;
	
	if (recognizer.state == UIGestureRecognizerStateBegan) {
		// -- Disable table view scrolling
		self.photoCollectionView.scrollEnabled = NO;
		// -- Hide detailed view
		self.displayingDetailedView = NO;
		_startingPanPoint = imageView.center;
		return;
	}
	
	if (recognizer.state == UIGestureRecognizerStateEnded) {
		// -- Enable table view scrolling
		self.photoCollectionView.scrollEnabled = YES;
		// -- Check if user dismissed the view
		CGPoint endingPanPoint = [recognizer translationInView:self];

		UIDeviceOrientation orientation = [[UIDevice currentDevice] orientation];
		CGPoint translatedPoint;
		
        if (UIDeviceOrientationIsPortrait(orientation) || orientation == UIDeviceOrientationFaceUp) {
            translatedPoint = CGPointMake(_startingPanPoint.x - endingPanPoint.y, _startingPanPoint.y);
        } else if (orientation == UIDeviceOrientationLandscapeLeft) {
            translatedPoint = CGPointMake(_startingPanPoint.x + endingPanPoint.x, _startingPanPoint.y);
        } else {
            translatedPoint = CGPointMake(_startingPanPoint.x - endingPanPoint.x, _startingPanPoint.y);
        }
		
		imageView.center = translatedPoint;
		int heightDifference = abs(floor(_startingPanPoint.x - translatedPoint.x));
		
		if (heightDifference <= AGPhotoBrowserThresholdToCenter) {
			// -- Back to original center
			[UIView animateWithDuration:AGPhotoBrowserAnimationDuration
							 animations:^(){
								 self.backgroundColor = [UIColor colorWithWhite:0. alpha:1.];
								 imageView.center = self->_startingPanPoint;
							 } completion:^(BOOL finished){
								 // -- show detailed view?
								 self.displayingDetailedView = YES;
							 }];
		} else {
			// -- Animate out!
			typeof(self) weakSelf __weak = self;
			[self hideWithCompletion:^(BOOL finished){
				typeof(weakSelf) strongSelf __strong = weakSelf;
				if (strongSelf) {
					imageView.center = strongSelf->_startingPanPoint;
				}
			}];
		}
	} else {
		CGPoint middlePanPoint = [recognizer translationInView:self];
		
		UIDeviceOrientation orientation = [[UIDevice currentDevice] orientation];
		CGPoint translatedPoint;
		
        if (UIDeviceOrientationIsPortrait(orientation) || orientation == UIDeviceOrientationFaceUp) {
            translatedPoint = CGPointMake(_startingPanPoint.x - middlePanPoint.y, _startingPanPoint.y);
        } else if (orientation == UIDeviceOrientationLandscapeLeft) {
            translatedPoint = CGPointMake(_startingPanPoint.x + middlePanPoint.x, _startingPanPoint.y);
        } else {
            translatedPoint = CGPointMake(_startingPanPoint.x - middlePanPoint.x, _startingPanPoint.y);
        }
		
		imageView.center = translatedPoint;
		int heightDifference = abs(floor(_startingPanPoint.x - translatedPoint.x));
		CGFloat ratio = (_startingPanPoint.x - heightDifference)/_startingPanPoint.x;
		self.backgroundColor = [UIColor colorWithWhite:0. alpha:ratio];
	}
}


#pragma mark - Private methods

- (void)p_doneButtonTapped:(UIButton *)sender
{
	if ([_delegate respondsToSelector:@selector(photoBrowser:didTapOnDoneButton:)]) {
		self.displayingDetailedView = NO;
		[_delegate photoBrowser:self didTapOnDoneButton:sender];
	}
}


#pragma mark - Orientation change

- (void)statusBarDidChangeFrame:(NSNotification *)notification
{
    // -- Get the device orientation
    UIDeviceOrientation orientation = [[UIDevice currentDevice] orientation];
	if (UIDeviceOrientationIsPortrait(orientation) || UIDeviceOrientationIsLandscape(orientation) || orientation == UIDeviceOrientationFaceUp) {
		_changingOrientation = YES;
		
		CGFloat angleTable = UIInterfaceOrientationAngleOfOrientation(orientation);
		CGFloat angleOverlay = UIInterfaceOrientationAngleOfOrientationForOverlay(orientation);
		CGAffineTransform tableTransform = CGAffineTransformMakeRotation(angleTable);
		CGAffineTransform overlayTransform = CGAffineTransformMakeRotation(angleOverlay);
		
		CGRect tableFrame = [UIScreen mainScreen].bounds;
		CGRect overlayFrame = CGRectZero;
		CGRect doneFrame = CGRectZero;
		
		[self setTransform:tableTransform andFrame:tableFrame forView:self.photoCollectionView];
		
		if (UIDeviceOrientationIsPortrait(orientation) || orientation == UIDeviceOrientationFaceUp) {
			overlayFrame = CGRectMake(0, CGRectGetHeight(tableFrame) - AGPhotoBrowserOverlayInitialHeight, CGRectGetWidth(tableFrame), AGPhotoBrowserOverlayInitialHeight);
			doneFrame = CGRectMake(CGRectGetWidth(tableFrame) - 60 - 10, 15, 60, 32);
		} else if (orientation == UIDeviceOrientationLandscapeLeft) {
			overlayFrame = CGRectMake(0, 0, AGPhotoBrowserOverlayInitialHeight, CGRectGetHeight(tableFrame));
			doneFrame = CGRectMake(CGRectGetWidth(tableFrame) - 32 - 15, CGRectGetHeight(tableFrame) - 10 - 60, 32, 60);
		} else {
			overlayFrame = CGRectMake(CGRectGetWidth(tableFrame) - AGPhotoBrowserOverlayInitialHeight, 0, AGPhotoBrowserOverlayInitialHeight, CGRectGetHeight(tableFrame));
			doneFrame = CGRectMake(15, 10, 32, 60);
		}
		// -- Update overlay
		[self setTransform:overlayTransform andFrame:overlayFrame forView:self.overlayView];
		if (self.overlayView.descriptionExpanded) {
			[self.overlayView resetOverlayView];
		}
		// -- Update done button
		[self setTransform:overlayTransform andFrame:doneFrame forView:self.doneButton];
		
		[self.photoCollectionView reloadData];
		[self.photoCollectionView scrollToItemAtIndexPath:[NSIndexPath indexPathForRow:_currentlySelectedIndex inSection:0] atScrollPosition:UICollectionViewScrollPositionNone animated:NO];

		_changingOrientation = NO;
	}
}

- (void)setTransform:(CGAffineTransform)transform andFrame:(CGRect)frame forView:(UIView *)view
{
	if (!CGAffineTransformEqualToTransform(view.transform, transform)) {
        view.transform = transform;
    }
    if (!CGRectEqualToRect(view.frame, frame)) {
        view.frame = frame;
    }
}

CGFloat UIInterfaceOrientationAngleOfOrientation(UIDeviceOrientation orientation)
{
    CGFloat angle;
    
    switch (orientation) {
        case UIDeviceOrientationPortraitUpsideDown:
            angle = -M_PI_2;
            break;
        case UIDeviceOrientationLandscapeLeft:
            angle = 0;
            break;
        case UIDeviceOrientationLandscapeRight:
            angle = M_PI;
            break;
        default:
            angle = -M_PI_2;
            break;
    }
    
    return angle;
}

CGFloat UIInterfaceOrientationAngleOfOrientationForOverlay(UIDeviceOrientation orientation)
{
    CGFloat angle;
    
    switch (orientation) {
        case UIDeviceOrientationPortraitUpsideDown:
            angle = 0;
            break;
        case UIDeviceOrientationLandscapeLeft:
            angle = M_PI_2;
            break;
        case UIDeviceOrientationLandscapeRight:
            angle = -M_PI_2;
            break;
        default:
            angle = 0;
            break;
    }
    
    return angle;
}

@end
