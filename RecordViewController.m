//
//  RecordViewController.m
//  INSCameraSDK-SampleOC
//
//  Created by HkwKelvin on 2019/3/21.
//  Copyright © 2019年 insta360. All rights reserved.
//

#import "RecordViewController.h"

#import <INSCameraSDK/INSCameraSDK.h>
#import "HousingResourceViewController.h"
#import "MobileAlbumViewController.h"
#import "UIViewController+AlertController.h"
//#import "LiveConfigurationViewController.h"
#import "PlayerViewController.h"
#import "HttpConnection.h"
#import "CLRotateAnimationView.h"

#import <INSCoreMedia/INSCoreMedia.h>
#import "CLRotateAnimationView.h"
#import "CLRoundAnimationView.h"
#import "GCDTimer.h"
#import "PhotoFileModel.h"
#import "PhotoAlbumManger.h"
//inline static void dispatch_async_main(dispatch_block_t block)
//{
//    dispatch_async(dispatch_get_main_queue(), block);
//}
//
//inline static void dispatch_async_default(dispatch_block_t block)
//{
//    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), block);
//}

@interface RecordViewController () <INSCameraPreviewPlayerDelegate>

@property (nonatomic, strong) INSCameraMediaSession *mediaSession;

@property (nonatomic, strong) INSCameraPreviewPlayer *previewPlayer;

@property (nonatomic, strong) INSCameraStorageStatus *storageState;
@property (nonatomic, strong) INSCameraBatteryStatus *batteryStatus;

@property (nonatomic,strong) INSCameraStorageStatus *cardState;
@property (nonatomic,strong) UIButton *albumBtn;

//@property (nonatomic, strong) LiveConfigurationViewController *configurationVC;

@property (nonatomic, assign) INSVideoEncode videoEncode;
@property (nonatomic, strong) UILabel *memoryLabel;
@property (nonatomic, strong) UILabel *electricityLabel;
@property (nonatomic, strong) UIView *electricityView;
@property (nonatomic, strong) UIImageView *electricityImageView;
@property (nonatomic, strong) NSTimer * timer;
@property (nonatomic,strong) UIButton *connectBtn;
@property (nonatomic,assign) bool isSuccess;//连接成功

@property (nonatomic,assign) int timeNum;//连接时间
@end

@implementation RecordViewController

- (UIImage *)stitchImage:(UIImage *)image extraInfo:(INSExtraInfo *)extraInfo outputSize:(CGSize)outputSize {
    INSFlatPanoOffscreenRender *render = [[INSFlatPanoOffscreenRender alloc] initWithRenderWidth:outputSize.width height:outputSize.height];
    render.eulerAdjust = extraInfo.metadata.euler;
    render.offset = extraInfo.metadata.offset;
    
    render.gyroStabilityOrientation = GLKQuaternionIdentity;
    if (extraInfo.gyroData) {
        INSGyroPBPlayer *gyroPlayer = [[INSGyroPBPlayer alloc] initWithPBGyroData:extraInfo.gyroData];
        GLKQuaternion orientation = [gyroPlayer getImageOrientationWithRenderType:INSRenderTypeFlatPanoRender];
        render.gyroStabilityOrientation = orientation;
    }
    
    [render setRenderImage:image];
    return [render renderToImage];
}

- (void)appendLog:(NSString *)text {
    NSLog(@"==log:%@", text);
}

