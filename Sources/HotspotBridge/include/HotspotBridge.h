#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
/// Optional private-framework adapter. Never persists or logs hotspot credentials.
@interface STHotspotBrowser : NSObject
@property(nonatomic, copy, nullable) void (^devicesChanged)(NSArray<NSDictionary<NSString *, id> *> *devices);
- (BOOL)start;
- (void)stop;
- (void)connectIdentifier:(NSString *)identifier completion:(void (^)(BOOL success))completion;
@end
NS_ASSUME_NONNULL_END
