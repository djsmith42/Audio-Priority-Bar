#import <Foundation/Foundation.h>
#import <ServiceManagement/ServiceManagement.h>

NS_ASSUME_NONNULL_BEGIN

@interface APBLaunchAtLoginController : NSObject

@property (nonatomic, readonly) BOOL isEnabled;
@property (nonatomic, readonly) BOOL requiresApproval;
@property (nonatomic, readonly, copy, nullable) NSString *errorMessage;
/// Called after any of the values above change.
@property (nonatomic, copy, nullable) void (^onChange)(void);

/// Uses `SMAppService.mainAppService`.
- (instancetype)init;
- (instancetype)initWithStatus:(SMAppServiceStatus (^)(void))status
                      register:(BOOL (^)(NSError **error))registerService
                    unregister:(BOOL (^)(NSError **error))unregisterService NS_DESIGNATED_INITIALIZER;

- (void)refresh;
- (void)setEnabled:(BOOL)enabled;

@end

NS_ASSUME_NONNULL_END
