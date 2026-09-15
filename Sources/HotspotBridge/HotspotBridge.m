#import "HotspotBridge.h"
#import <CoreWLAN/CoreWLAN.h>
#import <dlfcn.h>
@interface NSObject (STPrivateHotspot)
- (void)startBrowsing;
- (void)stopBrowsing;
- (void)setDelegate:(id)delegate;
- (void)enableRemoteHotspotForDevice:(id)device withCompletionHandler:(void (^)(id))completion;
- (NSString *)cellularProtocolString;
@end
@interface STHotspotBrowser ()
@property(nonatomic, strong) NSObject *session;
@property(nonatomic, strong) NSDictionary<NSString *, id> *devices;
@property(nonatomic) NSUInteger generation;
@end
@implementation STHotspotBrowser
- (BOOL)start {
    if (self.session) return YES;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dlopen("/System/Library/PrivateFrameworks/Sharing.framework/Sharing", RTLD_LAZY);
        dlopen("/System/Library/PrivateFrameworks/WiFiKit.framework/WiFiKit", RTLD_LAZY);
    });
    Class cls=NSClassFromString(@"SFRemoteHotspotSession");
    if (!cls || ![cls instancesRespondToSelector:@selector(startBrowsing)] ||
        ![cls instancesRespondToSelector:@selector(stopBrowsing)] ||
        ![cls instancesRespondToSelector:@selector(setDelegate:)] ||
        ![cls instancesRespondToSelector:@selector(enableRemoteHotspotForDevice:withCompletionHandler:)]) return NO;
    @try {
        self.session=[[cls alloc] init];
        if (!self.session) return NO;
        [self.session setDelegate:(id)self];
        [self.session startBrowsing];
        return YES;
    } @catch(NSException *exception) { [self stop]; return NO; }
}
- (void)stop {
    self.generation++;
    @try { [self.session stopBrowsing]; [self.session setDelegate:nil]; } @catch(NSException *exception) {}
    self.session=nil; self.devices=nil;
}
- (void)dealloc {
    @try { [_session stopBrowsing]; [_session setDelegate:nil]; } @catch(NSException *exception) {}
}
- (void)session:(id)session updatedFoundDevices:(NSArray *)devices {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (session!=self.session) return;
        NSMutableDictionary *raw=[NSMutableDictionary dictionary];
        NSMutableArray *rows=[NSMutableArray array];
        for(id device in devices) {
            @try {
                NSString *identifier=[device valueForKey:@"deviceIdentifier"];
                NSString *name=[device valueForKey:@"deviceName"];
                if (![identifier isKindOfClass:NSString.class] || !identifier.length || ![name isKindOfClass:NSString.class]) continue;
                raw[identifier]=device;
                NSMutableDictionary *row=[@{@"id":identifier,@"name":name} mutableCopy];
                for(NSString *key in @[@"batteryLife",@"signalStrength"]) {
                    id value=[device valueForKey:key];
                    if ([value isKindOfClass:NSNumber.class]) row[key]=value;
                }
                if ([device respondsToSelector:@selector(cellularProtocolString)]) {
                    id value=[device cellularProtocolString];
                    if ([value isKindOfClass:NSString.class]) row[@"cellular"]=value;
                }
                [rows addObject:row];
            } @catch(NSException *exception) { continue; }
        }
        self.devices=raw;
        if(self.devicesChanged) self.devicesChanged(rows);
    });
}
- (void)connectIdentifier:(NSString *)identifier completion:(void (^)(BOOL))completion {
    id device=self.devices[identifier];
    if(!device || !self.session) {completion(NO);return;}
    NSUInteger generation=++self.generation;
    __block BOOL finished=NO;
    __block BOOL associating=NO;
    __block BOOL receivedInfo=NO;
    void (^finish)(BOOL)=^(BOOL success){
        if(finished || generation!=self.generation) return;
        finished=YES; completion(success);
    };
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 45*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        if(generation==self.generation && !finished && !associating) {finish(NO);self.generation++;}
    });
    @try {
        [self.session enableRemoteHotspotForDevice:device withCompletionHandler:^(id info){
            dispatch_async(dispatch_get_main_queue(), ^{
                if(finished || receivedInfo || generation!=self.generation) return;
                receivedInfo=YES;
                NSString *name=nil,*password=nil;
                @try {
                    if([info respondsToSelector:NSSelectorFromString(@"name")] && [info respondsToSelector:NSSelectorFromString(@"password")]) {
                        name=[info valueForKey:@"name"]; password=[info valueForKey:@"password"];
                    }
                } @catch(NSException *exception) {}
                if(![name isKindOfClass:NSString.class] || !name.length || ![password isKindOfClass:NSString.class]) {finish(NO);return;}
                dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
                    CWInterface *interface=CWWiFiClient.sharedWiFiClient.interface;
                    BOOL success=NO;
                    for(int attempt=0;attempt<4;attempt++) {
                        __block BOOL cancelled;
                        dispatch_sync(dispatch_get_main_queue(),^{cancelled=finished || generation!=self.generation;});
                        if(cancelled) return;
                        NSSet *networks=[interface scanForNetworksWithSSID:[name dataUsingEncoding:NSUTF8StringEncoding] error:nil];
                        CWNetwork *target=nil;
                        for(CWNetwork *network in networks) if([network.ssid isEqualToString:name]) {target=network;break;}
                        if(target) {
                            dispatch_sync(dispatch_get_main_queue(),^{
                                cancelled=finished || generation!=self.generation;
                                if(!cancelled) associating=YES;
                            });
                            if(cancelled) return;
                            success=[interface associateToNetwork:target password:password error:nil];
                            break;
                        }
                        if(attempt<3) [NSThread sleepForTimeInterval:3];
                    }
                    dispatch_async(dispatch_get_main_queue(),^{finish(success);});
                });
            });
        }];
    } @catch(NSException *exception) {finish(NO);}
}
@end
