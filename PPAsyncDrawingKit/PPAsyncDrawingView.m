//
//  PPAsyncDrawingView.m
//  PPAsyncDrawingKit
//
//  Created by DSKcpp on 16/6/29.
//  Copyright © 2016年 DSKcpp. All rights reserved.
//

#import "PPAsyncDrawingView.h"

static BOOL asyncDrawingDisabled = NO;

@interface PPAsyncDrawingView () @end

@implementation PPAsyncDrawingView

+ (BOOL)asyncDrawingDisabledGlobally
{
    return asyncDrawingDisabled;
}

+ (void)setDisablesAsyncDrawingGlobally:(BOOL)asyncDrawingDisabledGlobally
{
    asyncDrawingDisabled = asyncDrawingDisabledGlobally;
}

+ (Class)layerClass
{
    return [PPAsyncDrawingViewLayer class];
}

- (instancetype)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame]) {
        self.drawingPolicy = 0;
        self.dispatchPriority = 0;
        self.opaque = NO;
        self.layer.contentsScale = [UIScreen mainScreen].scale;
        if ([self.layer isKindOfClass:[PPAsyncDrawingViewLayer class]]) {
            self.drawingLayer = (PPAsyncDrawingViewLayer *)self.layer;
        }
    }
    return self;
}

- (CGContextRef)newCGContextForLayer:(CALayer *)layer
{
    return nil;
}

- (NSDictionary *)currentDrawingUserInfo
{
    return nil;
}

- (void)setNeedsDisplayAsync
{
    [self setContentsChangedAfterLastAsyncDrawing:YES];
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect
{
    [self drawingWillStartAsynchronously:NO];
    [self drawInRect:rect withContext:UIGraphicsGetCurrentContext() asynchronously:NO userInfo:[self currentDrawingUserInfo]];
    [self drawingDidFinishAsynchronously:NO success:YES];
}

- (void)displayLayer:(CALayer *)layer
{
    if (layer) {
        [self _displayLayer:(PPAsyncDrawingViewLayer *)layer rect:layer.bounds drawingStarted:^(BOOL async) {
            [self drawingWillStartAsynchronously:async];
        } drawingFinished:^(BOOL async, BOOL success) {
            [self drawingDidFinishAsynchronously:async success:success];
        } drawingInterrupted:^(BOOL async, BOOL success) {
            [self drawingDidFinishAsynchronously:async success:success];
        }];
    }
}

- (void)drawingWillStartAsynchronously:(BOOL)async { }

- (void)drawingDidFinishAsynchronously:(BOOL)async success:(BOOL)success { }

- (void)_displayLayer:(PPAsyncDrawingViewLayer *)layer rect:(CGRect)rect drawingStarted:(void (^)(BOOL))drawingStarted drawingFinished:(void (^)(BOOL, BOOL))drawingFinished drawingInterrupted:(void (^)(BOOL, BOOL))drawingInterrupted
{
    BOOL asynchronously = NO;
    if ([layer drawsCurrentContentAsynchronously]) {
        if (![PPAsyncDrawingView asyncDrawingDisabledGlobally]) {
            asynchronously = YES;
        }
    }
    _padingRedraw = NO;
    [layer increaseDrawingCount];
    NSInteger drawCount = [layer drawingCount];
    NSDictionary *userInfo = [self currentDrawingUserInfo];
    BOOL (^isCancel)() = ^BOOL() {
        return drawCount != [layer drawingCount];
    };
    dispatch_queue_t queue;
    if (asynchronously) {
        if (!layer.reserveContentsBeforeNextDrawingComplete) {
            [layer setContents:nil];
        }
        queue = self.drawQueue;
    } else if ([NSThread isMainThread]) {
        queue = dispatch_get_main_queue();
    } else {
        queue = dispatch_get_main_queue();
    }
    dispatch_async(queue, ^{
        if (drawingStarted) {
            drawingStarted(YES);
        }
        if (isCancel()) {
            dispatch_async(dispatch_get_main_queue(), ^{
                drawingFinished(YES, NO);
            });
            return;
        }
        CGSize size = layer.bounds.size;
        CGFloat scale = layer.contentsScale;
        UIGraphicsBeginImageContextWithOptions(size, layer.isOpaque, scale);
        CGContextRef context = UIGraphicsGetCurrentContext();
        CGContextSaveGState(context);
        UIColor *backgroundColor = self.backgroundColor;
        if (backgroundColor) {
            CGContextSetFillColorWithColor(context, backgroundColor.CGColor);
            CGContextFillRect(context, CGRectMake(0, 0, size.width * scale, size.height * scale));
        }
        [self drawInRect:CGRectMake(0, 0, size.width, size.height) withContext:context asynchronously:asynchronously userInfo:userInfo];
        CGContextRestoreGState(context);
        UIImage *image = [UIImage imageWithCGImage:CGBitmapContextCreateImage(context)];
        UIGraphicsEndImageContext();
        if (isCancel()) {
            dispatch_async(dispatch_get_main_queue(), ^{
                drawingFinished(YES, NO);
            });
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (isCancel()) {
                drawingFinished(YES, NO);
            } else {
                self.layer.contents = (__bridge id _Nullable)(image.CGImage);
                drawingFinished(YES, YES);
            }
        });
    });
}

