//
//  AVOutputViewController.m
//  INSCameraSDK-SampleOC
//
//  Created by HkwKelvin on 2019/3/21.
//  Copyright © 2019年 insta360. All rights reserved.
//

#import "AVOutputViewController.h"

#pragma mark FPSCounter
@implementation FPSCounter

- (NSString *)description {
    NSString *fpsString = [NSString stringWithFormat:@"%.2f",_fps];
    NSString *durationString = [NSString stringWithFormat:@"%.2f",_duration];
    
    return [NSString stringWithFormat:@"FPS: %@, Duration: %@",fpsString, durationString];
}

- (void)reset {
    _value = 0;
    _lastCountTimestamp = 0;
    _firstTimestamp = 0;
}

- (BOOL)updateWithTimestamp:(NSTimeInterval)timestamp {
    if (_firstTimestamp == 0) {
        _firstTimestamp = timestamp;
    }
    _duration = timestamp - _firstTimestamp;
    
    _value += 1;
    if (timestamp >= _lastCountTimestamp + _interval) {
        _fps = _value / (timestamp - _lastCountTimestamp);
        _lastCountTimestamp = timestamp;
        _value = 0;
        
        return YES;
    }
    
    return NO;
}

@end

#pragma mark AVOutputViewController (INSCameraAVOutputDelegate)
@implementation AVOutputViewController (AVOutput)

- (void)avOutput:(id<INSCameraAVOutput>)avOutput didOutputAudioPacket:(INSCameraAudioPacket *)audioPacket {
    if ([avOutput isKindOfClass:[INSCameraFlatPanoOutput class]]) {
        NSLog(@"FlatPanoOutput didOutputAudioPacket %g",audioPacket.timestamp);
    }
    
    if ([avOutput isKindOfClass:[INSCameraScreenOutput class]]) {
        NSLog(@"ScreenOutput didOutputAudioPacket %g",audioPacket.timestamp);
    }
    
    // do anything with the audio data here
}

- (void)avOutput:(id<INSCameraAVOutput>)avOutput didOutputVideoFrame:(INSCameraVideoFrame *)videoFrame {
    if ([avOutput isKindOfClass:[INSCameraFlatPanoOutput class]]) {
        if ([self.flatPanoOutputCounter updateWithTimestamp:videoFrame.timestamp]) {
            self.flatPanoDescriptionLabel.text = self.flatPanoOutputCounter.description;
        }
        
        // capture the current frame
        if (self.snapshotButton.isSelected) {
            UIImage *image = [UIImage imageWithPixelBuffer:videoFrame.pixelBuffer];
            self.snapshotImageView.image = image;
            
            self.snapshotButton.selected = NO;
        }
    }
    
    if ([avOutput isKindOfClass:[INSCameraScreenOutput class]]) {
        if ([self.screenOutputCounter updateWithTimestamp:videoFrame.timestamp]) {
            self.screenDescriptionLabel.text = self.screenOutputCounter.description;
        }
    }
}

@end

#pragma mark - AVOutputViewController
@interface AVOutputViewController () <XLFormRowDescriptorViewController>

@property (nonatomic, strong) INSCameraFlatPanoOutput *flatPanoOutput;

@property (nonatomic, strong) INSCameraScreenOutput *screenOutput;

@property (nonatomic, strong) INSCameraPreviewPlayer *previewPlayer;

@property (nonatomic, strong) INSCameraMediaSession *mediaSession;

@property (nonatomic, strong) INSRenderView *renderView;

@end

@implementation AVOutputViewController

@synthesize rowDescriptor;

- (void)dealloc {
    [_mediaSession stopRunningWithCompletion:nil];
    [_previewPlayer.renderView destroyRender];
    [EAGLContext setCurrentContext:[[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3]];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"AV Outputs";
    
    _mediaSession = [[INSCameraMediaSession alloc] init];
    
    _flatPanoOutputCounter = [[FPSCounter alloc] init];
    _screenOutputCounter = [[FPSCounter alloc] init];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(cameraDidConnected:) name:INSCameraDidConnectNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(cameraDidDisconnected:) name:INSCameraDidDisconnectNotification object:nil];
    
    [self setupUI];
    
    if ([INSCameraManager sharedManager].cameraState == INSCameraStateConnected) {
        [self cameraDidConnected:nil];
    }
}