- (void)dealloc {
    [_mediaSession stopRunningWithCompletion:^(NSError * _Nullable error) {
        NSLog(@"stop media session with err: %@", error);
    }];
    
    [[INSCameraManager usbManager] removeObserver:self forKeyPath:@"cameraState"];
    [[INSCameraManager socketManager] removeObserver:self forKeyPath:@"cameraState"];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.isSuccess = NO;
    
    [[INSCameraManager usbManager] addObserver:self forKeyPath:@"cameraState" options:NSKeyValueObservingOptionNew context:nil];
    [[INSCameraManager socketManager] addObserver:self forKeyPath:@"cameraState" options:NSKeyValueObservingOptionNew context:nil];
    
    _videoEncode = INSVideoEncodeH264;
    _mediaSession = [[INSCameraMediaSession alloc] init];
    [self addBoxbgViewanimation];
    [self setupRenderView];

    
    self.timer = [NSTimer scheduledTimerWithTimeInterval:2 target:self selector:@selector(timerAction) userInfo:nil repeats:YES];
      [[NSRunLoop currentRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
        [EAGLContext setCurrentContext:[[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3]];
 
    if ([INSCameraManager sharedManager].currentCamera) {
        __weak typeof(self)weakSelf = self;
        [self fetchOptionsWithCompletion:^{
            [weakSelf updateConfiguration];
            [weakSelf runMediaSession];
        }];
    }
}

- (void)updateConfiguration {
//    _mediaSession.expectedVideoResolution = INSVideoResolution1920x960x30;
//
//    // secondary stream resolution
//    _mediaSession.expectedVideoResolutionSecondary = INSVideoResolution960x480x30;
//
//    // use main stream or secondary stream to preview
//    _mediaSession.previewStreamType = INSPreviewStreamTypeSecondary;
//
//    // audio sample rate
//    _mediaSession.expectedAudioSampleRate = INSAudioSampleRate48000Hz;
//
//    // preview stream encode
//    _mediaSession.videoStreamEncode = INSVideoEncodeH264;
//
//    // gyroscope correction mode
//    // If you are in panoramic preview, use `INSGyroPlayModeDefault`.
//    // If you are in wide angle preview, use `INSGyroPlayModeFootageMotionSmooth`.
//    _mediaSession.gyroPlayMode = INSGyroPlayModeDefault;
    
    _mediaSession.videoStreamEncode = INSVideoEncodeH264;

    _mediaSession.gyroPlayMode = INSGyroPlayModeNone;
}

- (void)setupRenderView {
    
    [[DHHUDManager sharedManager] showLoadingWithMessage:@"Vr環境を生成しています" view:self.view];
    
    CGFloat height = CGRectGetHeight(self.view.bounds);
    CGRect frame = CGRectMake(0, 0, CGRectGetWidth(self.view.bounds), height);
    _previewPlayer = [[INSCameraPreviewPlayer alloc] initWithFrame:frame
                                                        renderType:INSRenderTypeSphericalPanoRender];
    [_previewPlayer playWithGyroTimestampAdjust:30.f];
    _previewPlayer.delegate = self;
    [self.view addSubview:_previewPlayer.renderView];
    
    [_mediaSession plug:self.previewPlayer];
    
    // adjust field of view parameters
    NSString *offset = [INSCameraManager sharedManager].currentCamera.settings.mediaOffset;
    if (offset) {
        NSInteger rawValue = [[INSLensOffset alloc] initWithOffset:offset].lensType;
        if (rawValue == INSLensTypeOneR577Wide || rawValue == INSLensTypeOneR283Wide) {
            _previewPlayer.renderView.enablePanGesture = NO;
            _previewPlayer.renderView.enablePinchGesture = NO;
            
            _previewPlayer.renderView.render.camera.xFov = 37;
            _previewPlayer.renderView.render.camera.distance = 700;
        }
    }

    UIButton *connectBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [connectBtn setImage:[UIImage imageNamed:@"home_takepicBtn"] forState:UIControlStateNormal];
    connectBtn.layer.masksToBounds = YES;
    connectBtn.layer.cornerRadius = 40;
    
    [connectBtn addTarget:self action:@selector(ClicktakePicture2) forControlEvents:UIControlEventTouchUpInside];
    connectBtn.hidden = YES;
    [self.view addSubview:connectBtn];
    self.connectBtn = connectBtn;
    
    [connectBtn mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerX.equalTo(self.view);
        make.bottom.equalTo(self.view).offset(-82);
        make.height.width.mas_offset(80);
    }];
    
    UIButton *hudBtn = [[UIButton alloc]init];
    hudBtn.backgroundColor = [UIColor whiteColor];
    hudBtn.layer.masksToBounds = YES;
    hudBtn.layer.cornerRadius = 20;
    [self.view addSubview:hudBtn];
    [hudBtn mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerX.equalTo(connectBtn);
        make.height.equalTo(@(40));
        make.width.equalTo(@(40));
        make.top.equalTo(connectBtn.mas_bottom).offset(20);
    }];
    [hudBtn addTarget:self action:@selector(switchMode) forControlEvents:UIControlEventTouchUpInside];
    hudBtn.hidden = YES;
    
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    [btn setImage:[UIImage imageNamed:@"home_takepicBtn2"] forState:UIControlStateNormal];
    [self.view addSubview:btn];
//    btn.backgroundColor = [UIColor whiteColor];
    [btn mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerY.equalTo(connectBtn);
        make.height.width.mas_offset(30);
        make.left.equalTo(self.view).offset(40);
    }];
    btn.layer.cornerRadius = 30/2;
    btn.layer.masksToBounds= YES;
    [btn addTarget:self action:@selector(pushHousingResource) forControlEvents:UIControlEventTouchUpInside];
    self.albumBtn = btn;
    
    UIImageView *memoryImageView = [[UIImageView alloc]init];
    memoryImageView.image =[UIImage imageNamed:@"home_memory"];
    [self.view addSubview:memoryImageView];
    [memoryImageView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.view).offset(60);
        make.right.equalTo(self.view).offset(-120);
        make.width.equalTo(@(18));
        make.height.equalTo(@(18));
    }];
    
    UILabel *memoryLabel = [[UILabel alloc]init];
    memoryLabel.text = @"12.04G";
    memoryLabel.font = [UIFont systemFontOfSize:12];
    memoryLabel.textColor =[UIColor colorWithHexString:@"#F2F2F2"];
    [self.view addSubview:memoryLabel];
    [memoryLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerY.equalTo(memoryImageView);
        make.left.equalTo(memoryImageView.mas_right).offset(2);
    }];
    self.memoryLabel = memoryLabel;
    
    UIImageView *electricityImageView = [[UIImageView alloc]init];
    electricityImageView.contentMode = UIViewContentModeScaleAspectFit;
    electricityImageView.image =[UIImage imageNamed:@"home_electricity"];
    [self.view addSubview:electricityImageView];
    [electricityImageView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.view).offset(60);
        make.right.equalTo(self.view).offset(-55);
        make.width.equalTo(@(18));
        make.height.equalTo(@(18));
    }];
    self.electricityImageView = electricityImageView;
    
    UIView *electricityView = [[UIView alloc]init];
    electricityView.backgroundColor = [UIColor whiteColor];
    [electricityImageView addSubview:electricityView];
    [electricityView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerY.equalTo(electricityImageView);
        make.left.equalTo(electricityImageView).offset(2);
        make.height.equalTo(@(6));
        make.width.equalTo(@(13));
    }];
    self.electricityView = electricityView;
    
    UILabel *electricityLabel = [[UILabel alloc]init];
    electricityLabel.text = @"100%";
    electricityLabel.font = [UIFont systemFontOfSize:12];
    electricityLabel.textColor =[UIColor colorWithHexString:@"#F2F2F2"];
    [self.view addSubview:electricityLabel];
    [electricityLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerY.equalTo(electricityImageView);
        make.left.equalTo(electricityImageView.mas_right).offset(2);
    }];
    self.electricityLabel = electricityLabel;
    
    UIImageView *backImageView = [[UIImageView alloc]init];
    backImageView.image = [UIImage imageNamed:@"home_witheBack"];
    [self.view addSubview:backImageView];
    [backImageView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerY.equalTo(electricityLabel);
        make.left.equalTo(self.view).offset(16);
        make.width.equalTo(@(25));
        make.height.equalTo(@(25));
    }];
    
    UIButton *leftBtn = [[UIButton alloc]init];
    [self.view addSubview:leftBtn];
    [leftBtn mas_makeConstraints:^(MASConstraintMaker *make) {
        make.center.equalTo(backImageView);
        make.width.equalTo(@(50));
        make.height.equalTo(@(30));
    }];
    [leftBtn addTarget:self action:@selector(leftAction) forControlEvents:UIControlEventTouchUpInside];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{

        [self timerAction];
    });

    UIButton *disconnectBtn = [[UIButton alloc]init];
    [self.view addSubview:disconnectBtn];
    [disconnectBtn mas_makeConstraints:^(MASConstraintMaker *make) {

        make.centerY.equalTo(connectBtn);
        make.height.width.mas_offset(30);
        make.right.equalTo(self.view).offset(-40);
    }];
    [disconnectBtn setImage:[UIImage imageNamed:@"999"] forState:UIControlStateNormal];
    [disconnectBtn setTitleColor:[UIColor colorWithHexString:@"#F53F3F"] forState:UIControlStateNormal];

    [disconnectBtn addTarget:self action:@selector(closeConnect) forControlEvents:UIControlEventTouchUpInside];
    //查询剩余容量
    [self usedSpaceAndfreeSpace];
}