- (BOOL)drawInRect:(CGRect)rect withContext:(CGContextRef)context asynchronously:(BOOL)async
{
    return YES;
}

- (BOOL)drawInRect:(CGRect)rect withContext:(CGContextRef)context asynchronously:(BOOL)async userInfo:(NSDictionary *)userInfo
{
    return [self drawInRect:rect withContext:context asynchronously:async];
}

- (void)interruptDrawingWhenPossible
{
    [self.drawingLayer increaseDrawingCount];
}

- (void)redraw
{
    [self displayLayer:self.layer];
}

- (BOOL)respondsToSelector:(SEL)aSelector
{
    if (!self.alwaysUsesOffscreenRendering) {
        if ([NSStringFromSelector(aSelector) isEqual:@"displayLayer:"]) {
            if (self.drawingPolicy != 1) {
                return YES;
            }
            return NO;
        } else {
            return [super respondsToSelector:aSelector];
        }
    } else {
        return [super respondsToSelector:aSelector];
    }
}

- (void)dealloc
{
    if (_dispatchDrawQueue) {
        _dispatchDrawQueue = nil;
    }
}

#pragma mark - getter and setter
- (NSTimeInterval)fadeDuration
{
    return self.drawingLayer.fadeDuration;
}

- (void)setFadeDuration:(NSTimeInterval)fadeDuration
{
    [self.drawingLayer setFadeDuration:fadeDuration];
}

- (BOOL)reserveContentsBeforeNextDrawingComplete
{
    return self.drawingLayer.reserveContentsBeforeNextDrawingComplete;
}

- (void)setReserveContentsBeforeNextDrawingComplete:(BOOL)reserveContentsBeforeNextDrawingComplete
{
    [self.drawingLayer setReserveContentsBeforeNextDrawingComplete:reserveContentsBeforeNextDrawingComplete];
}

- (BOOL)contentsChangedAfterLastAsyncDrawing
{
    return self.drawingLayer.contentsChangedAfterLastAsyncDrawing;
}

- (void)setContentsChangedAfterLastAsyncDrawing:(BOOL)contentsChangedAfterLastAsyncDrawing
{
    [self.drawingLayer setContentsChangedAfterLastAsyncDrawing:contentsChangedAfterLastAsyncDrawing];
}

- (NSInteger)drawingPolicy
{
    return self.drawingLayer.drawingPolicy;
}

- (void)setDrawingPolicy:(NSInteger)drawingPolicy
{
    [self.drawingLayer setDrawingPolicy:drawingPolicy];
}

- (void)setDrawingCount:(NSUInteger)drawingCount
{
    [self.drawingLayer setDrawingPolicy:drawingCount];
}

- (NSUInteger)drawingCount
{
    return self.drawingLayer.drawingCount;
}

- (void)setDispatchDrawQueue:(dispatch_queue_t)dispatchDrawQueue
{
    if (!self.serializesDrawingOperations) {
        [self _setDispatchDrawQueue:dispatchDrawQueue];
    }
}

- (void)_setDispatchDrawQueue:(dispatch_queue_t)dispatchDrawQueue
{
    if (self.dispatchDrawQueue) {
        self.dispatchDrawQueue = nil;
    }
    self.dispatchDrawQueue = dispatchDrawQueue;
}

- (void)setSerializesDrawingOperations:(BOOL)serializesDrawingOperations
{
    if (_serializesDrawingOperations == serializesDrawingOperations) {
        return;
    }
    _serializesDrawingOperations = serializesDrawingOperations;
    if (serializesDrawingOperations) {
        dispatch_queue_t queue = dispatch_queue_create("PPAsyncDrawingViewSerializeQueue", 0);
        dispatch_set_target_queue(queue, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0));
        [self _setDispatchDrawQueue:queue];
    }
}

- (dispatch_queue_t)drawQueue
{
    if (self.dispatchDrawQueue) {
        return self.dispatchDrawQueue;
    } else {
        return dispatch_get_global_queue(self.dispatchPriority, 0);
    }
}

@end

@implementation PPAsyncDrawingViewLayer

- (void)increaseDrawingCount
{
    _drawingCount += 1;
}

- (void)setNeedsDisplay
{
    [self increaseDrawingCount];
    [super setNeedsDisplay];
}

- (void)setNeedsDisplayInRect:(CGRect)rect
{
    [self increaseDrawingCount];
    [super setNeedsDisplayInRect:rect];
}

- (BOOL)drawsCurrentContentAsynchronously
{
    NSUInteger drawingPolicy = self.drawingPolicy;
    if (drawingPolicy == 2) {
        return YES;
    } else if (drawingPolicy == 1) {
        return NO;
    } else {
        return self.contentsChangedAfterLastAsyncDrawing;
    }
}

@end