- (void)setupUI {
    _snapshotButton.layer.masksToBounds = YES;
    _snapshotButton.layer.cornerRadius  = 32.f;
    
    INSRenderView *renderView = [[INSRenderView alloc] initWithFrame:self.view.bounds renderType:INSRenderTypeSphericalPanoRender];
    [self.view insertSubview:renderView atIndex:0];
    _renderView = renderView;
}

- (void)cameraDidConnected:(NSNotification *)notification {
    NSString *cameraName = [INSCameraManager sharedManager].currentCamera.name;
    if ([cameraName isEqualToString:kInsta360CameraNameNano]) {
        _renderView.enableGyroStabilizer = NO;
        _mediaSession.expectedAudioSampleRate = INSAudioSampleRate48000Hz;
        _mediaSession.expectedVideoResolution = INSVideoResolution2560x1280x30;
    }
    else {
        _renderView.enableGyroStabilizer = YES;
        _mediaSession.expectedAudioSampleRate = INSAudioSampleRate48000Hz;
        _mediaSession.expectedVideoResolution = INSVideoResolution3840x1920x30;
        
        // if you don't want to enable gyro stabilizer, you may want to rorate the preiview with 90 degree
        // renderView.enableGyroStabilizer = false
        // renderView.render.gyroStabilityOrientation = GLKQuaternionMake(0, 0, 0.7071, 0.7071)
    }
    
    _snapshotButton.enabled = YES;
}

- (void)cameraDidDisconnected:(NSNotification *)notification {
    _snapshotButton.enabled = YES;
}

- (void)updateMediaSession {
    if (!_previewPlayer && !_flatPanoOutput && !_screenOutput) {
        [_mediaSession stopRunningWithCompletion:nil];
        return ;
    }
    
    __weak typeof(self)weakSelf = self;
    if (_mediaSession.running) {
        [_mediaSession commitChangesWithCompletion:^(NSError * _Nullable error) {
            NSLog(@"commitChange %@",error);
            if (error) {
                weakSelf.previewButton.selected = false;
                weakSelf.flatPanoOutputButton.selected = false;
                weakSelf.screenOutputButton.selected = false;
                [weakSelf.mediaSession unplugAll];
            }
        }];
    }
    else {
        [_mediaSession startRunningWithCompletion:^(NSError * _Nullable error) {
            NSLog(@"startRunning %@",error);
            if (error) {
                weakSelf.previewButton.selected = false;
                weakSelf.flatPanoOutputButton.selected = false;
                weakSelf.screenOutputButton.selected = false;
                [weakSelf.mediaSession unplugAll];
            }
        }];
    }
}

#pragma mark Button Action
- (IBAction)handleSwitchPreview:(UIButton *)sender {
    _previewButton.selected = !_previewButton.selected;
    
    if (_previewButton.isSelected) {
        _previewPlayer = [[INSCameraPreviewPlayer alloc] initWithRenderView:_renderView];
        [_mediaSession plug:_previewPlayer];
    }
    else if (_previewPlayer) {
        [_mediaSession unplug:_previewPlayer];
        _previewPlayer = nil;
    }
    
    [self updateMediaSession];
}

- (IBAction)handleSwitchFlatPanoOutput:(UIButton *)sender {
    _flatPanoOutputButton.selected = !_flatPanoOutputButton.selected;
    
    if (_flatPanoOutputButton.isSelected) {
        INSVideoResolution resolution = _mediaSession.expectedVideoResolution;
        _flatPanoOutput = [[INSCameraFlatPanoOutput alloc] initWithOutputWidth:resolution.width
                                                                  outputHeight:resolution.height];
        [_flatPanoOutput setDelegate:self onDispatchQueue:nil];
        
        /*
         *  set output pixel format to kCVPixelFormatType_32BGRA
         *  if you want to receive the video in bgra instead of NV12 format
         *  flatPanoOutput?.outputPixelFormat = kCVPixelFormatType_32BGRA
         */
        [_mediaSession plug:_flatPanoOutput];
        [_flatPanoOutputCounter reset];
    }
    else if (_flatPanoOutput) {
        [_mediaSession unplug:_flatPanoOutput];
        _flatPanoOutput = nil;
    }
    
    [self updateMediaSession];
}