-(void)leftAction {
    [self.navigationController popViewControllerAnimated:YES];
    
}

-(void)switchMode {
    [self takeHDR];
}

//背景星星动画
-(void)addBoxbgViewanimation{
    
    UIImageView *bgImgView = [[UIImageView alloc]initWithFrame:CGRectMake(0, 0, WIDTH_SCREEN, HEIGHT_SCREEN)];
    bgImgView.image = [UIImage imageNamed:@"home_xingkong_bg"];
//    self.bgImgView.backgroundColor = blueColor;
    [self.view addSubview:bgImgView];
    
    UIImageView *BoxbgView = [[UIImageView alloc]initWithFrame:CGRectMake(0, 60, WIDTH_SCREEN, WIDTH_SCREEN*261/375)];
    
    NSArray *imgArray = @[[UIImage imageNamed:@"Boxbganimation_0"], [UIImage imageNamed:@"Boxbganimation_1"], [UIImage imageNamed:@"Boxbganimation_2"],[UIImage imageNamed:@"Boxbganimation_3"],[UIImage imageNamed:@"Boxbganimation_4"],[UIImage imageNamed:@"Boxbganimation_5"],[UIImage imageNamed:@"Boxbganimation_6"],[UIImage imageNamed:@"Boxbganimation_7"],[UIImage imageNamed:@"Boxbganimation_8"],[UIImage imageNamed:@"Boxbganimation_9"]];
    BoxbgView.animationImages = imgArray;
    BoxbgView.animationDuration = 5.0;
    BoxbgView.animationRepeatCount = 0;
    [BoxbgView startAnimating];
    [self.view addSubview:BoxbgView];
    
}

