//
//  TTFSwH264Decoder.m
//  ffmpeg_codec_demo
//
//  Created by jiang on 2017/9/6.
//  Copyright © 2017年 t. All rights reserved.
//

#import "TTSwH264Decoder.h"
#import <UIKit/UIKit.h>
#import <libavcodec/avcodec.h>
#import <libswscale/swscale.h>
#import <libavutil/imgutils.h>

#import <CoreMedia/CoreMedia.h>

#define BUF_SIZE    4096

@interface TTSwH264Decoder () {
    AVPacket _avpkt;
    AVFrame *_pRGBFrame;        //帧对象
    AVFrame *_pYUVFrame;        //帧对象
    
    AVCodecParserContext *_avParserContext;
    AVCodec *_pCodecH264;       //解码器
    AVCodecContext *_ctx;       //解码器数据结构对象
    uint8_t *_yuv_buf;          //yuv图像数据区
    uint8_t *_rgb_buf;          //rgb图像数据区
    struct SwsContext *_scxt;   //图像格式转换对象
    
    uint8_t *_streambuf;        //h264 stream buffer
//    uint8_t *_outbuf;         //解码出来视频数据缓存
    int _nDataLen;              //h264 stream 数据区长度
    
    uint8_t *_pbuf;             //用以存放帧数据
    int _nOutSize;              //用以记录帧数据长度
    int _haveread;              //用以记录已读buf长度
    int _decodelen;             //解码器返回长度
    int _piclen;                //解码器返回图片长度
    int _piccount;              //输出图片计数
}

@end


@implementation TTSwH264Decoder

- (instancetype)init
{
    self = [super init];
    if (self) {
        [self setup];
    }
    return self;
}

- (void)dealloc {
    
    if (_pbuf) {
        free(_pbuf);
        _pbuf = NULL;
    }
    
    if (_yuv_buf) {
        free(_yuv_buf);
        _yuv_buf = NULL;
    }
    
    if (_rgb_buf) {
        free(_rgb_buf);
        _rgb_buf = NULL;
    }
    
    av_free(_pRGBFrame);
    av_free(_pYUVFrame);    //释放帧资源
    
    avcodec_close(_ctx);    //关闭解码器
    av_free(_ctx);
}

/**
 初始化 各种参数
 */
- (void)setup {
    avcodec_register_all();     //注册编解码器
    av_init_packet(&_avpkt);     //初始化包结构
    
    _pRGBFrame = av_frame_alloc();      //RGB帧数据赋值
    _pYUVFrame = av_frame_alloc();
    
    _pbuf = malloc(BUF_SIZE);           //初始化帧数据区
    _yuv_buf = malloc(BUF_SIZE);        //初始化YUV图像数据区
    _rgb_buf = malloc(BUF_SIZE);        //初始化RGB图像帧数据区
    
    _pCodecH264 = avcodec_find_decoder(AV_CODEC_ID_H264);     //查找h264解码器
    if (!_pCodecH264)
    {
        fprintf(stderr, "h264 codec not found\n");
        exit(1);
    }
    
    _avParserContext = av_parser_init(AV_CODEC_ID_H264);
    if (!_pCodecH264) return;
    _ctx = avcodec_alloc_context3(_pCodecH264);//函数用于分配一个AVCodecContext并设置默认值，如果失败返回NULL，并可用av_free()进行释放
    
    if (_pCodecH264->capabilities & CODEC_CAP_TRUNCATED)
        _ctx->flags |= CODEC_FLAG_TRUNCATED;    /* we do not send complete frames */
    if (avcodec_open2(_ctx, _pCodecH264, NULL) < 0) return;
    _nDataLen = 0;
}

- (void)setDelegate:(id<TTVideoDecodingDelegate>)delegate {
    _delegate = delegate;
}

