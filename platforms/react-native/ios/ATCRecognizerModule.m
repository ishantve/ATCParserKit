//
//  ATCRecognizerModule.m
//  @ishant89/atc-parser-kit
//
//  Exposes the Swift ATCRecognizerModule to the React Native bridge.
//

#import <React/RCTBridgeModule.h>

@interface RCT_EXTERN_MODULE(ATCRecognizerModule, NSObject)

RCT_EXTERN_METHOD(createRecognizer:(NSString *)templatesJSON
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(releaseRecognizer:(nonnull NSNumber *)handle
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(recognize:(nonnull NSNumber *)handle
                  transcript:(NSString *)transcript
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(diagnostics:(nonnull NSNumber *)handle
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

@end