-(void)takeHDR {
    __weak typeof(self)weakSelf = self;

    [[DHHUDManager sharedManager] showLoadingWithMessage:@"Vr環境を生成しています" view:self.view];
    
    INSTakePictureOptions *options = [[INSTakePictureOptions alloc] init];
    options.mode = INSPhotoModeAeb;
    options.AEBEVBias = @[@(0), @(-2), @(-1), @(1), @(2)];
    options.generateManually = YES;
    [[INSCameraManager sharedManager].commandManager takePictureWithOptions:options completion:^(NSError * _Nullable error, INSCameraPhotoInfo * _Nullable photoInfo) {
        NSLog(@"take hdr picture: %@, %@",photoInfo.uri,photoInfo.hdrUris);
        
        if (![IsBlankStr isBlankString:photoInfo.uri]) {//有照片
            [[NSNotificationCenter defaultCenter]postNotificationName:@"UpdatePictureNotification" object:nil];
            
//            NSURL *url = [NSURL URLWithString:photoInfo.uri];
            NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://192.168.42.1:80%@",photoInfo.uri]];
            
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{

                [weakSelf.mediaSession stopRunningWithCompletion:^(NSError * _Nullable error) {
                    [weakSelf runMediaSession];
                }];
                
                INSImageInfoParser *parser = [[INSImageInfoParser alloc] initWithURL:url];
                if ([parser open]) {
                    NSData *data = [NSData dataWithContentsOfURL:url];
                    UIImage *thumbnail = [[UIImage alloc] initWithData:data];
                    
                    CGSize outputSize = parser.extraInfo.metadata.dimension;
                    UIImage *output = [weakSelf stitchImage:thumbnail extraInfo:parser.extraInfo outputSize:outputSize];
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [[DHHUDManager sharedManager] dismissHUDImmediatelyWithView:weakSelf.view];
                       
                        // preview
                        PlayerViewController *controller = [[PlayerViewController alloc] initWithImage:output];
                        [controller vcAction];
                        [weakSelf.navigationController pushViewController:controller animated:YES];
                    });
                }
            });

        }
    }];
}