#pragma mark - decode stream data
- (void)decode:(void *)data_buffer length:(int)length {
    
    if (!data_buffer || length == 0) {
        return;
    }
    
    _nDataLen = length;
    _streambuf = data_buffer;

    _haveread = 0;
    while (_nDataLen > 0) {
        int nLength = av_parser_parse2(_avParserContext,
                                       _ctx,
                                       &_yuv_buf,
                                       &_nOutSize,
                                       _streambuf + _haveread,
                                       _nDataLen,
                                       0, 0, 0);
        _nDataLen -= nLength;
        _haveread += nLength;
        
        if (_nOutSize <= 0) {
            continue;
        }
        
        _avpkt.size = _nOutSize;
        _avpkt.data = _yuv_buf;
        
        while (_avpkt.size > 0) {
            // _decodelen = avcodec_decode_video2(_ctx, _pYUVFrame, &_piclen, &_avpkt);
            int ret = avcodec_send_packet(_ctx, &_avpkt);
            if (ret < 0) {
                fprintf(stderr, "decode video packet error\n");
                av_packet_unref(&_avpkt);
                break;
            }
            
            ret = avcodec_receive_frame(_ctx, _pYUVFrame);
            if (ret < 0) {
                fprintf(stderr, "avcodec_receive_frame error\n");
                break;
            }
            
            //                    if (_decodelen < 0) {
            //                        break;
            //                    }
            
            //                    if (_piclen) {
            _scxt = sws_getContext(_ctx->width,
                                   _ctx->height,
                                   AV_PIX_FMT_YUV420P, //_ctx->pix_fmt,
                                   _ctx->width,
                                   _ctx->height,
                                   AV_PIX_FMT_NV12,
                                   SWS_FAST_BILINEAR,
                                   NULL, NULL, NULL);
            
            if (_scxt) {
                avpicture_fill((AVPicture*)_pRGBFrame, _rgb_buf, AV_PIX_FMT_NV12, _ctx->width, _ctx->height);
                
                if (avpicture_alloc((AVPicture*)_pRGBFrame, AV_PIX_FMT_NV12, _ctx->width, _ctx->height) >= 0) {
                    sws_scale(_scxt,
                              (const uint8_t* const*)_pYUVFrame->data,
                              _pYUVFrame->linesize,
                              0,
                              _ctx->height,
                              _pRGBFrame->data,
                              _pRGBFrame->linesize);
                    
                    //读取解码后的数据
                    [self rgbFrame2Image:_pRGBFrame size:CGSizeMake(_ctx->width, _ctx->height)];
                }
                
                sws_freeContext(_scxt);//释放格式转换器资源
                avpicture_free((AVPicture *)_pRGBFrame);//释放帧资源
                av_packet_unref(&_avpkt);//释放本次读取的帧内存
            }
            //                    }
            //                    _avpkt.size -= _decodelen;
            //                    _avpkt.data += _decodelen;
        }
    }
}

//+ (CVPixelBufferRef)NV12ToPixelBuffer:(AVFrame *)yuv_frame width:(size_t)width height:(size_t)height {
//    
//    NSDictionary *pixelAttributes = @{(id)kCVPixelBufferIOSurfacePropertiesKey : @{}};
//    CVPixelBufferRef pixelBuffer = NULL;
//    CVReturn result = CVPixelBufferCreate(kCFAllocatorDefault,
//                                          width,
//                                          height,
//                                          kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
//                                          (__bridge CFDictionaryRef)(pixelAttributes),
//                                          &pixelBuffer);
//    
//    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
//    uint8_t *yDestPlane = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
//    memcpy(yDestPlane, yPlane, size.width * size.height);
//    uint8_t *uvDestPlane = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1);
//    memcpy(uvDestPlane, uvPlane, numberOfElementsForChroma);
//    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
//    
//    if (result != kCVReturnSuccess) {
//        NSLog(@"Unable to create cvpixelbuffer %d", result);
//        return NULL;
//    }
////    CIImage *coreImage = [CIImage imageWithCVPixelBuffer:pixelBuffer]; //success!
////    CVPixelBufferRelease(pixelBuffer);
//    
//    return pixelBuffer;
//}

/**
 avframe to UIImage

 @param rgb_frame - frame data
 @param size - width and height
 */
- (void)rgbFrame2Image:(AVFrame *)rgb_frame size:(CGSize)size {
    CFDataRef cfData = CFDataCreate(kCFAllocatorDefault, rgb_frame->data[0], rgb_frame->linesize[0] * size.height);
    CGDataProviderRef provider = CGDataProviderCreateWithCFData(cfData);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    
    CGImageRef imageRef = CGImageCreate(size.width,
                                        size.height,
                                        8,
                                        3 * 8,      //fmt rgb24
                                        rgb_frame->linesize[0],
                                        colorSpace,
                                        kCGBitmapByteOrderDefault,
                                        provider,
                                        NULL,
                                        NO,
                                        kCGRenderingIntentDefault);
    
    UIImage *image = [UIImage imageWithCGImage:imageRef];
    
    __weak typeof(self) wself = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(wself) sself = wself;
        if (!sself) {
            return ;
        }

        [sself.delegate videoDecoder:sself videoFrame:image];
    });
    
    CGColorSpaceRelease(colorSpace);
    CGImageRelease(imageRef);
    CGDataProviderRelease(provider);
    CFRelease(cfData);
}

@end
