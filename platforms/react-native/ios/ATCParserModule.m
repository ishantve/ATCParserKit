//
//  ATCParserModule.m
//  @ishant89/atc-parser-kit
//
//  Exposes the Swift ATCParserModule to the React Native bridge.
//

#import <React/RCTBridgeModule.h>

@interface RCT_EXTERN_MODULE(ATCParserModule, NSObject)

RCT_EXTERN_METHOD(parse:(NSString *)command
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

@end