-(void)ClicktakePicture{
//    Vr環境を生成しています

    [[DHHUDManager sharedManager] showLoadingWithMessage:@"Vr環境を生成しています" view:self.view];

    __weak typeof(self)weakSelf = self;
    INSExtraInfo *extraInfo = [[INSExtraInfo alloc] init];
    INSTakePictureOptions *options = [[INSTakePictureOptions alloc] initWithExtraInfo:extraInfo];
    [[INSCameraManager sharedManager].commandManager takePictureWithOptions:options completion:^(NSError * _Nullable error, INSCameraPhotoInfo * _Nullable photoInfo) {
        NSLog(@"take picture uri: %@, error: %@",photoInfo.uri,error);
//        [weakSelf showAlertWith:@"takePicture" message:[NSString stringWithFormat:@"%@",photoInfo.uri]];
        if (error) {
            [[DHHUDManager sharedManager] dismissWithError:error.description];
            
            return ;
        }
        if (![IsBlankStr isBlankString:photoInfo.uri]) {//有照片
            
            [[NSNotificationCenter defaultCenter]postNotificationName:@"UpdatePictureNotification" object:nil];
            
//            NSURL *url = [NSURL URLWithString:photoInfo.uri];
            NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://192.168.42.1:80%@",photoInfo.uri]];
            
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{

                [weakSelf.mediaSession stopRunningWithCompletion:^(NSError * _Nullable error) {
                    [weakSelf runMediaSession];
                }];
                
                INSImageInfoParser *parser = [[INSImageInfoParser alloc] initWithURL:url];
                if ([parser open]) {
                    NSData *data = [NSData dataWithContentsOfURL:url];
                    UIImage *thumbnail = [[UIImage alloc] initWithData:data];
                    
                    CGSize outputSize = parser.extraInfo.metadata.dimension;
                    UIImage *output = [weakSelf stitchImage:thumbnail extraInfo:parser.extraInfo outputSize:outputSize];
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [[DHHUDManager sharedManager] dismissHUDImmediatelyWithView:weakSelf.view];
                       
                        // preview
                        PlayerViewController *controller = [[PlayerViewController alloc] initWithImage:output];
                        [controller vcAction];
                        [weakSelf.navigationController pushViewController:controller animated:YES];
                    });
                }
            });

        }
    }];

}

-(void)ClicktakePicture2{
//    Vr環境を生成しています
    __weak typeof(self)weakSelf = self;

    [[DHHUDManager sharedManager] showLoadingWithMessage:@"Vr環境を生成しています" view:self.view];

    INSExtraInfo *extraInfo = [[INSExtraInfo alloc] init];
    INSTakePictureOptions *options = [[INSTakePictureOptions alloc] initWithExtraInfo:extraInfo];
    
    [[INSCameraManager sharedManager].commandManager takePictureWithoutStoringWithOptions:options completion:^(NSError * _Nullable error, NSData * _Nullable photoData) {
        
        INSImageInfoParser *parser = [[INSImageInfoParser alloc] initWithData:photoData];

        if (parser.open) {
            UIImage *thumbnail = [[UIImage alloc] initWithData:photoData];
            
            CGSize outputSize = parser.extraInfo.metadata.dimension;
            UIImage *output = [self stitchImage:thumbnail extraInfo:parser.extraInfo outputSize:outputSize];
            
            [[PhotoAlbumManger sharedManager] saveimageWithPicTitle:@"Home360" withdownloadImage:output withsuccess:^(NSString * _Nonnull response) {
                

                //如果保存成功， 把内存卡里的 那个删掉
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[DHHUDManager sharedManager] dismissHUDImmediatelyWithView:weakSelf.view];

                    [self showTitleString:@"保存に成功しました"];
                    [self buttonAnimation:self.albumBtn];
                    
                    [self.albumBtn setImage:output forState:UIControlStateNormal];
                });

            } failed:^(NSInteger typeod) {

                dispatch_async(dispatch_get_main_queue(), ^{
                    
                    [[DHHUDManager sharedManager] dismissHUDImmediatelyWithView:weakSelf.view];

                    [self showTitleString:@"保存に失敗しました"];
                });

            }];
        }
            
            
    }];
    
    
}

//按钮出现时的动画效果