- (IBAction)handleSwitchScreenOutptut:(UIButton *)sender {
    _screenOutputButton.selected = !_screenOutputButton.selected;
    
    if (_screenOutputButton.isSelected) {
        CGSize size = self.view.bounds.size;
        _screenOutput = [[INSCameraScreenOutput alloc] initWithRenderView:_renderView
                                                              outputWidth:size.width
                                                             outputHeight:size.height
                                                        outputPixelFormat:kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                                                          outputFrameRate:30
                                                              enableAudio:NO];
        [_screenOutput setDelegate:self onDispatchQueue:nil];
        [_mediaSession plug:_screenOutput];
        
        [_screenOutputCounter reset];
    }
    else if (_screenOutput) {
        [_mediaSession unplug:_screenOutput];
        _screenOutput = nil;
    }
    
    [self updateMediaSession];
}

- (IBAction)handleSnapshot:(UIButton *)sender {
    if (_snapshotButton.isSelected) {
        return ;
    }
    _snapshotButton.selected = YES;
}

- (IBAction)setHighExposure:(UIButton *)sender {
    INSPhotographyOptions *options = [INSPhotographyOptions new];
    options.whiteBalanceValue = 9000;
    options.exposureBias = 0.0;
    //图片需要设置stillExposure和videoExposure，视频只需要设置videoExposure
//    options.stillExposure = [INSCameraExposureOptions new];
    options.videoExposure = [INSCameraExposureOptions new];
    options.videoExposure.program = INSCameraExposureProgramManual;
    options.videoExposure.iso = 1600;
    options.videoExposure.shutterSpeed = CMTimeMake(1, 30);
    //设置成片参数
    [[INSCameraManager socketManager].commandManager setPhotographyOptions:options forFunctionMode: INSCameraFunctionModeNormalVideo types:@[@(INSPhotographyOptionsTypeVideoExposureOptions), @(INSPhotographyOptionsTypeWhiteBalanceValue)] completion:^(NSError * _Nullable error, NSArray<NSNumber *> * _Nullable successTypes) {
        NSLog(@"NormalVideo, error：%@", error);
    }];
    
    //设置预览流参数
    [[INSCameraManager socketManager].commandManager setPhotographyOptions:options forFunctionMode: INSCameraFunctionModeLiveStream types:@[@(INSPhotographyOptionsTypeVideoExposureOptions), @(INSPhotographyOptionsTypeWhiteBalanceValue)] completion:^(NSError * _Nullable error, NSArray<NSNumber *> * _Nullable successTypes) {
        NSLog(@"LiveStream, error：%@", error);
    }];
}

- (IBAction)setLowExposure:(UIButton *)sender {
    INSPhotographyOptions *options = [INSPhotographyOptions new];
    options.whiteBalanceValue = 2000;
    options.exposureBias = 0.0;
    //图片需要设置stillExposure和videoExposure，视频只需要设置videoExposure
//    options.stillExposure = [INSCameraExposureOptions new];
    options.videoExposure = [INSCameraExposureOptions new];
    options.videoExposure.program = INSCameraExposureProgramManual;
    options.videoExposure.iso = 400;
    options.videoExposure.shutterSpeed = CMTimeMake(1, 120);
    //设置成片参数
    [[INSCameraManager socketManager].commandManager setPhotographyOptions:options forFunctionMode: INSCameraFunctionModeNormalVideo types:@[@(INSPhotographyOptionsTypeVideoExposureOptions), @(INSPhotographyOptionsTypeWhiteBalanceValue)] completion:^(NSError * _Nullable error, NSArray<NSNumber *> * _Nullable successTypes) {
        NSLog(@"NormalVideo, error：%@", error);
    }];
    
    //设置预览流参数
    [[INSCameraManager socketManager].commandManager setPhotographyOptions:options forFunctionMode: INSCameraFunctionModeLiveStream types:@[@(INSPhotographyOptionsTypeVideoExposureOptions), @(INSPhotographyOptionsTypeWhiteBalanceValue)] completion:^(NSError * _Nullable error, NSArray<NSNumber *> * _Nullable successTypes) {
        NSLog(@"LiveStream, error：%@", error);
    }];
}

@end
