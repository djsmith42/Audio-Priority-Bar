#import "HeadphoneDetection.h"

@implementation APBHeadphoneDetection

+ (NSArray<NSString *> *)keywords {
    static NSArray<NSString *> *keywords;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        keywords = @[
            @"headphone", @"headset", @"earphone", @"earbud", @"earbuds", @"buds", @"pods",
            @"airpods", @"earpods", @"beats", @"powerbeats", @"beatsx", @"beats fit",
            @"beats solo", @"beats studio", @"wh-1000", @"wf-1000", @"linkbuds", @"inzone",
            @"galaxy buds", @"buds pro", @"buds live", @"buds fe", @"quietcomfort",
            @"qc ultra", @"qc45", @"qc35", @"soundsport", @"sport earbuds", @"momentum",
            @"hd 4", @"hd 5", @"pxc", @"jabra", @"elite", @"evolve", @"jbl tune",
            @"jbl live", @"jbl tour", @"jbl reflect", @"anker", @"soundcore",
            @"skullcandy", @"nothing ear", @"oneplus buds", @"pixel buds",
            @"huawei freebuds", @"oppo enco", @"technics eah", @"bowers", @"b&w px",
            @"denon perl", @"focal bathys", @"hifiman", @"shure aonic",
            @"audio-technica ath", @"beyerdynamic", @"marshall", @"bang & olufsen",
            @"b&o", @"akg", @"plantronics", @"poly", @"razer", @"steelseries", @"hyperx",
            @"logitech g pro", @"astro", @"corsair", @"1more", @"tozo", @"edifier",
            @"fiio", @"moondrop",
        ];
    });
    return keywords;
}

/// Product lines that are speakers even though a brand keyword above would
/// otherwise claim them. Entries must name a product line, never a brand:
/// excluding "marshall" or "anker" would misfile the headphones those same
/// brands make.
+ (NSArray<NSString *> *)speakerProducts {
    return @[@"jabra speak"];
}

+ (BOOL)name:(NSString *)name containsAnyOf:(NSArray<NSString *> *)keywords {
    NSString *normalized = name.lowercaseString;
    for (NSString *keyword in keywords) {
        if ([normalized containsString:keyword]) return YES;
    }
    return NO;
}

+ (BOOL)isHeadphone:(NSString *)name {
    return [self name:name containsAnyOf:self.keywords];
}

+ (BOOL)isKnownSpeaker:(NSString *)name {
    return [self name:name containsAnyOf:self.speakerProducts];
}

@end