-(void)buttonAnimation:(UIButton *)sender {
    
    CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:@"transform"];
    
    
    
    CATransform3D scale1 = CATransform3DMakeScale(0.5, 0.5, 1);
    
    CATransform3D scale2 = CATransform3DMakeScale(1.2, 1.2, 1);
    
    CATransform3D scale3 = CATransform3DMakeScale(0.9, 0.9, 1);
    
    CATransform3D scale4 = CATransform3DMakeScale(1.0, 1.0, 1);
    
    
    
    NSArray *frameValues = [NSArray arrayWithObjects:
                            
                            [NSValue valueWithCATransform3D:scale1],
                            
                            [NSValue valueWithCATransform3D:scale2],
                            [NSValue valueWithCATransform3D:scale3],
                            
                            [NSValue valueWithCATransform3D:scale4],
                            nil];
    
    [animation setValues:frameValues];
    
    
    NSArray *frameTimes = [NSArray arrayWithObjects:
                           
                           [NSNumber numberWithFloat:0.0],
                           
                           [NSNumber numberWithFloat:0.5],
                           
                           [NSNumber numberWithFloat:0.9],
                           
                           [NSNumber numberWithFloat:1.0],
                           
                           nil];
    
    [animation setKeyTimes:frameTimes];
    
    
    
    animation.fillMode = kCAFillModeForwards;
    
    animation.duration = 0.3f;
    
    
    
    [sender.layer addAnimation:animation forKey:@"DSPopUpAnimation"];
    
}



//获取空间存储状态
- (void)fetchOptionsWithCompletion:(nullable void (^)(void))completion {
    __weak typeof(self)weakSelf = self;
    NSArray *optionTypes = @[@(INSCameraOptionsTypeStorageState),@(INSCameraOptionsTypeVideoEncode),@(INSCameraOptionsTypeStorageState)];
    [[INSCameraManager sharedManager].commandManager getOptionsWithTypes:optionTypes completion:^(NSError * _Nullable error, INSCameraOptions * _Nullable options, NSArray<NSNumber *> * _Nullable successTypes) {
        if (!options) {
            [weakSelf showAlertWith:@"Get options" message:error.description];
            completion();
            return ;
        }
        weakSelf.storageState = options.storageStatus;
        weakSelf.videoEncode = options.videoEncode;
        weakSelf.cardState = options.storageStatus;
        
        
        completion();
    }];
}

- (void)runMediaSession {
    if ([INSCameraManager sharedManager].cameraState != INSCameraStateConnected) {
        [[INSCameraManager socketManager] setup];
        return ;
    }

    self.isSuccess = YES;
    self.connectBtn.hidden = NO;
    
    __weak typeof(self)weakSelf = self;
    if (_mediaSession.running) {
        self.view.userInteractionEnabled = NO;
        [_mediaSession commitChangesWithCompletion:^(NSError * _Nullable error) {
            NSLog(@"commitChanges media session with error: %@",error);
            weakSelf.view.userInteractionEnabled = YES;
            if (error) {
                [weakSelf showAlertWith:@"commitChanges media failed" message:error.description];
            }
        }];
    }
    else {
        self.view.userInteractionEnabled = NO;
        [_mediaSession startRunningWithCompletion:^(NSError * _Nullable error) {
            NSLog(@"start running media session with error: %@",error);
            weakSelf.view.userInteractionEnabled = YES;
            if (error) {
                [weakSelf showAlertWith:@"start media failed" message:error.description];
                [weakSelf.previewPlayer playWithSmoothBuffer:NO];
            }
        }];
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if ([keyPath isEqualToString:@"cameraState"]) {
        INSCameraState state = [change[NSKeyValueChangeNewKey] unsignedIntegerValue];
        switch (state) {
            case INSCameraStateFound:
                break;
            case INSCameraStateConnected:
                [self runMediaSession];
                break;
            default:
                [_mediaSession stopRunningWithCompletion:nil];
                break;
        }
    }
}

#pragma mark INSCameraPreviewPlayerDelegate
- (NSString *)offsetToPlay:(INSCameraPreviewPlayer *)player {
    NSString *mediaOffset = [INSCameraManager sharedManager].currentCamera.settings.mediaOffset;
    if (([[INSCameraManager sharedManager].currentCamera.name isEqualToString:kInsta360CameraNameOneX]
         || [[INSCameraManager sharedManager].currentCamera.name isEqualToString:kInsta360CameraNameOneR]
         || [[INSCameraManager sharedManager].currentCamera.name isEqualToString:kInsta360CameraNameOneX2])
        && [INSLensOffset isValidOffset:mediaOffset]) {
        return [INSOffsetCalculator convertOffset:mediaOffset toType:INSOffsetConvertTypeOneX3040_2_2880];
    }
    
    return mediaOffset;
}

//ios获取剩余存储空间
-(void)usedSpaceAndfreeSpace{
    NSString* path = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)objectAtIndex:0] ;
    NSFileManager* fileManager = [[NSFileManager alloc ]init];
    NSDictionary *fileSysAttributes = [fileManager attributesOfFileSystemForPath:path error:nil];
    NSNumber *freeSpace = [fileSysAttributes objectForKey:NSFileSystemFreeSize];
    NSString  * str= [NSString stringWithFormat:@"%0.1fG",[freeSpace longLongValue]/1024.0/1024.0/1024.0];
    self.memoryLabel.text = str;
}

