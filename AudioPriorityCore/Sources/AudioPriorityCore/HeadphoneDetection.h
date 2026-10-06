#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface APBHeadphoneDetection : NSObject

+ (BOOL)isHeadphone:(NSString *)name;

/// A product known to be a speaker regardless of what it reports about
/// itself. CoreAudio has no speakerphone terminal type, so a speakerphone
/// may describe itself as headphones, and only the product line settles it.
+ (BOOL)isKnownSpeaker:(NSString *)name;

@end

NS_ASSUME_NONNULL_END