-(void)pushHousingResource {
    
    UIStoryboard *st = [UIStoryboard storyboardWithName:@"MobileAlbum" bundle:nil];
    MobileAlbumViewController *vc = [st instantiateViewControllerWithIdentifier:@"MobileAlbumViewController"];
    vc.state = MobileAlbumViewStateLeft;
    [self.navigationController pushViewController:vc animated:YES];

}

// 重写下面的方法，拦截手势返回
- (BOOL)navigationShouldPopOnGesture {
    // do something
    
    return NO;
}

//断开连接
-(void)closeConnect {
    
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];

    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"接続解除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
    
        
        [self.navigationController popViewControllerAnimated:YES];
       
    }];
    
    UIAlertAction *resetAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil];
    
    [alertController addAction:okAction];
    [alertController addAction:resetAction];
    
    [self presentViewController:alertController animated:YES completion:nil];
    
}

- (void)timerAction{
    
//    [self setupRenderView];
    

    
    if (self.isSuccess == NO) {
        self.timeNum = self.timeNum + 1;
        
        if (self.timeNum > 20) {
             [[DHHUDManager sharedManager] dismissHUDImmediatelyWithView:self.view];

            [[DHHUDManager sharedManager] showLoadingWithMessage:@"接続がタイムアウトしました。再試行してください" view:self.view];
            
            if (self.timeNum > 22) {
                [self.navigationController popViewControllerAnimated:YES];
            }
        }
        
        [self runMediaSession];
    }
    
    __weak typeof(self)weakSelf = self;
    NSArray *optionTypes = @[@(INSCameraOptionsTypeStorageState),@(INSCameraOptionsTypeVideoEncode),@(INSCameraOptionsTypeBatteryStatus)];
    [[INSCameraManager sharedManager].commandManager getOptionsWithTypes:optionTypes completion:^(NSError * _Nullable error, INSCameraOptions * _Nullable options, NSArray<NSNumber *> * _Nullable successTypes) {
        if (!options) {
//                [weakSelf showAlertWith:@"Get options" message:error.description];
            return ;
        }
        weakSelf.storageState = options.storageStatus;
        weakSelf.videoEncode = options.videoEncode;
        weakSelf.batteryStatus = options.batteryStatus;
        
        if (options.storageStatus.cardState == INSCameraCardStateNoCard) {
            [self showTitleString:@"Sdカードが検出されません"];
        }
        
        if (options.storageStatus.cardState == INSCameraCardStateNoSpace) {
            [self showTitleString:@"Sdカードがいっぱいで撮影できません"];
        }
        
        if (options.storageStatus.cardState == INSCameraCardStateUnknownError) {
            [self showTitleString:@"Sdカードが故障しています。カメラをチェックしてください"];
        }
        
        if (options.batteryStatus.batteryLevel < 20) {
            self.electricityView.backgroundColor = [UIColor redColor];
        }else {
            self.electricityView.backgroundColor = [UIColor whiteColor];
        }
        
        if (options.batteryStatus.powerType == INSCameraPowerTypeAdapter) {
            self.electricityView.hidden = YES;
            self.electricityImageView.image = [UIImage imageNamed:@"home_charging"];
            self.electricityLabel.text = @"充電中";
        }else {
            self.electricityView.hidden = NO;
            self.electricityImageView.image = [UIImage imageNamed:@"home_electricity"];
            
            self.electricityLabel.text = [NSString stringWithFormat:@"%d%%",(int)options.batteryStatus.batteryLevel];
            [self.electricityView mas_updateConstraints:^(MASConstraintMaker *make) {
                make.width.equalTo(@(0.13 * (int)options.batteryStatus.batteryLevel));
            }];
        }
 
    }];
}

@end
